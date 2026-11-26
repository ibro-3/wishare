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

  /// Ended offers stay addressable briefly so a polling sender receives an
  /// explicit decline/cancel instead of a bare 404.
  bool declined = false;
  String? endStatus;
  DateTime? endedAt;

  Future<void> _writeTail = Future<void>.value();
  int _writesInFlight = 0;

  bool get hasPendingWrites => _writesInFlight > 0;

  /// Runs [action] once all earlier writes for this transfer have settled.
  /// The offset check, append and progress update happen inside the queue, so
  /// concurrent chunks for the same file cannot interleave or race.
  Future<T> serializeWrite<T>(Future<T> Function() action) {
    _writesInFlight++;
    final result = _writeTail.then((_) async {
      try {
        return await action();
      } finally {
        _writesInFlight--;
      }
    });
    // Keep the chain alive even when one chunk fails.
    _writeTail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }
}

/// HTTPS receiver. TLS identity is the device certificate; API calls also
/// require a session token obtained from a successful PIN pairing.
class WishareServer {
  WishareServer({required this.identity, required this.downloadDirectory});

  static const int _maxEntries = 10000;
  static const int _maxTotalBytes = 20 * 1024 * 1024 * 1024;
  static const int _maxPathLength = 4096;
  static const int _maxTokens = 128;
  static const Duration _tokenLifetime = Duration(days: 30);
  static const int _maxEndedTransfers = 100;
  static const Duration _endedTransferLifetime = Duration(hours: 1);

  final DeviceIdentity identity;
  String downloadDirectory;

  HttpServer? _server;
  String? _pin;
  final Map<String, String> _tokens = {};
  final Map<String, DateTime> _tokenTouched = {};
  final Map<String, PendingTransfer> _pending = {};
  final Map<String, PendingTransfer> _ended = {};

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

  /// The bound port; useful after `start(port: 0)` in tests.
  int get port => _server?.port ?? WiProtocol.port;

  String generatePin() {
    _pin = newPin();
    return _pin!;
  }

  /// Change where completed files land without restarting the server.
  /// Active transfers keep the directory chosen when they were accepted.
  void updateDownloadDirectory(String directory) {
    downloadDirectory = directory;
  }

  /// [port] is injectable so tests can bind an ephemeral port instead of the
  /// fixed LAN port used in production.
  Future<void> start({int port = WiProtocol.port}) async {
    if (_server != null) return;
    final server = await HttpServer.bindSecure(
      InternetAddress.anyIPv4,
      port,
      identity.securityContext(),
      shared: true,
    );
    try {
      server.listen(_handle);
      _server = server;
    } on Object {
      // Do not leave a bound port behind if listener setup fails.
      await server.close(force: true);
      rethrow;
    }
  }

  void accept(String transferId, String saveDirectory) {
    final pending = _pending[transferId];
    if (pending == null || pending.declined) return;
    pending.accepted = true;
    pending.saveDirectory = saveDirectory;
    _emit(pending, TransferStatus.queued);
  }

  void decline(String transferId) =>
      _endTransfer(transferId, TransferStatus.declined, 'declined');

  void cancel(String transferId) =>
      _endTransfer(transferId, TransferStatus.cancelled, 'cancelled');

