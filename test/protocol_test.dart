import 'package:flutter_test/flutter_test.dart';
import 'package:wishare/core/network/protocol.dart';

void main() {
  const fingerprint =
      'ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789';

  test('QR payload round-trips host, fingerprint and PIN', () {
    const payload = PairingPayload(
      host: '192.168.1.20',
      port: 45821,
      name: 'Living room PC',
      fingerprint: fingerprint,
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

  test('rejects malformed pairing QR codes', () {
    PairingPayload payload({
      String host = '192.168.1.20',
      int port = 45821,
      String fp = fingerprint,
      String pin = '123456',
    }) => PairingPayload(
      host: host,
      port: port,
      name: 'PC',
      fingerprint: fp,
      pin: pin,
    );
    for (final bad in [
      payload(host: ''),
      payload(port: 0),
      payload(port: 70000),
      payload(fp: 'NOT-HEX'),
      payload(pin: 'abc'),
    ]) {
      expect(
        () => PairingPayload.fromUri(Uri.parse(bad.toQrUri())),
        throwsFormatException,
      );
    }
  });

  test('fingerprint helpers are safe on short or malformed input', () {
    expect(isValidFingerprint(fingerprint), isTrue);
    expect(isValidFingerprint('ABCDEF'), isFalse);
    expect(abbreviateFingerprint(''), '—');
    expect(abbreviateFingerprint('AB'), 'AB');
    expect(abbreviateFingerprint(fingerprint), 'ABCDEF01…23456789');
  });
}
