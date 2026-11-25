import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../crypto/certificate_manager.dart';
import '../models/peer.dart';
import '../models/settings.dart';
import '../models/transfer.dart';
import '../network/discovery.dart';
import '../platform/notifications.dart';
import '../network/protocol.dart';
import '../network/wishare_client.dart';
import '../network/wishare_server.dart';
import '../storage/app_store.dart';
import '../theme/wishare_theme.dart';

final storeProvider = FutureProvider<AppStore>((ref) => AppStore.create());

final identityProvider = FutureProvider<DeviceIdentity>((ref) async {
  final store = await ref.watch(storeProvider.future);
  final existing = await store.certificates.load();
  return existing ?? await store.certificates.generate();
});

final settingsProvider = AsyncNotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);

class SettingsController extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() async {
    final store = await ref.watch(storeProvider.future);
    return store.loadSettings();
  }

  Future<void> updateSettings(
    AppSettings Function(AppSettings current) change,
  ) async {
    final current = state.value;
    if (current == null) return;
    final next = change(current);
    state = AsyncData(next);
    final store = await ref.read(storeProvider.future);
    await store.saveSettings(next);
  }
}

final peersProvider = AsyncNotifierProvider<PeersController, List<Peer>>(
  PeersController.new,
);

class PeersController extends AsyncNotifier<List<Peer>> {
  @override
  Future<List<Peer>> build() async {
    final store = await ref.watch(storeProvider.future);
    return store.loadPeers();
  }

  Future<void> merge(Iterable<Peer> discovered) async {
    final byId = <String, Peer>{
      for (final peer in state.value ?? const <Peer>[]) peer.id: peer,
    };
    for (final peer in discovered) {
      final existing = byId[peer.id];
      byId[peer.id] = existing == null
          ? peer
          : peer.copyWith(
              certificateFingerprint:
                  peer.certificateFingerprint ??
                  existing.certificateFingerprint,
              pinnedCertificate: existing.pinnedCertificate,
              sessionToken: existing.sessionToken,
              pairingMethod: existing.pairingMethod,
              pairedAt: existing.pairedAt,
              trustLevel: existing.trustLevel,
            );
    }
    final next = byId.values.toList()
      ..sort(
        (a, b) => (b.lastSeen?.compareTo(a.lastSeen ?? DateTime.now()) ?? 0),
      );
    state = AsyncData(next);
    await _save(next);
  }

  Future<void> markPaired(String id, String name) async {
    final identity = await ref.read(identityProvider.future);
    final next = (state.value ?? const <Peer>[]).map((peer) {
      if (peer.id != id) return peer;
      return peer.copyWith(
        name: name,
        certificateFingerprint:
            peer.certificateFingerprint ?? identity.fingerprint,
        pinnedCertificate: identity.certificatePem,
        pairedAt: DateTime.now(),
        pairingMethod: PairingMethod.qr,
        trustLevel: TrustLevel.paired,
      );
    }).toList();
    state = AsyncData(next);
    await _save(next);
  }

  Future<void> addManual(Peer peer) async {
    final next = <Peer>[...(state.value ?? const <Peer>[]), peer];
    state = AsyncData(next);
    await _save(next);
  }

  Future<void> _save(List<Peer> peers) async {
    final store = await ref.read(storeProvider.future);
    await store.savePeers(peers);
  }
}

final transfersProvider =
    AsyncNotifierProvider<TransfersController, List<Transfer>>(
      TransfersController.new,
    );

class TransfersController extends AsyncNotifier<List<Transfer>> {
  @override
  Future<List<Transfer>> build() async {
    final store = await ref.watch(storeProvider.future);
    return store.loadTransfers();
  }

  Future<void> upsert(Transfer transfer) async {
    final next = <Transfer>[
      transfer,
      ...(state.value ?? const <Transfer>[]).where(
        (existing) => existing.id != transfer.id,
      ),
    ];
    state = AsyncData(next);
    await _save(next);
  }

  Future<void> _save(List<Transfer> transfers) async {
    final store = await ref.read(storeProvider.future);
    await store.saveTransfers(transfers);
  }
}

class NetworkState {
  const NetworkState({
    required this.server,
    required this.discovery,
    this.pin,
    this.qrPayload,
    this.error,
  });

  final WishareServer server;
  final DiscoveryService discovery;
  final String? pin;
  final PairingPayload? qrPayload;
  final String? error;

  NetworkState copyWith({
    String? pin,
    PairingPayload? qrPayload,
    String? error,
  }) => NetworkState(
    server: server,
    discovery: discovery,
    pin: pin,
    qrPayload: qrPayload,
    error: error,
  );
}

final networkProvider = AsyncNotifierProvider<NetworkController, NetworkState>(
  NetworkController.new,
);

