import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../crypto/certificate_manager.dart';
import '../models/pair_request.dart';
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
    final store = await ref.read(storeProvider.future);
    try {
      // Persist before publishing so listeners never observe unsaved settings.
      await store.saveSettings(next);
    } on Object {
      // Rollback: the previous value remains published.
      state = AsyncData(current);
      rethrow;
    }
    state = AsyncData(next);
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
      ..sort((a, b) {
        final aSeen = a.lastSeen ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bSeen = b.lastSeen ?? DateTime.fromMillisecondsSinceEpoch(0);
        final byTime = bSeen.compareTo(aSeen);
        // Tie-break on a stable key: never use DateTime.now() in a comparator.
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });
    state = AsyncData(next);
    await _save(next);
  }

  /// [fingerprint] is the sender identity observed during pairing. Never pin
  /// our own certificate here: that would make every sender look trusted.
  /// Replace any existing record for the same device after a successful
  /// request/approve pairing, instead of leaving a duplicate unpaired row.
  Future<void> markPairedRemotely(Peer peer) async {
    final next = <Peer>[
      peer,
      ...(state.value ?? const <Peer>[]).where(
        (existing) => existing.id != peer.id,
      ),
    ];
    state = AsyncData(next);
    await _save(next);
  }

  Future<void> markPaired(
    String id,
    String name, {
    String? fingerprint,
    PairingMethod method = PairingMethod.qr,
  }) async {
    final observed = fingerprint != null && isValidFingerprint(fingerprint)
        ? normaliseFingerprint(fingerprint)
        : null;
    final pairedAt = DateTime.now();
    final next = (state.value ?? const <Peer>[]).map((peer) {
      if (peer.id != id) return peer;
      final existing = peer.certificateFingerprint;
      final trustedFingerprint =
          observed ??
          (existing != null && isValidFingerprint(existing)
              ? normaliseFingerprint(existing)
              : null);
      // Construct explicitly so no pinned certificate from a previous record
      // (or from our own identity) can survive.
      return Peer(
        id: peer.id,
        name: name,
        address: peer.address,
        port: peer.port,
        colorSeed: peer.colorSeed,
        certificateFingerprint: trustedFingerprint,
        sessionToken: peer.sessionToken,
        pairingMethod: method,
        pairedAt: pairedAt,
        lastSeen: peer.lastSeen,
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
    ].take(200).toList();
    state = AsyncData(next);
    await _save(next);
  }

  Future<void> _save(List<Transfer> transfers) async {
    final store = await ref.read(storeProvider.future);
    await store.saveTransfers(transfers);
  }
}

/// Incoming no-code pairing requests waiting on the receiver's approval.
final pairRequestsProvider =
    AsyncNotifierProvider<PairRequestsController, List<PairRequest>>(
      PairRequestsController.new,
    );

class PairRequestsController extends AsyncNotifier<List<PairRequest>> {
  StreamSubscription<PairRequest>? _subscription;

  @override
  Future<List<PairRequest>> build() async {
    final network = await ref.watch(networkProvider.future);
    ref.onDispose(() => _subscription?.cancel());
    final existing = network.server.pendingRequests;
    _subscription = network.server.pairRequests.listen((request) {
      final current = state.value ?? const <PairRequest>[];
      if (current.any((entry) => entry.id == request.id)) return;
      state = AsyncData([...current, request]);
    });
    return existing;
  }

  void remove(String id) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(current.where((request) => request.id != id).toList());
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
    final identity = await ref.read(identityProvider.future);
    // One-time snapshot: toggling a setting must not rebuild (and dispose) the
    // bound HTTPS server or discovery in the middle of a transfer.
    final settings = await ref.read(settingsProvider.future);
    final server = WishareServer(
      identity: identity,
      downloadDirectory: settings.downloadDirectory ?? '',
    );
    final discovery = DiscoveryService(
      identity: identity,
      enabled: settings.discoveryEnabled,
      broadcast: settings.broadcastEnabled,
    );

    final subscriptions = <StreamSubscription<dynamic>>[];
    // Register cleanup before any resource is acquired so a partial startup
    // failure cannot leave a bound port or a live subscription behind.
    ref.onDispose(() {
      for (final subscription in subscriptions) {
        subscription.cancel();
      }
      unawaited(discovery.dispose());
      unawaited(server.dispose());
    });

    try {
      await server.start();
      await discovery.start();
    } on Object {
      await discovery.stop();
      await server.dispose();
      rethrow;
    }

    subscriptions.addAll([
      discovery.peers.listen((peers) {
        ref.read(peersProvider.notifier).merge(peers);
      }),
      server.offers.listen((manifest) {
        if (AppLifecycle.state.value != AppLifecycleState.resumed &&
            ref.read(settingsProvider).value?.notificationsEnabled == true) {
          Notifications.showIncomingOffer(
            manifest.senderName,
            manifest.fileCount,
            transferId: manifest.transferId,
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
              fingerprint: event['fingerprint'] as String?,
              method: event['method'] == 'request'
                  ? PairingMethod.request
                  : PairingMethod.qr,
            );
      }),
    ]);
    return NetworkState(server: server, discovery: discovery);
  }

  /// Apply changed settings to the running network services without rebuilding
  /// this controller (which would drop in-flight transfers).
  Future<void> applySettings(AppSettings settings) async {
    final current = state.value;
    if (current == null) return;
    current.server.updateDownloadDirectory(settings.downloadDirectory ?? '');
    current.discovery.applySettings(
      discoveryEnabled: settings.discoveryEnabled,
      broadcastEnabled: settings.broadcastEnabled,
    );
    state = AsyncData(current.copyWith());
  }

  /// Receiver side: called from the pairing prompt after explicit approval.
  Future<void> approvePairRequest(String id) async {
    final state = await future;
    state.server.approvePairRequest(id);
  }

  /// Receiver side: decline and keep the request marked declined so the
  /// polling sender gets a clear answer instead of a 404.
  Future<void> declinePairRequest(String id) async {
    final state = await future;
    state.server.declinePairRequest(id);
  }

  /// Sender side: ask a discovered nearby device to pair. No QR and no PIN —
  /// the receiver must approve the request in its UI before a token is issued.
  Future<void> requestPairWith(Peer peer) async {
    final fingerprint = peer.certificateFingerprint;
    if (fingerprint == null || !isValidFingerprint(fingerprint)) {
      throw const FormatException(
        'This device has no verified certificate fingerprint yet',
      );
    }
    final identity = await ref.read(identityProvider.future);
    final settings = await ref.read(settingsProvider.future);
    final client = WishareClient(
      host: peer.address,
      port: peer.port,
      expectedFingerprint: fingerprint,
      senderId: identity.id,
      senderFingerprint: identity.fingerprint,
    );
    await client.requestPair(
      id: identity.id,
      name: settings.deviceName,
      fingerprint: identity.fingerprint,
    );
    final token = await client.waitForPairApproval(identity.id);
    await ref
        .read(peersProvider.notifier)
        .markPairedRemotely(
          peer.copyWith(
            certificateFingerprint: fingerprint,
            sessionToken: token,
            pairingMethod: PairingMethod.request,
            pairedAt: DateTime.now(),
            trustLevel: TrustLevel.paired,
          ),
        );
  }

  /// Sender side: verify the receiver certificate, redeem the PIN, and store
  /// the resulting session token with the peer.
  Future<void> pairWith(PairingPayload payload) async {
    final identity = await ref.read(identityProvider.future);
    final client = WishareClient(
      host: payload.host,
      port: payload.port,
      expectedFingerprint: payload.fingerprint,
      senderFingerprint: identity.fingerprint,
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
