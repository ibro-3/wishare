import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../crypto/certificate_manager.dart';
import 'protocol.dart';

/// Minimal mDNS/DNS-SD responder for `_wishare._tcp.local`.
///
/// My design decision: `multicast_dns` is a client-only package, so this
/// responder answers PTR/SRV/TXT/A questions directly over UDP 5353. UDP
/// broadcast discovery remains the primary LAN path, with manual IP/QR as the
/// fallback; this adds standards-based discovery for other mDNS browsers.
abstract final class MDnsProtocol {
  static const String serviceName = '_wishare._tcp.local';
  static const String enumerationName = '_services._dns-sd._udp.local';
  static const int ptr = 12;
  static const int srv = 33;
  static const int txt = 16;
  static const int a = 1;

  static Uint8List encodeName(String name) {
    final bytes = <int>[];
    for (final label in name.split('.')) {
      if (label.isEmpty) continue;
      final labelBytes = utf8.encode(label);
      if (labelBytes.length > 63) {
        throw FormatException('DNS label too long: $label');
      }
      bytes.add(labelBytes.length);
      bytes.addAll(labelBytes);
    }
    bytes.add(0);
    return Uint8List.fromList(bytes);
  }

  static MDnsQuestion? parseQuestion(Uint8List data) {
    if (data.length < 12) return null;
    final id = (data[0] << 8) | data[1];
    final flags = (data[2] << 8) | data[3];
    if (flags & 0x8000 != 0) return null; // ignore responses
    final questionCount = (data[4] << 8) | data[5];
    if (questionCount < 1) return null;

    var position = 12;
    final labels = <String>[];
    while (position < data.length) {
      final length = data[position++];
      if (length == 0) break;
      if (length & 0xC0 != 0) return null; // compressed names unsupported here
      if (position + length > data.length) return null;
      labels.add(utf8.decode(data.sublist(position, position + length)));
      position += length;
    }
    if (position + 4 > data.length) return null;
    final type = (data[position] << 8) | data[position + 1];
    final klass = (data[position + 2] << 8) | data[position + 3];
    return MDnsQuestion(
      id: id,
      name: labels.join('.').toLowerCase(),
      type: type,
      klass: klass,
      bytes: Uint8List.fromList(data.sublist(12, position + 4)),
    );
  }

  static Uint8List buildResponse({
    required MDnsQuestion question,
    required String ptrTarget,
    required DeviceIdentity identity,
    required String address,
    required int port,
    String? recordName,
  }) {
    final out = BytesBuilder(copy: false);
    void u16(int value) {
      out.add([(value >> 8) & 0xFF, value & 0xFF]);
    }

    void u32(int value) {
      out.add([
        (value >> 24) & 0xFF,
        (value >> 16) & 0xFF,
        (value >> 8) & 0xFF,
        value & 0xFF,
      ]);
    }

    void record({
      required List<int> name,
      required int type,
      required int klass,
      required int ttl,
      required List<int> rdata,
    }) {
      out.add(name);
      u16(type);
      u16(klass);
      u32(ttl);
      u16(rdata.length);
      out.add(rdata);
    }

    // Header: response, authoritative answer, 1 question, 1 answer, 4 extras
    // (SRV, TXT, A for the instance and A for the SRV target host).
    u16(question.id);
    u16(0x8400);
    u16(1);
    u16(1);
    u16(0);
    u16(4);
    out.add(question.bytes);

    final instanceName = recordName ?? ptrTarget;
    record(
      name: const [0xC0, 0x0C],
      type: ptr,
      klass: 1,
      ttl: 120,
      rdata: encodeName(ptrTarget),
    );

    // SRV rdata: priority, weight, port, then the target hostname.
    final srvData = BytesBuilder(copy: false)
      ..add([0, 0, 0, 0, (port >> 8) & 0xFF, port & 0xFF])
      ..add(encodeName('${identity.id}.local'));
    record(
      name: MDnsProtocol.encodeName(instanceName),
      type: MDnsProtocol.srv,
      klass: 1,
      ttl: 120,
      rdata: srvData.takeBytes(),
    );

    final txtData = BytesBuilder(copy: false);
    for (final entry in {
      'id': identity.id,
      'name': identity.name,
      'port': '$port',
      'fp': identity.fingerprint,
      'v': WiProtocol.version,
    }.entries) {
      final value = utf8.encode('${entry.key}=${entry.value}');
      if (value.length > 255) continue;
      txtData.add([value.length]);
      txtData.add(value);
    }
    record(
      name: MDnsProtocol.encodeName(instanceName),
      type: MDnsProtocol.txt,
      klass: 1,
      ttl: 120,
      rdata: txtData.takeBytes(),
    );

    final addressRecord = InternetAddress(address).rawAddress;
    record(
      name: MDnsProtocol.encodeName(instanceName),
      type: MDnsProtocol.a,
      klass: 1,
      ttl: 120,
      rdata: addressRecord,
    );
    // Our own querier resolves the instance name above. Standard DNS-SD
    // browsers first read SRV and then query its target, so publish that A
    // record too.
    record(
      name: MDnsProtocol.encodeName('${identity.id}.local'),
      type: MDnsProtocol.a,
      klass: 1,
      ttl: 120,
      rdata: addressRecord,
    );

    return out.takeBytes();
  }
}

