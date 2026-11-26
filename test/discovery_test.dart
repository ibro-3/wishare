import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wishare/core/crypto/certificate_manager.dart';
import 'package:wishare/core/network/discovery.dart';

void main() {
  test('bound discovery socket has IPv4 broadcast enabled', () async {
    final identity = await CertificateManager.create(name: 'Test device');
    final discovery = DiscoveryService(
      identity: identity,
      enabled: true,
      broadcast: true,
    );
    addTearDown(discovery.dispose);

    await discovery.start();

    expect(discovery.broadcastReady, isTrue);
  });

  test(
    'broadcast targets include interface broadcasts and the global fallback',
    () async {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      final targets = DiscoveryService.broadcastTargets(interfaces);
      final addresses = targets.map((address) => address.address).toList();

      expect(addresses, contains('255.255.255.255'));
      expect(addresses.toSet().length, addresses.length);
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          final broadcast = address.broadcast;
          if (broadcast != null) expect(addresses, contains(broadcast.address));
        }
      }
    },
  );

  test(
    'broadcast targets fall back to the global address with no interfaces',
    () {
      final targets = DiscoveryService.broadcastTargets(const []);
      expect(targets.single.address, '255.255.255.255');
    },
  );

  test('preferred LAN address is never loopback or link-local', () async {
    final address = await DiscoveryService.preferredLocalAddress();
    expect(address, isNot('127.0.0.1'));
    expect(address.startsWith('169.254.'), isFalse);
  });
}
