import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../crypto/certificate_manager.dart';
import '../models/manifest.dart';
import '../models/transfer.dart';
import 'protocol.dart';

class PendingTransfer {
  PendingTransfer({required this.manifest, required this.stagingDirectory});

  final TransferManifest manifest;
  final String stagingDirectory;
  bool accepted = false;
  String saveDirectory = '';
  int transferredBytes = 0;
  final Map<String, String> checksums = {};
}

/// HTTPS receiver. TLS identity is the device certificate; API calls also
/// require a session token obtained from a successful PIN pairing.
class WishareServer {
  WishareServer({required this.identity, required this.downloadDirectory});

  final DeviceIdentity identity;
  final String downloadDirectory;

  HttpServer? _server;
  String? _pin;
  final Map<String, String> _tokens = {};
  final Map<String, PendingTransfer> _pending = {};

  final StreamController<TransferManifest> _offers =
      StreamController<TransferManifest>.broadcast();
  final StreamController<Transfer> _updates =
      StreamController<Transfer>.broadcast();
  final StreamController<Map<String, dynamic>> _pairings =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get pairings => _pairings.stream;
  Stream<TransferManifest> get offers => _offers.stream;
  Stream<Transfer> get updates => _updates.stream;
  String? get pin => _pin;
  bool get isRunning => _server != null;

  String generatePin() {
    _pin = newPin();
    return _pin!;
  }

  /// [port] is injectable so tests can bind an ephemeral port instead of the
  /// fixed LAN port used in production.
  Future<void> start({int port = WiProtocol.port}) async {
    if (_server != null) return;
    _server = await HttpServer.bindSecure(
      InternetAddress.anyIPv4,
      port,
      identity.securityContext(),
      shared: true,
    );
    _server!.listen(_handle);
  }

  void accept(String transferId, String saveDirectory) {
    final pending = _pending[transferId];
    if (pending == null) return;
    pending.accepted = true;
    pending.saveDirectory = saveDirectory;
    _emit(pending, TransferStatus.queued);
  }

  void decline(String transferId) {
    final pending = _pending.remove(transferId);
    if (pending == null) return;
    _deleteStaging(pending);
    _emitTransfer(
      Transfer(
        id: transferId,
        direction: TransferDirection.incoming,
        peerId: pending.manifest.senderId,
        peerName: pending.manifest.senderName,
        files: pending.manifest.entries,
        totalBytes: pending.manifest.totalBytes,
        createdAt: DateTime.now(),
        status: TransferStatus.declined,
        finishedAt: DateTime.now(),
      ),
    );
  }

  void cancel(String transferId) {
    final pending = _pending.remove(transferId);
    if (pending == null) return;
    _deleteStaging(pending);
    _emitTransfer(
      Transfer(
        id: transferId,
        direction: TransferDirection.incoming,
        peerId: pending.manifest.senderId,
        peerName: pending.manifest.senderName,
        files: pending.manifest.entries,
        totalBytes: pending.manifest.totalBytes,
        createdAt: DateTime.now(),
        status: TransferStatus.cancelled,
        finishedAt: DateTime.now(),
      ),
    );
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> dispose() async {
    await stop();
    await _offers.close();
    await _updates.close();
    await _pairings.close();
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      switch (request.method) {
        case 'GET' when request.uri.path == '/info':
          _writeJson(response, 200, {
            'id': identity.id,
            'name': identity.name,
            'fingerprint': identity.fingerprint,
            'version': WiProtocol.version,
          });
        case 'POST' when request.uri.path == '/pair':
          await _pair(request, response);
        case 'POST' when request.uri.path == '/request':
          await _offer(request, response);
        case 'GET' when request.uri.path == '/status':
          _status(request, response);
        case 'PUT' when request.uri.path == '/chunk':
          await _chunk(request, response);
        case 'POST' when request.uri.path == '/complete':
          await _complete(request, response);
        case 'POST' when request.uri.path == '/cancel':
          await _localAction(request, response);
        default:
          _writeJson(response, 404, {'error': 'Not found'});
      }
    } on FormatException catch (error) {
      _writeJson(response, 400, {'error': error.message});
    } on Object catch (error) {
      _writeJson(response, 500, {'error': error.toString()});
    }
  }

  String? _authorized(HttpRequest request) {
    final id = request.headers.value(WiProtocol.headerDeviceId);
    final token = request.headers.value(WiProtocol.headerToken);
    if (id == null || token == null) return null;
    if (_tokens[id] != token) return null;
    return id;
  }

