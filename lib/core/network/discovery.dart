import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:multicast_dns/multicast_dns.dart';

import '../crypto/certificate_manager.dart';
import '../platform/android_multicast.dart';
import 'mdns_responder.dart';
import '../models/peer.dart';
import 'protocol.dart';

/// LAN discovery: a UDP broadcast heartbeat plus an mDNS/DNS-SD querier.
///
/// `multicast_dns` is a client-only package, so our own advertisement uses a
/// broadcast heartbeat and a small mDNS responder. Both paths feed the same
/// peer list; manual IP/QR pairing remains the fallback when a network blocks
/// all local discovery.
class DiscoveryService {
  DiscoveryService({
    required DeviceIdentity identity,
    required bool enabled,
    required bool broadcast,
  }) : _identity = identity, // ignore: prefer_initializing_formals
       _enabled = enabled, // ignore: prefer_initializing_formals
       _broadcast = broadcast; // ignore: prefer_initializing_formals

  final DeviceIdentity _identity;
  bool _enabled;
  bool _broadcast;

  RawDatagramSocket? _socket;
  MDnsResponder? _mdns;
  MDnsClient? _mdnsClient;
  Timer? _heartbeat;
  Timer? _pruner;
  Timer? _mdnsQuery;
  bool _starting = false;
  bool _restartRequested = false;
  bool _multicastLockHeld = false;
  List<InternetAddress> _broadcastTargets = const [];
  NetworkInterface? _preferredInterface;
  String _localAddress = '127.0.0.1';
  final Map<String, Peer> _peers = {};
  final StreamController<List<Peer>> _controller =
      StreamController<List<Peer>>.broadcast();
  final StreamController<String> _errors = StreamController<String>.broadcast();

  Stream<List<Peer>> get peers => _controller.stream;

  /// Discovery/transport errors worth showing in the UI. An empty string
  /// means the last problem cleared.
  Stream<String> get errors => _errors.stream;

  String? get lastError => _lastError;
  String? _lastError;

  /// True once the UDP socket is bound with IPv4 broadcast enabled.
  bool get broadcastReady => _socket?.broadcastEnabled ?? false;

  List<Peer> get current => List.unmodifiable(_peers.values);

  Future<void> start() async {
    if (!_enabled || _starting || _socket != null) return;
    _starting = true;
    try {
      // Bind to the LAN address we also advertise in QR codes. Binding to
      // anyIPv4 lets the OS pick the default route, which on multi-adapter
      // machines can be a VPN; heartbeats then leave the wrong interface.
      _localAddress = await preferredLocalAddress();
      final interfaces = await _interfaces();
      _preferredInterface = interfaceFor(interfaces, _localAddress);
      final bindAddress = _localAddress == '127.0.0.1'
          ? InternetAddress.anyIPv4
          : InternetAddress(_localAddress);
      var boundToAny = bindAddress.address == InternetAddress.anyIPv4.address;
      try {
        final socket = await RawDatagramSocket.bind(
          bindAddress,
          WiProtocol.port,
          reuseAddress: true,
          reusePort: true,
        );
        // Dart disables IPv4 broadcast by default. Without this flag sending
        // to a broadcast address fails and the heartbeat never leaves the
        // device.
        socket.broadcastEnabled = true;
        // A settings toggle may have disabled discovery while we awaited.
        if (!_enabled) {
          socket.close();
          return;
        }
        _socket = socket;
      } on Object catch (error) {
        // Some platforms refuse binding to a specific address. Fall back to
        // the wildcard socket rather than losing broadcast discovery.
        if (!boundToAny) {
          try {
            final socket = await RawDatagramSocket.bind(
              InternetAddress.anyIPv4,
              WiProtocol.port,
              reuseAddress: true,
              reusePort: true,
            );
            socket.broadcastEnabled = true;
            if (!_enabled) {
              socket.close();
              return;
            }
            _socket = socket;
            boundToAny = true;
          } on Object catch (fallbackError) {
            _reportError('Broadcast discovery unavailable: $fallbackError');
          }
        } else {
          _reportError('Broadcast discovery unavailable: $error');
        }
      }
      if (_socket != null) {
        _broadcastTargets = boundToAny || _localAddress == '127.0.0.1'
            ? broadcastTargets(interfaces)
            : broadcastTargetsFor(interfaces, _localAddress);
        _socket!.listen(
          (event) {
            // A malformed datagram must never take down the discovery service.
            try {
              if (event != RawSocketEvent.read) return;
              final datagram = _socket?.receive();
              if (datagram == null) return;
              _handleDatagram(datagram);
            } on Object {
              // Ignore this packet and keep listening.
            }
          },
          onError: (Object error) =>
              _reportError('Discovery socket error: $error'),
        );
        _startHeartbeat();
      }
      if (_enabled) await _startMdns();
      if (!_enabled) return;
      _pruner?.cancel();
      _pruner = Timer.periodic(const Duration(seconds: 5), (_) {
        final cutoff = DateTime.now().subtract(const Duration(seconds: 20));
        final expired = _peers.entries
            .where((entry) => entry.value.lastSeen?.isBefore(cutoff) ?? false)
            .map((entry) => entry.key)
            .toList();
        for (final id in expired) {
          _peers.remove(id);
        }
        _emit();
      });
    } finally {
      _starting = false;
      if (_restartRequested) {
        _restartRequested = false;
        if (_enabled && _socket == null) unawaited(start());
      }
    }
  }