class MDnsQuestion {
  const MDnsQuestion({
    required this.id,
    required this.name,
    required this.type,
    required this.klass,
    required this.bytes,
  });

  final int id;
  final String name;
  final int type;
  final int klass;
  final Uint8List bytes;

  bool get isWishareQuery =>
      name == MDnsProtocol.serviceName ||
      name.endsWith('.${MDnsProtocol.serviceName}') ||
      name == MDnsProtocol.enumerationName;
}

class MDnsResponder {
  MDnsResponder({
    required this.identity,
    required this.address,
    this.interface,
  });

  final DeviceIdentity identity;
  final String address;

  /// Optional interface to join the multicast group on. Pinning this to the
  /// same interface as [address] keeps mDNS traffic off VPN/virtual adapters.
  final NetworkInterface? interface;

  static final InternetAddress _multicast = InternetAddress('224.0.0.251');
  static const int _port = 5353;

  RawDatagramSocket? _socket;

  bool get isRunning => _socket != null;

  Future<void> start() async {
    if (_socket != null) return;
    try {
      final bindAddress = address == '127.0.0.1'
          ? InternetAddress.anyIPv4
          : InternetAddress(address);
      RawDatagramSocket socket;
      try {
        socket = await RawDatagramSocket.bind(
          bindAddress,
          _port,
          reuseAddress: true,
          reusePort: true,
          ttl: 255, // mDNS requires TTL 255.
        );
      } on SocketException {
        // Fall back to the wildcard bind where a platform disallows binding
        // mDNS to a specific interface address.
        socket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          _port,
          reuseAddress: true,
          reusePort: true,
          ttl: 255,
        );
      }
      if (interface != null) {
        socket.joinMulticast(_multicast, interface);
      } else {
        socket.joinMulticast(_multicast);
      }
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket.receive();
        if (datagram == null) return;
        final question = MDnsProtocol.parseQuestion(datagram.data);
        if (question == null || !question.isWishareQuery) return;
        // A service/enumeration question advertises our instance; a direct
        // instance question (from an mDNS querier) echoes its own name so the
        // SRV/TXT/A records match what the querier is looking for.
        final isEnumeration = question.name == MDnsProtocol.enumerationName;
        final instanceName = '${identity.id}.${MDnsProtocol.serviceName}';
        final ptrTarget = isEnumeration
            ? MDnsProtocol.serviceName
            : question.name == MDnsProtocol.serviceName
            ? instanceName
            : question.name;
        final response = MDnsProtocol.buildResponse(
          question: question,
          ptrTarget: ptrTarget,
          recordName: isEnumeration ? instanceName : null,
          identity: identity,
          address: address,
          port: WiProtocol.port,
        );
        try {
          socket.send(response, datagram.address, datagram.port);
        } on SocketException {
          // Ignore platforms that block multicast replies.
        }
      });
      _socket = socket;
    } on SocketException {
      // Broadcast discovery and manual pairing remain available.
    }
  }

  Future<void> stop() async {
    _socket?.close();
    _socket = null;
  }
}
