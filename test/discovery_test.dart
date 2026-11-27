import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:multicast_dns/multicast_dns.dart';
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

  test(
    'broadcast targets can be restricted to the preferred interface',
    () async {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      if (interfaces.isEmpty) return; // Headless hosts may have no LAN.
      final address = interfaces.first.addresses.first.address;
      final preferred = DiscoveryService.interfaceFor(interfaces, address);
      expect(preferred, isNotNull);
      expect(DiscoveryService.interfaceFor(interfaces, '203.0.113.7'), isNull);

      final targets = DiscoveryService.broadcastTargetsFor(interfaces, address);
      expect(
        targets.map((entry) => entry.address),
        contains('255.255.255.255'),
      );
      for (final target in targets) {
        if (target.address == '255.255.255.255') continue;
        expect(
          preferred!.addresses.any(
            (entry) => entry.broadcast?.address == target.address,
          ),
          isTrue,
        );
      }
    },
  );

  test('start is idempotent and rescan can be repeated', () async {
    final identity = await CertificateManager.create(name: 'Test device');
    final discovery = DiscoveryService(
      identity: identity,
      enabled: true,
      broadcast: true,
    );
    addTearDown(discovery.dispose);

    await discovery.start();
    await discovery.start();
    expect(discovery.broadcastReady, isTrue);
    await discovery.rescan();
    await discovery.rescan();

    discovery.applySettings(discoveryEnabled: false, broadcastEnabled: false);
    for (var i = 0; i < 10 && discovery.broadcastReady; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(discovery.broadcastReady, isFalse);

    discovery.applySettings(discoveryEnabled: true, broadcastEnabled: true);
    for (var i = 0; i < 60 && !discovery.broadcastReady; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(discovery.broadcastReady, isTrue);
  });

  test('mDNS records older than twenty seconds are not fresh', () {
    final now = DateTime.now().millisecondsSinceEpoch;
    final address = InternetAddress('192.168.1.20');
    expect(
      DiscoveryService.isFreshMdnsRecord(
        IPAddressResourceRecord('instance', now + 120000, address: address),
      ),
      isTrue,
    );
    expect(
      DiscoveryService.isFreshMdnsRecord(
        IPAddressResourceRecord('instance', now + 90000, address: address),
      ),
      isFalse,
    );
  });
}
