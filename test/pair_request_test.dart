import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wishare/core/crypto/certificate_manager.dart';
import 'package:wishare/core/network/protocol.dart';
import 'package:wishare/core/network/wishare_client.dart';
import 'package:wishare/core/network/wishare_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  test(
    'requests pair without a PIN and only a human approval issues a token',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'wishare-pair-request-',
      );
      final receiver = await CertificateManager.create(name: 'Receiver');
      final sender = await CertificateManager.create(name: 'Sender');
      final server = WishareServer(
        identity: receiver,
        downloadDirectory: temp.path,
      );
      await server.start(port: 0);
      addTearDown(() async {
        await server.dispose();
        temp.deleteSync(recursive: true);
      });

      final incoming = server.pairRequests.first;
      final client = WishareClient(
        host: '127.0.0.1',
        port: server.port,
        expectedFingerprint: receiver.fingerprint,
        senderId: sender.id,
        senderFingerprint: sender.fingerprint,
      );
      await client.requestPair(
        id: sender.id,
        name: sender.name,
        fingerprint: sender.fingerprint,
      );

      final request = await incoming;
      expect(request.id, sender.id);
      expect(request.name, 'Sender');
      // TOFU uses the fingerprint the server actually observed, not a claimed one.
      expect(request.fingerprint, sender.fingerprint);

      // No token exists while the request sits in the UI. Check the status
      // endpoint directly instead of relying on a timing delay.
      final http = HttpClient()
        ..connectionTimeout = WiProtocol.requestTimeout
        ..badCertificateCallback = (_, _, _) => true;
      final statusRequest = await http.getUrl(
        Uri(
          scheme: WiProtocol.scheme,
          host: '127.0.0.1',
          port: server.port,
          path: '/pair-request/status',
          queryParameters: {'id': sender.id},
        ),
      );
      final statusResponse = await statusRequest.close();
      final statusBody = await utf8.decoder.bind(statusResponse).join();
      http.close(force: true);
      expect(jsonDecode(statusBody)['status'], 'pending');

      final pairing = server.pairings.first;
      final approval = client.waitForPairApproval(sender.id);
      server.approvePairRequest(request.id);

      final token = await approval;
      expect(token, isNotEmpty);
      final event = await pairing;
      expect(event['method'], 'request');
      expect(event['fingerprint'], sender.fingerprint);

      // A session token now authorizes API calls that previously returned 401.
      Object? failure;
      try {
        await client.status('unknown-transfer');
      } on Object catch (error) {
        failure = error;
      }
      expect(failure, isA<HttpException>());
      expect(failure.toString(), isNot(contains('401')));
    },
  );

  test('a declined request reaches the polling sender', () async {
    final temp = await Directory.systemTemp.createTemp('wishare-pair-decline-');
    final receiver = await CertificateManager.create(name: 'Receiver');
    final sender = await CertificateManager.create(name: 'Sender');
    final server = WishareServer(
      identity: receiver,
      downloadDirectory: temp.path,
    );
    await server.start(port: 0);
    addTearDown(() async {
      await server.dispose();
      temp.deleteSync(recursive: true);
    });

    final incoming = server.pairRequests.first;
    final client = WishareClient(
      host: '127.0.0.1',
      port: server.port,
      expectedFingerprint: receiver.fingerprint,
      senderId: sender.id,
      senderFingerprint: sender.fingerprint,
    );
    await client.requestPair(
      id: sender.id,
      name: 'Sender',
      fingerprint: sender.fingerprint,
    );
    final request = await incoming;
    server.declinePairRequest(request.id);

    expect(
      client.waitForPairApproval(sender.id),
      throwsA(isA<PairRequestException>()),
    );
  });
}