  Future<void> _pair(HttpRequest request, HttpResponse response) async {
    final body = await _readJson(request);
    final pin = body['pin'] as String?;
    if (_pin == null || pin == null || pin != _pin) {
      _writeJson(response, 403, {'error': 'Incorrect pairing PIN'});
      return;
    }
    final id = body['id'] as String?;
    if (id == null) {
      _writeJson(response, 400, {'error': 'Missing device id'});
      return;
    }
    final token = const Uuid4().newId();
    _tokens[id] = token;
    _pin = null; // single-use PIN
    _pairings.add({'id': id, 'name': body['name'] ?? 'Wishare device'});
    _writeJson(response, 200, {
      'token': token,
      'fingerprint': identity.fingerprint,
    });
  }

  Future<void> _offer(HttpRequest request, HttpResponse response) async {
    final id = _authorized(request);
    if (id == null) {
      _writeJson(response, 401, {'error': 'Not paired'});
      return;
    }
    final manifest = TransferManifest.fromJson(await _readJson(request));
    if (manifest.senderId != id) {
      _writeJson(response, 403, {'error': 'Identity mismatch'});
      return;
    }
    final staging = '$downloadDirectory/.staging/${manifest.transferId}';
    await Directory(staging).create(recursive: true);
    for (final entry in manifest.entries.where((e) => e.isDirectory)) {
      await Directory('$staging/${SafePath.sanitise(entry.relativePath)}')
          .create(recursive: true);
    }
    _pending[manifest.transferId] = PendingTransfer(
      manifest: manifest,
      stagingDirectory: staging,
    );
    _offers.add(manifest);
    _writeJson(response, 202, {'transferId': manifest.transferId});
  }

  void _status(HttpRequest request, HttpResponse response) {
    final id = _authorized(request);
    if (id == null) {
      _writeJson(response, 401, {'error': 'Not paired'});
      return;
    }
    final transferId = request.uri.queryParameters['transferId'];
    final path = request.uri.queryParameters['path'];
    final pending = transferId == null ? null : _pending[transferId];
    if (pending == null) {
      _writeJson(response, 404, {'error': 'Unknown transfer'});
      return;
    }
    var offset = 0;
    if (path != null) {
      final relative = SafePath.sanitise(decodePath(path));
      final file = File('${pending.stagingDirectory}/$relative');
      if (file.existsSync()) offset = file.lengthSync();
    }
    _writeJson(response, 200, {
      'accepted': pending.accepted,
      'transferredBytes': pending.transferredBytes,
      'offset': offset,
    });
  }

  Future<void> _chunk(HttpRequest request, HttpResponse response) async {
    final id = _authorized(request);
    if (id == null) {
      _writeJson(response, 401, {'error': 'Not paired'});
      return;
    }
    final transferId = request.uri.queryParameters['transferId'];
    final path = request.uri.queryParameters['path'];
    final offset = int.tryParse(request.uri.queryParameters['offset'] ?? '');
    final pending = transferId == null ? null : _pending[transferId];
    if (pending == null || path == null || offset == null) {
      _writeJson(response, 400, {'error': 'Invalid chunk request'});
      return;
    }
    if (!pending.accepted) {
      _writeJson(response, 409, {'error': 'Transfer not accepted'});
      return;
    }
    final relativePath = SafePath.sanitise(decodePath(path));
    final file = File('${pending.stagingDirectory}/$relativePath');
    await file.parent.create(recursive: true);
    final currentLength = file.existsSync() ? file.lengthSync() : 0;
    if (currentLength != offset) {
      _writeJson(response, 409, {
        'error': 'Offset mismatch',
        'offset': currentLength,
      });
      return;
    }
    final bytes = await _readBytes(request);
    if (!file.existsSync()) await file.create(recursive: true);
    // `writeOnly` truncates on open, which would destroy resumed bytes.
    // Append mode never truncates; since offset == current file length, the
    // append point is exactly the requested offset.
    final raf = await file.open(mode: FileMode.writeOnlyAppend);
    try {
      await raf.writeFrom(bytes);
    } finally {
      await raf.close();
    }
    pending.transferredBytes += bytes.length;
    _emit(pending, TransferStatus.transferring);
    _writeJson(response, 200, {'received': bytes.length});
  }

