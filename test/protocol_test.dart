import 'package:flutter_test/flutter_test.dart';
import 'package:wishare/core/network/protocol.dart';

void main() {
  test('QR payload round-trips host, fingerprint and PIN', () {
    const payload = PairingPayload(
      host: '192.168.1.20',
      port: 45821,
      name: 'Living room PC',
      fingerprint: 'ABCDEF0123456789',
      pin: '123456',
    );
    final parsed = PairingPayload.fromUri(Uri.parse(payload.toQrUri()));
    expect(parsed.host, payload.host);
    expect(parsed.port, payload.port);
    expect(parsed.name, payload.name);
    expect(parsed.fingerprint, payload.fingerprint);
    expect(parsed.pin, payload.pin);
  });

  test('rejects non-Wishare QR codes', () {
    expect(
      () => PairingPayload.fromUri(Uri.parse('https://example.com')),
      throwsFormatException,
    );
  });

  test('rejects path traversal in folder transfers', () {
    expect(SafePath.sanitise('folder/photo.jpg'), 'folder/photo.jpg');
    expect(() => SafePath.sanitise('../secrets.txt'), throwsFormatException);
    expect(() => SafePath.sanitise('/etc/passwd'), throwsFormatException);
    expect(
      () => SafePath.sanitise(r'C:\Windows\system.ini'),
      throwsFormatException,
    );
  });

  test('fingerprints ignore spacing and case', () {
    expect(normaliseFingerprint('ab:cd ef-01'), 'ABCDEF01');
  });
}
