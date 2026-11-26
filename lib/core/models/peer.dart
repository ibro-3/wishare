import '../network/protocol.dart';
import 'parse_helpers.dart';

enum PairingMethod { qr, manual, request }

enum TrustLevel { paired, untrusted, revoked }

class Peer {
  const Peer({
    required this.id,
    required this.name,
    required this.address,
    required this.port,
    required this.colorSeed,
    this.certificateFingerprint,
    this.pinnedCertificate,
    this.sessionToken,
    this.pairingMethod,
    this.pairedAt,
    this.lastSeen,
    this.trustLevel = TrustLevel.untrusted,
  });

  final String id;
  final String name;
  final String address;
  final int port;
  final int colorSeed;
  final String? certificateFingerprint;
  final String? pinnedCertificate;
  final String? sessionToken;
  final PairingMethod? pairingMethod;
  final DateTime? pairedAt;
  final DateTime? lastSeen;
  final TrustLevel trustLevel;

  /// A peer is usable once pairing has been recorded *and* we have either a
  /// session token (sender side) or a valid TOFU fingerprint (receiver side).
  /// A paired flag alone must never enable sending.
  bool get isPaired {
    if (trustLevel != TrustLevel.paired) return false;
    if (sessionToken != null && sessionToken!.isNotEmpty) return true;
    final fingerprint = certificateFingerprint;
    return fingerprint != null && isValidFingerprint(fingerprint);
  }

  String get endpoint => '$address:$port';

  Peer copyWith({
    String? id,
    String? name,
    String? address,
    int? port,
    int? colorSeed,
    String? certificateFingerprint,
    String? pinnedCertificate,
    String? sessionToken,
    PairingMethod? pairingMethod,
    DateTime? pairedAt,
    DateTime? lastSeen,
    TrustLevel? trustLevel,
  }) {
    return Peer(
      id: id ?? this.id,
      name: name ?? this.name,
      address: address ?? this.address,
      port: port ?? this.port,
      colorSeed: colorSeed ?? this.colorSeed,
      certificateFingerprint:
          certificateFingerprint ?? this.certificateFingerprint,
      pinnedCertificate: pinnedCertificate ?? this.pinnedCertificate,
      sessionToken: sessionToken ?? this.sessionToken,
      pairingMethod: pairingMethod ?? this.pairingMethod,
      pairedAt: pairedAt ?? this.pairedAt,
      lastSeen: lastSeen ?? this.lastSeen,
      trustLevel: trustLevel ?? this.trustLevel,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'address': address,
    'port': port,
    'colorSeed': colorSeed,
    'certificateFingerprint': certificateFingerprint,
    'pinnedCertificate': pinnedCertificate,
    'sessionToken': sessionToken,
    'pairingMethod': pairingMethod?.name,
    'pairedAt': pairedAt?.toIso8601String(),
    'lastSeen': lastSeen?.toIso8601String(),
    'trustLevel': trustLevel.name,
  };

  factory Peer.fromJson(Map<String, dynamic> json) => Peer(
    id: text(json['id']) ?? '',
    name: text(json['name']) ?? 'Wishare device',
    address: text(json['address']) ?? '',
    port: integer(json['port'], 0),
    colorSeed: integer(json['colorSeed'], 0xFF6750A4),
    certificateFingerprint: text(json['certificateFingerprint']),
    pinnedCertificate: text(json['pinnedCertificate']),
    sessionToken: text(json['sessionToken']),
    pairingMethod: enumByName(PairingMethod.values, json['pairingMethod']),
    pairedAt: dateTime(json['pairedAt']),
    lastSeen: dateTime(json['lastSeen']),
    trustLevel:
        enumByName(TrustLevel.values, json['trustLevel']) ??
        TrustLevel.untrusted,
  );
}