class NetworkController extends AsyncNotifier<NetworkState> {
  @override
  Future<NetworkState> build() async {
    final identity = await ref.watch(identityProvider.future);
    final settings = await ref.watch(settingsProvider.future);
    final server = WishareServer(
      identity: identity,
      downloadDirectory: settings.downloadDirectory ?? '',
    );
    final discovery = DiscoveryService(
      identity: identity,
      enabled: settings.discoveryEnabled,
      broadcast: settings.broadcastEnabled,
    );
    await server.start();
    await discovery.start();

    final subscriptions = <StreamSubscription<dynamic>>[
      discovery.peers.listen((peers) {
        ref.read(peersProvider.notifier).merge(peers);
      }),
      server.offers.listen((manifest) {
        if (AppLifecycle.state.value != AppLifecycleState.resumed &&
            ref.read(settingsProvider).value?.notificationsEnabled == true) {
          Notifications.showIncomingOffer(
            manifest.senderName,
            manifest.fileCount,
          );
        }
        ref
            .read(transfersProvider.notifier)
            .upsert(
              Transfer(
                id: manifest.transferId,
                direction: TransferDirection.incoming,
                peerId: manifest.senderId,
                peerName: manifest.senderName,
                files: manifest.entries,
                totalBytes: manifest.totalBytes,
                createdAt: DateTime.now(),
                status: TransferStatus.offered,
              ),
            );
      }),
      server.updates.listen((transfer) {
        ref.read(transfersProvider.notifier).upsert(transfer);
      }),
      server.pairings.listen((event) {
        ref
            .read(peersProvider.notifier)
            .markPaired(
              event['id'] as String,
              event['name'] as String? ?? 'Wishare device',
            );
      }),
    ];
    ref.onDispose(() {
      for (final subscription in subscriptions) {
        subscription.cancel();
      }
      discovery.stop();
      server.dispose();
    });
    return NetworkState(server: server, discovery: discovery);
  }

  /// Sender side: verify the receiver certificate, redeem the PIN, and store
  /// the resulting session token with the peer.
  Future<void> pairWith(PairingPayload payload) async {
    final identity = await ref.read(identityProvider.future);
    final client = WishareClient(
      host: payload.host,
      port: payload.port,
      expectedFingerprint: payload.fingerprint,
    );
    final info = await client.info();
    await client.pair(id: identity.id, name: identity.name, pin: payload.pin);
    await ref
        .read(peersProvider.notifier)
        .addManual(
          Peer(
            id: info['id'] as String? ?? payload.name,
            name: info['name'] as String? ?? payload.name,
            address: payload.host,
            port: payload.port,
            colorSeed: WishareTheme.seedArgb,
            certificateFingerprint: payload.fingerprint,
            sessionToken: client.token,
            pairedAt: DateTime.now(),
            pairingMethod: PairingMethod.qr,
            trustLevel: TrustLevel.paired,
          ),
        );
  }

  Future<void> acceptTransfer(String id, String saveDirectory) async {
    final state = await future;
    state.server.accept(id, saveDirectory);
  }

  Future<void> declineTransfer(String id) async {
    final state = await future;
    state.server.decline(id);
  }

  /// Cancel an active transfer in either direction.
  Future<void> cancelTransfer(Transfer transfer) async {
    if (transfer.direction == TransferDirection.incoming) {
      final state = await future;
      state.server.cancel(transfer.id);
      return;
    }
    final peers = ref.read(peersProvider).value ?? const <Peer>[];
    Peer? peer;
    for (final candidate in peers) {
      if (candidate.id == transfer.peerId) peer = candidate;
    }
    if (peer == null) return;
    final identity = await ref.read(identityProvider.future);
    final client = WishareClient(
      host: peer.address,
      port: peer.port,
      expectedFingerprint: peer.certificateFingerprint ?? '',
      senderId: identity.id,
      token: peer.sessionToken ?? '',
    );
    await client.cancel(transfer.id);
    await ref
        .read(transfersProvider.notifier)
        .upsert(
          transfer.copyWith(
            status: TransferStatus.cancelled,
            finishedAt: DateTime.now(),
          ),
        );
  }

  /// Generate a fresh single-use pairing code for the receiver.
  Future<PairingPayload> generatePairingCode() async {
    final state = await future;
    final identity = await ref.read(identityProvider.future);
    final settings = await ref.read(settingsProvider.future);
    final pin = state.server.generatePin();
    final payload = PairingPayload(
      host: await _localAddress(),
      port: WiProtocol.port,
      name: settings.deviceName,
      fingerprint: identity.fingerprint,
      pin: pin,
    );
    this.state = AsyncData(state.copyWith(pin: pin, qrPayload: payload));
    return payload;
  }

  Future<String> _localAddress() async {
    // The receiver's LAN address is advertised over UDP; prefer the first
    // non-loopback IPv4 address as a usable pairing host.
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (!address.isLoopback) return address.address;
      }
    }
    return '127.0.0.1';
  }
}
