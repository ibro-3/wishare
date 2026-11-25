import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wishare/core/crypto/certificate_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('generates a self-signed identity with a stable fingerprint', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final manager = CertificateManager(prefs);

    final identity = await manager.generate(name: 'Test device');
    expect(identity.name, 'Test device');
    expect(identity.fingerprint.length, 64);
    expect(identity.certificatePem, contains('-----BEGIN CERTIFICATE-----'));
    expect(
      CertificateManager.fingerprintOfCertificate(identity.certificatePem),
      identity.fingerprint,
    );

    final loaded = await manager.load();
    expect(loaded?.fingerprint, identity.fingerprint);

    // A SecurityContext must accept the generated key/certificate pair.
    expect(() => identity.securityContext(), returnsNormally);
  });
}
