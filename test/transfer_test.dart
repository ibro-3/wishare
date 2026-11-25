import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wishare/core/crypto/certificate_manager.dart';
import 'package:wishare/core/models/settings.dart';
import 'package:wishare/core/models/transfer.dart';
import 'package:wishare/core/network/transfer_coordinator.dart';
import 'package:wishare/core/network/wishare_client.dart';
import 'package:wishare/core/network/wishare_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  test(
    'pairs over TLS and transfers a folder with checksum verification',
    () async {
      SharedPreferences.setMockInitialValues({});
      final temp = await Directory.systemTemp.createTemp('wishare-e2e-');
      final downloadDir = '${temp.path}${Platform.pathSeparator}downloads';
      final sourceDir = Directory(
        '${temp.path}${Platform.pathSeparator}source',
      );
      await Directory('${sourceDir.path}/nested').create(recursive: true);
      await File('${sourceDir.path}/root.txt').writeAsString('root contents');
      await File('${sourceDir.path}/nested/deep.txt')
          .writeAsString('nested contents');

      final manager = CertificateManager(await SharedPreferences.getInstance());
      final identity = await manager.generate(name: 'Receiver');

      final server = WishareServer(
        identity: identity,
        downloadDirectory: downloadDir,
      );
      final pin = server.generatePin();
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final testPort = probe.port;
      await probe.close();
      await server.start(port: testPort);
      addTearDown(() async {
        await server.dispose();
        temp.deleteSync(recursive: true);
      });

      final settings = AppSettings.initial(downloadDir);
      final coordinator = TransferCoordinator(settings);
      final senderIdentity = await CertificateManager.create(name: 'Sender');
      final entries = await coordinator.collect([sourceDir.path]);
      final manifest = await coordinator.buildManifest(
        entries: entries,
        identity: senderIdentity,
        transferId: 'e2e-transfer',
      );

      final observedFingerprint = await WishareClient.fetchFingerprint(
        '127.0.0.1',
        testPort,
      );
      expect(observedFingerprint, identity.fingerprint);

      final client = WishareClient(
        host: '127.0.0.1',
        port: testPort,
        expectedFingerprint: identity.fingerprint,
      );
      await client.pair(id: senderIdentity.id, name: 'Sender', pin: pin);
      await client.sendManifest(manifest);
      server.accept(manifest.transferId, downloadDir);
      await client.waitForAccept(manifest.transferId);

      await coordinator.send(
        client: client,
        manifest: manifest,
        entries: entries,
        onProgress: (bytes, speed) {},
      );

      final root = File('$downloadDir/${entries.first.relativePath}/root.txt');
      final nested = File(
        '$downloadDir/${entries.first.relativePath}/nested/deep.txt',
      );
      expect(root.existsSync(), isTrue);
      expect(nested.existsSync(), isTrue);
      expect(root.readAsStringSync(), 'root contents');
      expect(nested.readAsStringSync(), 'nested contents');
    },
  );
  test(
    'cancel removes staging files and reports a cancelled transfer',
    () async {
      SharedPreferences.setMockInitialValues({});
      final temp = await Directory.systemTemp.createTemp('wishare-cancel-');
      final downloadDir = '${temp.path}${Platform.pathSeparator}downloads';
      await File('${temp.path}/payload.txt').writeAsString('payload');

      final manager = CertificateManager(await SharedPreferences.getInstance());
      final identity = await manager.generate(name: 'Receiver');
      final server = WishareServer(
        identity: identity,
        downloadDirectory: downloadDir,
      );
      final pin = server.generatePin();
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final testPort = probe.port;
      await probe.close();
      await server.start(port: testPort);
      addTearDown(() async {
        await server.dispose();
        temp.deleteSync(recursive: true);
      });

      final coordinator = TransferCoordinator(AppSettings.initial(downloadDir));
      final sender = await CertificateManager.create(name: 'Sender');
      final entries = await coordinator.collect(['${temp.path}/payload.txt']);
      final manifest = await coordinator.buildManifest(
        entries: entries,
        identity: sender,
        transferId: 'cancel-transfer',
      );

      final client = WishareClient(
        host: '127.0.0.1',
        port: testPort,
        expectedFingerprint: identity.fingerprint,
      );
      await client.pair(id: sender.id, name: 'Sender', pin: pin);

      final cancelled = Completer<Transfer>();
      final subscription = server.updates.listen((transfer) {
        if (transfer.status == TransferStatus.cancelled &&
            !cancelled.isCompleted) {
          cancelled.complete(transfer);
        }
      });
      addTearDown(subscription.cancel);

      await client.sendManifest(manifest);
      server.cancel(manifest.transferId);
      final transfer = await cancelled.future.timeout(
        const Duration(seconds: 5),
      );

      expect(transfer.id, 'cancel-transfer');
      expect(
        Directory('$downloadDir/.staging/${manifest.transferId}').existsSync(),
        isFalse,
      );
    },
  );
  test('resumes an interrupted transfer from the receiver offset', () async {
    SharedPreferences.setMockInitialValues({});
    final temp = await Directory.systemTemp.createTemp('wishare-resume-');
    final downloadDir = '${temp.path}${Platform.pathSeparator}downloads';
    final source = File('${temp.path}${Platform.pathSeparator}resume.txt');
    final content = Uint8List.fromList(
      List<int>.generate(4096, (index) => index % 256),
    );
    await source.writeAsBytes(content);

    final manager = CertificateManager(await SharedPreferences.getInstance());
    final identity = await manager.generate(name: 'Receiver');
    final server = WishareServer(
      identity: identity,
      downloadDirectory: downloadDir,
    );
    final pin = server.generatePin();
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final testPort = probe.port;
    await probe.close();
    await server.start(port: testPort);
    addTearDown(() async {
      await server.dispose();
      temp.deleteSync(recursive: true);
    });

    final coordinator = TransferCoordinator(AppSettings.initial(downloadDir));
    final sender = await CertificateManager.create(name: 'Sender');
    final entries = await coordinator.collect([source.path]);
    final manifest = await coordinator.buildManifest(
      entries: entries,
      identity: sender,
      transferId: 'resume-transfer',
    );
    final relativePath = entries.first.relativePath;

    final client = WishareClient(
      host: '127.0.0.1',
      port: testPort,
      expectedFingerprint: identity.fingerprint,
    );
    await client.pair(id: sender.id, name: 'Sender', pin: pin);
    await client.sendManifest(manifest);
    server.accept(manifest.transferId, downloadDir);
    await client.waitForAccept(manifest.transferId);

    final split = content.length ~/ 2;
    await client.sendChunk(
      transferId: manifest.transferId,
      relativePath: relativePath,
      offset: 0,
      bytes: content.sublist(0, split),
    );

    // Simulate a dropped connection: a fresh client resumes from the offset
    // acknowledged by the receiver.
    final resumed = WishareClient(
      host: '127.0.0.1',
      port: testPort,
      expectedFingerprint: identity.fingerprint,
      senderId: sender.id,
      token: client.token,
    );
    final status = await resumed.status(
      manifest.transferId,
      relativePath: relativePath,
    );
    expect(status.offset, split);
    await resumed.sendChunk(
      transferId: manifest.transferId,
      relativePath: relativePath,
      offset: status.offset,
      bytes: content.sublist(split),
    );
    await resumed.complete(manifest.transferId);

    expect(File('$downloadDir/$relativePath').readAsBytesSync(), content);
  });

  test('transfers over the actual LAN address, not only loopback', () async {
    SharedPreferences.setMockInitialValues({});
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );
    if (interfaces.isEmpty || interfaces.first.addresses.isEmpty) {
      return; // No LAN interface in this environment.
    }
    final host = interfaces.first.addresses.first.address;
    final temp = await Directory.systemTemp.createTemp('wishare-lan-');
    final downloadDir = '${temp.path}${Platform.pathSeparator}downloads';
    final source = File('${temp.path}${Platform.pathSeparator}lan.txt');
    await source.writeAsString('over the LAN');

    final manager = CertificateManager(await SharedPreferences.getInstance());
    final identity = await manager.generate(name: 'Receiver');
    final server = WishareServer(
      identity: identity,
      downloadDirectory: downloadDir,
    );
    final pin = server.generatePin();
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final testPort = probe.port;
    await probe.close();
    await server.start(port: testPort);
    addTearDown(() async {
      await server.dispose();
      temp.deleteSync(recursive: true);
    });

    final coordinator = TransferCoordinator(AppSettings.initial(downloadDir));
    final sender = await CertificateManager.create(name: 'Sender');
    final entries = await coordinator.collect([source.path]);
    final manifest = await coordinator.buildManifest(
      entries: entries,
      identity: sender,
      transferId: 'lan-transfer',
    );
    final client = WishareClient(
      host: host,
      port: testPort,
      expectedFingerprint: identity.fingerprint,
    );
    await client.pair(id: sender.id, name: 'Sender', pin: pin);
    await client.sendManifest(manifest);
    server.accept(manifest.transferId, downloadDir);
    await client.waitForAccept(manifest.transferId);
    await coordinator.send(
      client: client,
      manifest: manifest,
      entries: entries,
      onProgress: (transferred, speed) {},
    );

    expect(
      File('$downloadDir/${entries.first.relativePath}').readAsStringSync(),
      'over the LAN',
    );
  });
}
