enum PairingMethod { qr, manual }

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

  bool get isPaired =>
      trustLevel == TrustLevel.paired && pinnedCertificate != null;

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
    id: json['id'] as String,
    name: json['name'] as String,
    address: json['address'] as String,
    port: json['port'] as int,
    colorSeed: json['colorSeed'] as int? ?? 0xFF6750A4,
    certificateFingerprint: json['certificateFingerprint'] as String?,
    pinnedCertificate: json['pinnedCertificate'] as String?,
    sessionToken: json['sessionToken'] as String?,
    pairingMethod: json['pairingMethod'] == null
        ? null
        : PairingMethod.values.byName(json['pairingMethod'] as String),
    pairedAt: json['pairedAt'] == null
        ? null
        : DateTime.parse(json['pairedAt'] as String),
    lastSeen: json['lastSeen'] == null
        ? null
        : DateTime.parse(json['lastSeen'] as String),
    trustLevel: json['trustLevel'] == null
        ? TrustLevel.untrusted
        : TrustLevel.values.byName(json['trustLevel'] as String),
  );
}
