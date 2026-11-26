import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../models/manifest.dart';
import 'protocol.dart';

/// Thrown by [WishareClient.waitForAccept] when the receiver declines or
/// cancels an offer instead of accepting it. The UI should finalize the
/// outgoing transfer rather than treating this as a generic failure.
class TransferDeclinedException implements Exception {
  const TransferDeclinedException(this.transferId, {this.status});

  final String transferId;
  final String? status;

  @override
  String toString() => status == null || status!.isEmpty
      ? 'Transfer $transferId was declined'
      : 'Transfer $transferId ended with status $status';
}

/// Thrown when the receiver declines or drops a no-code pairing request.
class PairRequestException implements Exception {
  const PairRequestException(this.status);

  final String status;

  @override
  String toString() => status == 'declined'
      ? 'The other device declined the pairing request'
      : 'Pairing request $status';
}

/// HTTPS sender. A peer's certificate fingerprint is verified on every
/// connection (TOFU after pairing). Pairing additionally requires the PIN.
class WishareClient {
  WishareClient({
    required this.host,
    required this.port,
    required this.expectedFingerprint,
    this.senderId = '',
    this.token = '',
    this.senderFingerprint = '',
  });

  final String host;
  final int port;
  final String expectedFingerprint;

  /// Our own certificate fingerprint, sent to the receiver during pairing so
  /// it can pin our identity rather than its own.
  final String senderFingerprint;
  String senderId;
  String token;

  Uri _uri(String path, [Map<String, String>? query]) => Uri(
    scheme: WiProtocol.scheme,
    host: host,
    port: port,
    path: path,
    queryParameters: query,
  );

  HttpClient _client() {
    final client = HttpClient()..connectionTimeout = WiProtocol.requestTimeout;
    client.badCertificateCallback = (certificate, host, port) {
      final observed = sha256.convert(certificate.der).toString().toUpperCase();
      return normaliseFingerprint(observed) ==
          normaliseFingerprint(expectedFingerprint);
    };
    return client;
  }

  Future<Map<String, dynamic>> info() async {
    final client = _client();
    try {
      final request = await client.getUrl(_uri('/info'));
      final response = await request.close();
      return jsonDecode(utf8.decode(await _bytes(response)))
          as Map<String, dynamic>;
    } finally {
      client.close(force: true);
    }
  }

  /// Fetch a fingerprint for manual pairing. The user must compare it with
  /// the fingerprint shown on the receiver before calling [pair].
  static Future<String> fetchFingerprint(String host, int port) async {
    final client = HttpClient()
      ..connectionTimeout = WiProtocol.requestTimeout
      ..badCertificateCallback = (cert, host, port) => true;
    try {
      final request = await client.getUrl(
        Uri(scheme: WiProtocol.scheme, host: host, port: port, path: '/info'),
      );
      final response = await request.close();
      final body = jsonDecode(
        utf8.decode(await _bytes(response)),
      ) as Map<String, dynamic>;
      return normaliseFingerprint(body['fingerprint'] as String? ?? '');
    } finally {
      client.close(force: true);
    }
  }

  Future<String> pair({
    required String id,
    required String name,
    required String pin,
  }) async {
    senderId = id;
    final result = await _jsonRequest(
      'POST',
      '/pair',
      body: {'id': id, 'name': name, 'pin': pin},
    );
    token = result['token'] as String;
    final returnedFingerprint = normaliseFingerprint(
      result['fingerprint'] as String? ?? '',
    );
    if (returnedFingerprint != normaliseFingerprint(expectedFingerprint)) {
      throw const FormatException('Certificate fingerprint mismatch');
    }
    return token;
  }

  /// Ask a nearby receiver to approve pairing without a QR code or PIN.
  Future<void> requestPair({
    required String id,
    required String name,
    required String fingerprint,
  }) async {
    senderId = id;
    await _jsonRequest(
      'POST',
      '/pair-request',
      body: {'id': id, 'name': name, 'fingerprint': fingerprint},
    );
  }