  /// Immediately announce and re-run the mDNS query. Used by the Send tab's
  /// "Scan again" action when the periodic heartbeat has not found anything.
  Future<void> rescan() async {
    if (!_enabled) return;
    if (_socket == null && !_starting) {
      await start();
      return;
    }
    _announce();
    if (_mdnsClient != null) await _queryMdns();
  }

  static Future<List<NetworkInterface>> _interfaces() => NetworkInterface.list(
    includeLoopback: false,
    type: InternetAddressType.IPv4,
  );

  /// Prefer the interface broadcast addresses so Android and home routers
  /// actually forward the heartbeat; the global address is a fallback.
  static List<InternetAddress> broadcastTargets(
    Iterable<NetworkInterface> interfaces,
  ) {
    final seen = <String>{};
    final targets = <InternetAddress>[];
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        final broadcast = address.broadcast;
        if (broadcast == null || !seen.add(broadcast.address)) continue;
        targets.add(broadcast);
      }
    }
    final global = InternetAddress('255.255.255.255');
    if (seen.add(global.address)) targets.add(global);
    return targets;
  }

  /// The interface that owns [address], if any. Used to pin multicast joins
  /// and heartbeats to the same LAN as the advertised QR address.
  static NetworkInterface? interfaceFor(
    Iterable<NetworkInterface> interfaces,
    String address,
  ) {
    for (final interface in interfaces) {
      if (interface.addresses.any((entry) => entry.address == address)) {
        return interface;
      }
    }
    return null;
  }

  /// Broadcast only from the interface that owns our LAN address. The global
  /// fallback stays in the list, but VPN/virtual interfaces are not used as
  /// additional sources — their broadcasts cannot reach LAN peers.
  static List<InternetAddress> broadcastTargetsFor(
    Iterable<NetworkInterface> interfaces,
    String address,
  ) {
    final seen = <String>{};
    final targets = <InternetAddress>[];
    final preferred = interfaceFor(interfaces, address);
    if (preferred != null) {
      for (final entry in preferred.addresses) {
        final broadcast = entry.broadcast;
        if (broadcast == null || !seen.add(broadcast.address)) continue;
        targets.add(broadcast);
      }
    }
    final global = InternetAddress('255.255.255.255');
    if (seen.add(global.address)) targets.add(global);
    return targets;
  }

  /// Pick a usable LAN address, ignoring virtual interfaces (Docker, VPN,
  /// bridges) that would produce an unreachable QR pairing code.
  static Future<String> preferredLocalAddress() async {
    final interfaces = await _interfaces();
    final candidates = <(int, String)>[];
    for (final interface in interfaces) {
      final name = interface.name.toLowerCase();
      if (const [
        'docker',
        'br-',
        'veth',
        'virbr',
        'vboxnet',
        'vmnet',
        'tun',
        'tap',
        'wg',
        'tailscale',
        'ppp',
        'dummy',
      ].any(name.startsWith)) {
        continue;
      }
      final score = name.startsWith('wlan') || name.startsWith('wlp')
          ? 3
          : name.startsWith('eth') || name.startsWith('enp')
          ? 2
          : 1;
      for (final address in interface.addresses) {
        if (address.isLoopback || address.address.startsWith('169.254.')) {
          continue;
        }
        if (address.broadcast == null) continue;
        candidates.add((score, address.address));
      }
    }
    candidates.sort((a, b) => b.$1.compareTo(a.$1));
    return candidates.isEmpty ? '127.0.0.1' : candidates.first.$2;
  }

  Future<void> _startMdns() async {
    if (!_enabled || (_mdns != null && _mdnsClient != null)) return;
    if (!_multicastLockHeld) {
      await AndroidMulticast.acquire();
      _multicastLockHeld = true;
    }
    _mdns = MDnsResponder(
      identity: _identity,
      address: _localAddress,
      interface: _preferredInterface,
    );
    try {
      await _mdns!.start();
    } on Object catch (error) {
      _mdns = null;
      _reportError('mDNS responder unavailable: $error');
    }

    // MDnsClient asserts listenAddress is the wildcard address, so pin the
    // socket factory instead. Sending queries from the LAN address keeps mDNS
    // off a VPN default route — a common reason devices stay hidden.
    _mdnsClient = MDnsClient(
      rawDatagramSocketFactory:
          (
            dynamic host,
            int port, {
            bool reuseAddress = false,
            bool reusePort = false,
            int ttl = 0,
          }) async {
            final bindHost =
                _localAddress != '127.0.0.1' &&
                    host.toString() == InternetAddress.anyIPv4.address
                ? _localAddress
                : host;
            try {
              return await RawDatagramSocket.bind(
                bindHost,
                port,
                reuseAddress: reuseAddress,
                reusePort: reusePort,
                ttl: ttl,
              );
            } on SocketException {
              if (bindHost == host) rethrow;
              return RawDatagramSocket.bind(
                host,
                port,
                reuseAddress: reuseAddress,
                reusePort: reusePort,
                ttl: ttl,
              );
            }
          },
    );
    try {
      await _mdnsClient!.start(
        interfacesFactory: (type) => _interfaces(),
        onError: (Object error) => _reportError('mDNS client error: $error'),
      );
      if (!_enabled) {
        _mdnsClient?.stop();
        _mdnsClient = null;
        return;
      }
      // Do not await the first lookup: a one-shot mDNS query can take up to
      // its five-second timeout and must never delay app startup.
      unawaited(_queryMdns());
      _mdnsQuery?.cancel();
      _mdnsQuery = Timer.periodic(
        const Duration(seconds: 10),
        (_) => unawaited(_queryMdns()),
      );
    } on Object catch (error) {
      _mdnsClient?.stop();
      _mdnsClient = null;
      _reportError('mDNS discovery unavailable: $error');
    }
    if (_mdns == null && _mdnsClient == null) await _releaseMulticast();
  }

  /// One-shot mDNS query: find instances, then read their TXT/A records. Our
  /// responder answers both, so two Wishare apps can find each other even if
  /// UDP broadcast is blocked by the network.
  Future<void> _queryMdns() async {
    final client = _mdnsClient;
    if (client == null) return;
    try {
      final pointers = await client
          .lookup<PtrResourceRecord>(
            ResourceRecordQuery.serverPointer(WiProtocol.serviceType),
          )
          .toList();
      for (final pointer in pointers) {
        final instance = pointer.domainName;
        if (!instance.toLowerCase().endsWith('.${WiProtocol.serviceType}')) {
          continue;
        }
        final txt = await client
            .lookup<TxtResourceRecord>(ResourceRecordQuery.text(instance))
            .toList();
        final addresses = await client
            .lookup<IPAddressResourceRecord>(
              ResourceRecordQuery.addressIPv4(instance),
            )
            .toList();
        final addressRecord = addresses.firstOrNull;
        if (addressRecord == null) continue;
        final address = addressRecord.address.address;
        // multicast_dns serves records from a TTL cache. Only a recently
        // refreshed record may extend a peer's lifetime, otherwise a device
        // that left the LAN would linger for the full 120 s TTL.
        final fresh = isFreshMdnsRecord(addressRecord);
        final fields = <String, String>{};
        for (final line in (txt.firstOrNull?.text ?? '').split(
          RegExp(r'[\r\n]+'),
        )) {
          final separator = line.indexOf('=');
          if (separator < 1) continue;
          fields[line.substring(0, separator)] = line.substring(separator + 1);
        }
        final id = fields['id'] ?? instance.split('.').first;
        if (id.isEmpty || id == _identity.id) continue;
        final port = int.tryParse(fields['port'] ?? '') ?? WiProtocol.port;
        if (port < 1 || port > 65535) continue;
        final fingerprint = fields['fp'] ?? '';
        final name = fields['name'];
        final previous = _peers[id];
        if (!fresh && previous == null) continue;
        _peers[id] = Peer(
          id: id,
          name: name != null && name.isNotEmpty ? name : 'Wishare device',
          address: address,
          port: port,
          colorSeed: 0xFF6750A4,
          certificateFingerprint: isValidFingerprint(fingerprint)
              ? normaliseFingerprint(fingerprint)
              : null,
          lastSeen: fresh
              ? DateTime.now()
              : previous?.lastSeen ??
                    DateTime.now().subtract(const Duration(seconds: 21)),
        );
      }
      if (pointers.isNotEmpty) _emit();
    } on Object catch (error) {
      _reportError('mDNS lookup failed: $error');
    }
  }

  /// True when an mDNS record still has most of its 120 s TTL, i.e. it came
  /// from a recent response rather than the querier's cache.
  static bool isFreshMdnsRecord(ResourceRecord record) =>
      record.validUntil - DateTime.now().millisecondsSinceEpoch > 100000;

  Future<void> _releaseMulticast() async {
    if (!_multicastLockHeld) return;
    _multicastLockHeld = false;
    await AndroidMulticast.release();
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = null;
    if (!_enabled || !_broadcast || _socket == null) return;
    _heartbeat = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(_announce()),
    );
    unawaited(_announce());
  }

  /// Apply discovery toggles without rebuilding the network controller.
  void applySettings({
    required bool discoveryEnabled,
    required bool broadcastEnabled,
  }) {
    _enabled = discoveryEnabled;
    _broadcast = broadcastEnabled;
    if (!_enabled) {
      _restartRequested = false;
      _heartbeat?.cancel();
      _heartbeat = null;
      _socket?.close();
      _socket = null;
      unawaited(_stopMdns());
      return;
    }
    if (_socket == null) {
      if (_starting) {
        _restartRequested = true;
      } else {
        unawaited(start());
      }
      return;
    }
    _startHeartbeat();
    unawaited(_startMdns());
  }

  Future<void> _announce() async {
    if (!_enabled || !_broadcast) return;
    final payload = jsonEncode({
      't': 'announce',
      'id': _identity.id,
      'name': _identity.name,
      'port': WiProtocol.port,
      'fp': _identity.fingerprint,
      'v': WiProtocol.version,
    });
    _sendBroadcast(utf8.encode(payload));
  }

  void _sendBroadcast(List<int> bytes) {
    final socket = _socket;
    if (socket == null) return;
    final targets = _broadcastTargets.isEmpty
        ? [InternetAddress('255.255.255.255')]
        : _broadcastTargets;
    var sent = 0;
    for (final target in targets) {
      try {
        if (socket.send(bytes, target, WiProtocol.port) > 0) sent++;
      } on Object catch (error) {
        _reportError('Could not send discovery heartbeat: $error');
      }
    }
    if (sent > 0) _clearError();
  }

  void _handleDatagram(Datagram datagram) {
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(datagram.data));
    } on Object {
      return;
    }
    if (decoded is! Map || decoded['t'] != 'announce') return;
    final id = decoded['id'];
    if (id is! String || id.isEmpty || id == _identity.id) return;

    final rawPort = decoded['port'];
    final port = rawPort is int ? rawPort : WiProtocol.port;
    if (port < 1 || port > 65535) return;

    final name = decoded['name'];
    final fingerprint = decoded['fp'];
    _peers[id] = Peer(
      id: id,
      name: name is String && name.isNotEmpty ? name : 'Wishare device',
      address: datagram.address.address,
      port: port,
      colorSeed: 0xFF6750A4,
      certificateFingerprint:
          fingerprint is String && isValidFingerprint(fingerprint)
          ? normaliseFingerprint(fingerprint)
          : null,
      lastSeen: DateTime.now(),
    );
    _emit();
  }

  void _reportError(Object error) {
    final message = error.toString();
    if (message == _lastError) return;
    _lastError = message;
    if (!_errors.isClosed) _errors.add(message);
  }

  void _clearError() {
    if (_lastError == null) return;
    _lastError = null;
    if (!_errors.isClosed) _errors.add('');
  }

  void _emit() => _controller.add(List.unmodifiable(_peers.values.toList()));

  Future<void> _stopMdns() async {
    _mdnsQuery?.cancel();
    _mdnsQuery = null;
    _mdnsClient?.stop();
    _mdnsClient = null;
    await _mdns?.stop();
    _mdns = null;
    await _releaseMulticast();
  }

  /// Stop advertising/listening while keeping the stream reusable.
  Future<void> stop() async {
    _heartbeat?.cancel();
    _heartbeat = null;
    _pruner?.cancel();
    _pruner = null;
    _socket?.close();
    _socket = null;
    _broadcastTargets = const [];
    await _stopMdns();
  }

  Future<void> dispose() async {
    await stop();
    await _controller.close();
    await _errors.close();
  }
}
