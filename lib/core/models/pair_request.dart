import 'parse_helpers.dart';
import '../network/protocol.dart';

/// A nearby device asking to pair without a QR code. The receiver approves or
/// declines it; no PIN is typed on either device.
///
/// My design decision (not in M3): request/approve pairing, with the sender's
/// TLS-observed fingerprint shown on the receiver so TOFU stays meaningful.
class PairRequest {
  const PairRequest({
    required this.id,
    required this.name,
    required this.fingerprint,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String fingerprint;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'fingerprint': fingerprint,
    'createdAt': createdAt.toIso8601String(),
  };

  factory PairRequest.fromJson(Map<String, dynamic> json) => PairRequest(
    id: text(json['id']) ?? '',
    name: text(json['name']) ?? 'Wishare device',
    fingerprint: normaliseFingerprint(text(json['fingerprint']) ?? ''),
    createdAt: dateTime(json['createdAt']) ?? DateTime.now(),
  );

  bool get isValid => isValidTransferId(id) && isValidFingerprint(fingerprint);
}
