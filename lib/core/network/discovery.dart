import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../crypto/certificate_manager.dart';
import 'mdns_responder.dart';
import '../models/peer.dart';
import 'protocol.dart';

/// LAN discovery via UDP broadcast heartbeat (my design decision).
///
/// mDNS is supported for interoperability with other `_wishare._tcp.local`
/// implementations, but our own advertisement uses broadcast because a Dart
/// mDNS responder is not available in `multicast_dns` v0.3.
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
  Timer? _heartbeat;
  Timer? _pruner;
  final Map<String, Peer> _peers = {};
  final StreamController<List<Peer>> _controller =
      StreamController<List<Peer>>.broadcast();

  Stream<List<Peer>> get peers => _controller.stream;

  List<Peer> get current => List.unmodifiable(_peers.values);

  Future<void> start() async {
    if (!_enabled) return;
    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        WiProtocol.port,
        reuseAddress: true,
        reusePort: true,
      );
    } on SocketException {
      // Broadcast discovery is best-effort; mDNS and manual/QR still work.
      _socket = null;
    }
    if (_socket != null) {
      _socket!.listen((event) {
        // A malformed datagram must never take down the discovery service.
        try {
          if (event != RawSocketEvent.read) return;
          final datagram = _socket?.receive();
          if (datagram == null) return;
          _handleDatagram(datagram);
        } on Object {
          // Ignore this packet and keep listening.
        }
      });
      _startHeartbeat();
    }
    await _startMdns();
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
  }

  Future<void> _startMdns() async {
    if (_mdns != null) return;
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );
    final localAddress =
        interfaces.isNotEmpty && interfaces.first.addresses.isNotEmpty
        ? interfaces.first.addresses.first.address
        : '127.0.0.1';
    _mdns = MDnsResponder(identity: _identity, address: localAddress);
    try {
      await _mdns!.start();
    } on Object {
      _mdns = null;
    }
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
      _heartbeat?.cancel();
      _heartbeat = null;
      _socket?.close();
      _socket = null;
      unawaited(_mdns?.stop());
      _mdns = null;
      return;
    }
    if (_socket == null) {
      unawaited(start());
      return;
    }
    _startHeartbeat();
    unawaited(_startMdns());
  }

  Future<void> _announce() async {
    final payload = jsonEncode({
      't': 'announce',
      'id': _identity.id,
      'name': _identity.name,
      'port': WiProtocol.port,
      'fp': _identity.fingerprint,
      'v': WiProtocol.version,
    });
    // One datagram reaches every device on the local broadcast domain; N
    // interfaces do not need N copies.
    _sendBroadcast(utf8.encode(payload));
  }

  void _sendBroadcast(List<int> bytes) {
    try {
      _socket?.send(bytes, InternetAddress('255.255.255.255'), WiProtocol.port);
    } on SocketException {
      // Some platforms disallow directed broadcast; the manual/QR path
      // remains available.
    }
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

  void _emit() => _controller.add(List.unmodifiable(_peers.values.toList()));

  /// Stop advertising/listening while keeping the stream reusable.
  Future<void> stop() async {
    _heartbeat?.cancel();
    _heartbeat = null;
    _pruner?.cancel();
    _pruner = null;
    _socket?.close();
    _socket = null;
    await _mdns?.stop();
    _mdns = null;
  }

  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }
}
