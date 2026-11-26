import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wishare/core/crypto/certificate_manager.dart';
import 'package:wishare/core/models/manifest.dart';
import 'package:wishare/core/models/transfer.dart';
import 'package:wishare/core/network/protocol.dart';
import 'package:wishare/core/network/wishare_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  late Directory temp;
  late WishareServer server;
  late DeviceIdentity identity;
  late int port;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('wishare-security-');
    identity = await CertificateManager.create(name: 'Receiver');
    server = WishareServer(
      identity: identity,
      downloadDirectory: '${temp.path}${Platform.pathSeparator}downloads',
    );
    // Let the server choose the port atomically: a probe-then-rebind races
    // with other test isolates and caused intermittent "address in use".
    await server.start(port: 0);
    port = server.port;
  });

  tearDown(() async {
    await server.dispose();
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  HttpClient makeClient() => HttpClient()
    ..connectionTimeout = WiProtocol.requestTimeout
    ..badCertificateCallback = (_, _, _) => true;

  Future<({int status, Map<String, dynamic> body})> post(
    String path,
    Map<String, dynamic> body, {
    Map<String, String> headers = const {},
  }) async {
    final request = await makeClient().postUrl(
      Uri(scheme: WiProtocol.scheme, host: '127.0.0.1', port: port, path: path),
    );
    for (final entry in headers.entries) {
      request.headers.set(entry.key, entry.value);
    }
    request.headers.contentType = ContentType.json;
    request.add(utf8.encode(jsonEncode(body)));
    final response = await request.close();
    final text = await utf8.decoder.bind(response).join();
    return (
      status: response.statusCode,
      body: text.isEmpty
          ? const <String, dynamic>{}
          : jsonDecode(text) as Map<String, dynamic>,
    );
  }

  Future<({int status, Map<String, dynamic> body})> get(
    String path, {
    Map<String, String> headers = const {},
  }) async {
    final request = await makeClient().getUrl(
      Uri.parse('${WiProtocol.scheme}://127.0.0.1:$port$path'),
    );
    for (final entry in headers.entries) {
      request.headers.set(entry.key, entry.value);
    }
    final response = await request.close();
    final text = await utf8.decoder.bind(response).join();
    return (
      status: response.statusCode,
      body: text.isEmpty
          ? const <String, dynamic>{}
          : jsonDecode(text) as Map<String, dynamic>,
    );
  }

  Future<Map<String, String>> pairedHeaders() async {
    final result = await post('/pair', {
      'id': 'sender-device',
      'name': 'Sender',
      'pin': server.generatePin(),
    });
    expect(result.status, 200);
    return {
      WiProtocol.headerDeviceId: 'sender-device',
      WiProtocol.headerToken: result.body['token'] as String,
    };
  }

  test(
    'pairing pins the sender fingerprint, never the receiver identity',
    () async {
      const senderFingerprint =
          'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
      final event = server.pairings.first;
      final result = await post(
        '/pair',
        {'id': 'sender-device', 'name': 'Sender', 'pin': server.generatePin()},
        headers: {WiProtocol.headerFingerprint: senderFingerprint},
      );
      expect(result.status, 200);
      expect((await event)['fingerprint'], senderFingerprint);
      expect(result.body['fingerprint'], identity.fingerprint);
    },
  );

  test('cancel requires a paired session', () async {
    final result = await post('/cancel', {
      'transferId': 'any-transfer',
      'action': 'cancel',
    });
    expect(result.status, 401);
  });

  test('a paired sender cannot cancel someone else’s transfer', () async {
    final headers = await pairedHeaders();
    final result = await post('/cancel', {
      'transferId': 'other-transfer',
      'action': 'cancel',
    }, headers: headers);
    expect(result.status, 403);
  });

  test(
    'transfer ids with traversal are rejected before touching disk',
    () async {
      final headers = await pairedHeaders();
      final manifest = TransferManifest(
        transferId: '../../outside',
        senderId: 'sender-device',
        senderName: 'Sender',
        rootName: 'Files',
        entries: const [
          TransferFileEntry(relativePath: 'a.txt', size: 0, checksum: 'abc'),
        ],
        totalBytes: 0,
      );
      final result = await post(
        '/request',
        manifest.toJson(),
        headers: headers,
      );
      expect(result.status, 400);
      expect(
        Directory('${temp.path}/downloads/.staging').existsSync(),
        isFalse,
      );
    },
  );

  test('a valid offer is staged and can be cancelled by its sender', () async {
    final headers = await pairedHeaders();
    const transferId = '123e4567-e89b-12d3-a456-426614174000';
    final manifest = TransferManifest(
      transferId: transferId,
      senderId: 'sender-device',
      senderName: 'Sender',
      rootName: 'Files',
      entries: const [TransferFileEntry(relativePath: 'a.txt', size: 0)],
      totalBytes: 0,
    );
    final offered = await post('/request', manifest.toJson(), headers: headers);
    expect(offered.status, 202);
    final cancelled = await post('/cancel', {
      'transferId': transferId,
      'action': 'cancel',
    }, headers: headers);
    expect(cancelled.status, 200);
    final status = await get(
      '/status?transferId=$transferId',
      headers: headers,
    );
    expect(status.status, 200);
    expect(status.body['declined'], isTrue);
  });
}