  Future<void> _complete(HttpRequest request, HttpResponse response) async {
    final id = _authorized(request);
    if (id == null) {
      _writeJson(response, 401, {'error': 'Not paired'});
      return;
    }
    final body = await _readJson(request);
    final transferId = body['transferId'] as String?;
    final pending = transferId == null ? null : _pending[transferId];
    if (pending == null) {
      _writeJson(response, 404, {'error': 'Unknown transfer'});
      return;
    }
    _emit(pending, TransferStatus.verifying);

    final targetRoot = Directory(
      pending.saveDirectory.isEmpty ? downloadDirectory : pending.saveDirectory,
    );
    await targetRoot.create(recursive: true);
    final problems = <String>[];
    for (final entry in pending.manifest.entries.where((e) => !e.isDirectory)) {
      final relative = SafePath.sanitise(entry.relativePath);
      final staged = File('${pending.stagingDirectory}/$relative');
      if (!staged.existsSync()) {
        problems.add('Missing file: $relative');
        continue;
      }
      final digest = sha256.convert(staged.readAsBytesSync()).toString();
      if (entry.checksum != null && digest != entry.checksum) {
        problems.add('Checksum mismatch: $relative');
        continue;
      }
      final target = _uniqueTarget(targetRoot.path, relative);
      await target.parent.create(recursive: true);
      await staged.rename(target.path);
    }
    for (final entry in pending.manifest.entries.where((e) => e.isDirectory)) {
      final relative = SafePath.sanitise(entry.relativePath);
      await Directory('${targetRoot.path}/$relative').create(recursive: true);
    }
    _deleteStaging(pending);
    _pending.remove(transferId);

    if (problems.isEmpty) {
      _emitTransfer(
        Transfer(
          id: pending.manifest.transferId,
          direction: TransferDirection.incoming,
          peerId: pending.manifest.senderId,
          peerName: pending.manifest.senderName,
          files: pending.manifest.entries,
          totalBytes: pending.manifest.totalBytes,
          createdAt: DateTime.now(),
          status: TransferStatus.completed,
          transferredBytes: pending.manifest.totalBytes,
          finishedAt: DateTime.now(),
          saveDirectory: targetRoot.path,
        ),
      );
      _writeJson(response, 200, {'verified': true});
    } else {
      _emitTransfer(
        Transfer(
          id: pending.manifest.transferId,
          direction: TransferDirection.incoming,
          peerId: pending.manifest.senderId,
          peerName: pending.manifest.senderName,
          files: pending.manifest.entries,
          totalBytes: pending.manifest.totalBytes,
          createdAt: DateTime.now(),
          status: TransferStatus.failed,
          error: problems.join('\n'),
          finishedAt: DateTime.now(),
        ),
      );
      _writeJson(response, 422, {'error': problems.join('\n')});
    }
  }

  Future<void> _localAction(HttpRequest request, HttpResponse response) async {
    final body = await _readJson(request);
    final action = body['action'] as String?;
    final transferId = body['transferId'] as String?;
    if (transferId == null) {
      _writeJson(response, 400, {'error': 'Missing transfer id'});
      return;
    }
    if (action == 'decline') {
      decline(transferId);
    } else if (action == 'cancel') {
      cancel(transferId);
    } else {
      _writeJson(response, 400, {'error': 'Unknown action'});
      return;
    }
    _writeJson(response, 200, {'ok': true});
  }

  File _uniqueTarget(String root, String relative) {
    final base = File('$root/$relative');
    if (!base.existsSync()) return base;
    final suffix = DateTime.now().microsecondsSinceEpoch;
    final dot = base.path.lastIndexOf('.');
    return dot > base.path.lastIndexOf(Platform.pathSeparator)
        ? File(
            '${base.path.substring(0, dot)}-$suffix${base.path.substring(dot)}',
          )
        : File('${base.path}-$suffix');
  }

  void _deleteStaging(PendingTransfer pending) {
    final dir = Directory(pending.stagingDirectory);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }

  void _emit(PendingTransfer pending, TransferStatus status) {
    _emitTransfer(
      Transfer(
        id: pending.manifest.transferId,
        direction: TransferDirection.incoming,
        peerId: pending.manifest.senderId,
        peerName: pending.manifest.senderName,
        files: pending.manifest.entries,
        totalBytes: pending.manifest.totalBytes,
        createdAt: DateTime.now(),
        status: status,
        transferredBytes: pending.transferredBytes,
      ),
    );
  }

  void _emitTransfer(Transfer transfer) => _updates.add(transfer);

  static Future<Map<String, dynamic>> _readJson(HttpRequest request) async {
    final bytes = await _readBytes(request);
    return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  }

  static Future<Uint8List> _readBytes(HttpRequest request) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in request) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  static void _writeJson(HttpResponse response, int status, Object body) {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
    response.close();
  }
}
