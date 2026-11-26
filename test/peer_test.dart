import 'package:flutter_test/flutter_test.dart';
import 'package:wishare/core/models/peer.dart';
import 'package:wishare/core/network/protocol.dart';

void main() {
  const fingerprint =
      'ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789';

  Peer peer({
    String? pinnedCertificate,
    String? sessionToken,
    String? certificateFingerprint,
    TrustLevel trust = TrustLevel.paired,
  }) => Peer(
    id: 'peer-1',
    name: 'Living room PC',
    address: '192.168.1.20',
    port: 45821,
    colorSeed: 0xFF6750A4,
    pinnedCertificate: pinnedCertificate,
    sessionToken: sessionToken,
    certificateFingerprint: certificateFingerprint,
    trustLevel: trust,
  );

  test('sender-side pairing with a session token is usable', () {
    expect(
      peer(sessionToken: 'token-123').isPaired,
      isTrue,
      reason: 'QR pairing from the Send side stores a token, no pinned cert',
    );
  });

  test('receiver-side pairing with a full fingerprint is usable', () {
    expect(peer(certificateFingerprint: fingerprint).isPaired, isTrue);
  });

  test('a paired flag alone never enables sending', () {
    expect(peer().isPaired, isFalse);
    expect(
      peer(sessionToken: '', certificateFingerprint: 'TOO-SHORT').isPaired,
      isFalse,
    );
    expect(
      peer(sessionToken: 'token', trust: TrustLevel.untrusted).isPaired,
      isFalse,
    );
    expect(isValidFingerprint(fingerprint), isTrue);
  });
}