  /// Poll until the receiver approves or declines. The returned token is only
  /// issued on approval; the receiver fingerprint is re-verified here too.
  Future<String> waitForPairApproval(
    String id, {
    Duration timeout = const Duration(minutes: 2),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final result = await _jsonRequest(
        'GET',
        '/pair-request/status',
        query: {'id': id},
      );
      switch (result['status']) {
        case 'approved':
          final returned = normaliseFingerprint(
            result['fingerprint'] as String? ?? '',
          );
          if (returned != normaliseFingerprint(expectedFingerprint)) {
            throw const FormatException('Certificate fingerprint mismatch');
          }
          token = result['token'] as String? ?? '';
          if (token.isEmpty) {
            throw const FormatException('Missing session token');
          }
          return token;
        case 'declined':
          throw const PairRequestException('declined');
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    throw TimeoutException('The other device did not respond', timeout);
  }

  Future<void> sendManifest(TransferManifest manifest) async {
    await _jsonRequest('POST', '/request', body: manifest.toJson());
  }

  Future<
    ({
      bool accepted,
      int transferredBytes,
      int offset,
      bool declined,
      String? status,
    })
  >
  status(String transferId, {String? relativePath}) async {
    final query = <String, String>{'transferId': transferId};
    if (relativePath != null) query['path'] = encodePath(relativePath);
    final result = await _jsonRequest('GET', '/status', query: query);
    return (
      accepted: result['accepted'] is bool ? result['accepted'] as bool : false,
      transferredBytes: _asInt(result['transferredBytes']),
      offset: _asInt(result['offset']),
      declined: result['declined'] is bool ? result['declined'] as bool : false,
      status: result['status'] as String?,
    );
  }

  static int _asInt(Object? value) =>
      value is int ? value : (value is num ? value.toInt() : 0);

  Future<void> waitForAccept(
    String transferId, {
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final state = await status(transferId);
      if (state.declined) {
        throw TransferDeclinedException(transferId, status: state.status);
      }
      if (state.accepted) return;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    throw TimeoutException('Receiver did not accept the transfer', timeout);
  }

  /// Send one file chunk. Returns the number of bytes acknowledged by the
  /// receiver; a 409 response means the receiver's offset differs (resume).
  Future<int> sendChunk({
    required String transferId,
    required String relativePath,
    required int offset,
    required Uint8List bytes,
  }) async {
    final client = _client();
    try {
      final request = await client.putUrl(
        _uri('/chunk', {
          'transferId': transferId,
          'path': encodePath(relativePath),
          'offset': '$offset',
        }),
      );
      _applyHeaders(request);
      // Chunk bodies are raw bytes, not JSON.
      request.headers.contentType = ContentType('application', 'octet-stream');
      request.add(bytes);
      final response = await request.close();
      final body = await _bytes(response);
      if (response.statusCode != 200) {
        throw HttpException(utf8.decode(body), uri: request.uri);
      }
      final result = jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
      return result['received'] as int? ?? bytes.length;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> complete(String transferId) =>
      _jsonRequest('POST', '/complete', body: {'transferId': transferId});

  Future<void> cancel(String transferId) => _jsonRequest(
    'POST',
    '/cancel',
    body: {'transferId': transferId, 'action': 'cancel'},
  );

  void _applyHeaders(HttpClientRequest request) {
    request.headers.set(WiProtocol.headerDeviceId, senderId);
    request.headers.set(WiProtocol.headerToken, token);
    request.headers.set(
      WiProtocol.headerFingerprint,
      senderFingerprint.isEmpty ? expectedFingerprint : senderFingerprint,
    );
  }

  Future<Map<String, dynamic>> _jsonRequest(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    final client = _client();
    try {
      final request = await (switch (method) {
        'GET' => client.getUrl(_uri(path, query)),
        'POST' => client.postUrl(_uri(path, query)),
        _ => throw ArgumentError('Unsupported method $method'),
      });
      _applyHeaders(request);
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.add(jsonBytes(body));
      }
      final response = await request.close();
      final bytes = await _bytes(response);
      final decoded = bytes.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      if (response.statusCode >= 400) {
        throw HttpException(
          decoded['error'] as String? ??
              'Request failed (${response.statusCode})',
          uri: request.uri,
        );
      }
      return decoded;
    } finally {
      client.close(force: true);
    }
  }

  static Future<Uint8List> _bytes(HttpClientResponse response) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }
}
