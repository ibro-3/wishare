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
    required this._identity,
    required this._enabled,
    required this._broadcast,
  });

  final DeviceIdentity _identity;
  final bool _enabled;
  final bool _broadcast;

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
        if (event != RawSocketEvent.read) return;
        final datagram = _socket!.receive();
        if (datagram == null) return;
        _handleDatagram(datagram);
      });
      if (_broadcast) {
        _heartbeat = Timer.periodic(
          const Duration(seconds: 5),
          (_) => _announce(),
        );
        _announce();
      }
    }
    // mDNS responder answers standard DNS-SD queries in parallel with the
    // broadcast heartbeat. Both are best-effort.
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );
    final localAddress =
        interfaces.isNotEmpty && interfaces.first.addresses.isNotEmpty
        ? interfaces.first.addresses.first.address
        : '127.0.0.1';
    _mdns = MDnsResponder(identity: _identity, address: localAddress);
    await _mdns!.start();
    _pruner = Timer.periodic(const Duration(seconds: 5), (_) {
      final cutoff = DateTime.now().subtract(const Duration(seconds: 20));
      final expired = _peers.entries
          .where((e) => e.value.lastSeen!.isBefore(cutoff))
          .map((e) => e.key)
          .toList();
      for (final id in expired) {
        _peers.remove(id);
      }
      _emit();
    });
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
    final bytes = utf8.encode(payload);
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );
    if (interfaces.isEmpty) {
      _sendBroadcast(bytes);
      return;
    }
    for (final _ in interfaces) {
      _sendBroadcast(bytes);
    }
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
    } on FormatException {
      return;
    }
    if (decoded is! Map<String, dynamic> || decoded['t'] != 'announce') return;
    final id = decoded['id'] as String?;
    if (id == null || id == _identity.id) return;
    final port = decoded['port'] as int? ?? WiProtocol.port;
    _peers[id] = Peer(
      id: id,
      name: decoded['name'] as String? ?? 'Wishare device',
      address: datagram.address.address,
      port: port,
      colorSeed: 0xFF6750A4,
      certificateFingerprint: decoded['fp'] as String?,
      lastSeen: DateTime.now(),
    );
    _emit();
  }

  /// Add a peer discovered by QR or manual entry.
  void upsert(Peer peer) {
    _peers[peer.id] = peer;
    _emit();
  }

  void _emit() => _controller.add(List.unmodifiable(_peers.values.toList()));

  Future<void> stop() async {
    _heartbeat?.cancel();
    _pruner?.cancel();
    _socket?.close();
    _socket = null;
    await _mdns?.stop();
    _mdns = null;
    await _controller.close();
  }
}