  void _endTransfer(
    String transferId,
    TransferStatus status,
    String statusText,
  ) {
    final pending = _pending.remove(transferId);
    if (pending == null) return;
    pending
      ..declined = true
      ..endStatus = statusText
      ..endedAt = DateTime.now();
    _ended[transferId] = pending;
    _pruneEnded();
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
        status: status,
        finishedAt: DateTime.now(),
      ),
    );
  }

  void _pruneEnded() {
    final cutoff = DateTime.now().subtract(_endedTransferLifetime);
    _ended.removeWhere(
      (_, pending) => (pending.endedAt ?? cutoff).isBefore(cutoff),
    );
    while (_ended.length >= _maxEndedTransfers) {
      final now = DateTime.now();
      final oldest = _ended.entries.reduce((a, b) {
        final aTime = a.value.endedAt ?? now;
        final bTime = b.value.endedAt ?? now;
        return aTime.isBefore(bTime) ? a : b;
      }).key;
      _ended.remove(oldest);
    }
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
    // Treat this as "last seen": active tokens stay alive, idle ones expire.
    _tokenTouched[id] = DateTime.now();
    return id;
  }

  void _pruneTokens() {
    final cutoff = DateTime.now().subtract(_tokenLifetime);
    final expired = _tokenTouched.entries
        .where((entry) => entry.value.isBefore(cutoff))
        .map((entry) => entry.key)
        .toList();
    for (final id in expired) {
      _tokens.remove(id);
      _tokenTouched.remove(id);
    }
    while (_tokens.length >= _maxTokens) {
      final oldest = _tokenTouched.entries
          .reduce((a, b) => a.value.isBefore(b.value) ? a : b)
          .key;
      _tokens.remove(oldest);
      _tokenTouched.remove(oldest);
    }
  }

  Future<void> _pair(HttpRequest request, HttpResponse response) async {
    final body = await _readJson(request);
    final pin = body['pin'] as String?;
    if (_pin == null || pin == null || pin != _pin) {
      _writeJson(response, 403, {'error': 'Incorrect pairing PIN'});
      return;
    }
    final id = body['id'] as String?;
    if (id == null || id.isEmpty) {
      _writeJson(response, 400, {'error': 'Missing device id'});
      return;
    }
    final token = const Uuid4().newId();
    // Re-pairing replaces the old token and prunes stale sessions.
    _tokens.remove(id);
    _tokenTouched.remove(id);
    _pruneTokens();
    _tokens[id] = token;
    _tokenTouched[id] = DateTime.now();
    _pin = null; // single-use PIN

    // TOFU: pin the *sender's* identity, never our own. Prefer the TLS client
    // certificate; fall back to a validated header when no client cert is
    // presented (a common situation with self-signed certs).
    String? senderFingerprint;
    try {
      final certificate = request.certificate;
      if (certificate != null) {
        final observed = normaliseFingerprint(
          sha256.convert(certificate.der).toString(),
        );
        if (isValidFingerprint(observed)) senderFingerprint = observed;
      }
    } on Object {
      // Certificate access is best-effort; the header is the fallback.
    }
    senderFingerprint ??= _headerFingerprint(request);

    _pairings.add({
      'id': id,
      'name': body['name'] ?? 'Wishare device',
      'fingerprint': senderFingerprint,
    });
    _writeJson(response, 200, {
      'token': token,
      'fingerprint': identity.fingerprint,
    });
  }

  String? _headerFingerprint(HttpRequest request) {
    final value = request.headers.value(WiProtocol.headerFingerprint);
    if (value == null || !isValidFingerprint(value)) return null;
    return normaliseFingerprint(value);
  }

  Future<void> _offer(HttpRequest request, HttpResponse response) async {
    final id = _authorized(request);
    if (id == null) {
      _writeJson(response, 401, {'error': 'Not paired'});
      return;
    }
    final body = await _readJson(request);
    final transferId = body['transferId'] as String?;
    if (transferId == null || !isValidTransferId(transferId)) {
      throw const FormatException('Invalid transfer id');
    }
    if (_pending.containsKey(transferId) || _ended.containsKey(transferId)) {
      throw const FormatException('Duplicate transfer id');
    }

    final manifest = TransferManifest.fromJson(body);
    if (manifest.senderId != id) {
      _writeJson(response, 403, {'error': 'Identity mismatch'});
      return;
    }
    if (manifest.entries.length > _maxEntries) {
      throw FormatException('Too many entries (limit $_maxEntries)');
    }
    if (manifest.totalBytes < 0 || manifest.totalBytes > _maxTotalBytes) {
      throw const FormatException('Transfer size out of range');
    }
    final safePaths = <String>[];
    for (final entry in manifest.entries) {
      final relative = SafePath.sanitise(entry.relativePath);
      if (relative.isEmpty || relative.length > _maxPathLength) {
        throw const FormatException('Unsafe or overlong path');
      }
      if (entry.size < 0) {
        throw const FormatException('Invalid file size');
      }
      safePaths.add(relative);
    }

    final staging =
        '$downloadDirectory/.staging/${SafePath.sanitise(transferId)}';
    await Directory(staging).create(recursive: true);
    for (var i = 0; i < manifest.entries.length; i++) {
      if (!manifest.entries[i].isDirectory) continue;
      await Directory('$staging/${safePaths[i]}').create(recursive: true);
    }
    _pending[transferId] = PendingTransfer(
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
    final pending = transferId == null
        ? null
        : (_pending[transferId] ?? _ended[transferId]);
    if (pending == null || pending.manifest.senderId != id) {
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
      'declined': pending.declined,
      'status': pending.declined
          ? (pending.endStatus ?? 'declined')
          : (pending.accepted ? 'accepted' : 'pending'),
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
    if (pending == null || path == null || offset == null || offset < 0) {
      _writeJson(response, 400, {'error': 'Invalid chunk request'});
      return;
    }
    if (pending.manifest.senderId != id || pending.declined) {
      _writeJson(response, 403, {'error': 'Transfer not active'});
      return;
    }
    if (!pending.accepted) {
      _writeJson(response, 409, {'error': 'Transfer not accepted'});
      return;
    }
    final relativePath = SafePath.sanitise(decodePath(path));
    final bytes = await _readBytes(request);

    final outcome = await pending.serializeWrite(() async {
      final file = File('${pending.stagingDirectory}/$relativePath');
      await file.parent.create(recursive: true);
      final currentLength = file.existsSync() ? file.lengthSync() : 0;
      if (currentLength != offset) {
        return (mismatch: currentLength, received: 0);
      }
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
      return (mismatch: null, received: bytes.length);
    });

    if (outcome.mismatch != null) {
      _writeJson(response, 409, {
        'error': 'Offset mismatch',
        'offset': outcome.mismatch,
      });
      return;
    }
    _writeJson(response, 200, {'received': outcome.received});
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
    if (pending == null || pending.manifest.senderId != id) {
      _writeJson(response, 404, {'error': 'Unknown transfer'});
      return;
    }
    if (pending.hasPendingWrites) {
      _writeJson(response, 409, {'error': 'Writes still in progress'});
      return;
    }
    if (pending.declined) {
      _writeJson(response, 409, {'error': 'Transfer not active'});
      return;
    }
    _emit(pending, TransferStatus.verifying);

    final targetRoot = Directory(
      pending.saveDirectory.isEmpty ? downloadDirectory : pending.saveDirectory,
    );
    await targetRoot.create(recursive: true);
    final problems = <String>[];
    final files = pending.manifest.entries
        .where((entry) => !entry.isDirectory)
        .toList();
    final targets = <File?>[];

    for (final entry in files) {
      final relative = SafePath.sanitise(entry.relativePath);
      final staged = File('${pending.stagingDirectory}/$relative');
      if (!staged.existsSync()) {
        problems.add('Missing file: $relative');
        targets.add(null);
        continue;
      }
      final digest = await _checksum(staged);
      if (entry.checksum != null && digest != entry.checksum) {
        problems.add('Checksum mismatch: $relative');
        targets.add(null);
        continue;
      }
      final target = _uniqueTarget(targetRoot.path, relative);
      await target.parent.create(recursive: true);
      try {
        await staged.rename(target.path);
      } on FileSystemException {
        // Cross-device rename is not supported; stream a copy instead.
        await _copyFile(staged, target);
      }
      targets.add(target);
    }

    for (final entry in pending.manifest.entries.where((e) => e.isDirectory)) {
      final relative = SafePath.sanitise(entry.relativePath);
      await Directory('${targetRoot.path}/$relative').create(recursive: true);
    }

    // Only trust targets after re-verifying them at their final location.
    for (var i = 0; i < files.length; i++) {
      final target = targets[i];
      if (target == null) continue;
      if (!target.existsSync()) {
        problems.add('Missing target: ${files[i].relativePath}');
        continue;
      }
      if (await target.length() != files[i].size) {
        problems.add('Size mismatch: ${files[i].relativePath}');
        continue;
      }
      final checksum = files[i].checksum;
      if (checksum != null && await _checksum(target) != checksum) {
        problems.add('Checksum mismatch: ${files[i].relativePath}');
      }
    }

    if (problems.isEmpty) _deleteStaging(pending);
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
    final id = _authorized(request);
    if (id == null) {
      _writeJson(response, 401, {'error': 'Not paired'});
      return;
    }
    final body = await _readJson(request);
    final action = body['action'] as String?;
    final transferId = body['transferId'] as String?;
    if (transferId == null || !isValidTransferId(transferId)) {
      _writeJson(response, 400, {'error': 'Invalid transfer id'});
      return;
    }
    final pending = _pending[transferId];
    if (pending == null || pending.manifest.senderId != id) {
      _writeJson(response, 403, {'error': 'Not your transfer'});
      return;
    }
    switch (action) {
      case 'decline':
        decline(transferId);
      case 'cancel':
        cancel(transferId);
      default:
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

  static Future<String> _checksum(File file) async {
    final digests = StreamController<Digest>();
    final sink = sha256.startChunkedConversion(digests.sink);
    final result = digests.stream.first.then((digest) => digest.toString());
    try {
      await for (final chunk in file.openRead()) {
        sink.add(chunk);
      }
    } finally {
      sink.close();
      await digests.close();
    }
    return result;
  }

  static Future<void> _copyFile(File source, File target) async {
    final sink = target.openWrite();
    try {
      await for (final chunk in source.openRead()) {
        sink.add(chunk);
      }
    } finally {
      await sink.close();
    }
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
