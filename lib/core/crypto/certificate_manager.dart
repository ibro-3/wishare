import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/pointycastle.dart';
import 'package:pointycastle/random/fortuna_random.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A device's self-signed identity.
///
/// My design decision: P-256 ECDSA, self-signed X.509, SHA-256 fingerprint.
/// The fingerprint is the TOFU identity pinned by peers after scanning a QR.
class DeviceIdentity {
  const DeviceIdentity({
    required this.id,
    required this.name,
    required this.privateKeyPem,
    required this.certificatePem,
    required this.fingerprint,
  });

  final String id;
  final String name;
  final String privateKeyPem;
  final String certificatePem;
  final String fingerprint;

  /// Short, human-comparable form of the fingerprint: `4F2A … C91D`.
  String get shortFingerprint {
    if (fingerprint.length < 8) return fingerprint;
    return '${fingerprint.substring(0, 4)} … ${fingerprint.substring(fingerprint.length - 4)}';
  }

  SecurityContext securityContext() {
    final context = SecurityContext(withTrustedRoots: false)
      ..useCertificateChainBytes(utf8.encode(certificatePem))
      ..usePrivateKeyBytes(utf8.encode(privateKeyPem));
    return context;
  }
}

class CertificateManager {
  const CertificateManager(this._prefs);

  final SharedPreferences _prefs;

  static const _keyId = 'identity.id';
  static const _keyName = 'identity.name';
  static const _keyCert = 'identity.certificate';
  static const _keyKey = 'identity.privateKey';

  Future<DeviceIdentity?> load() async {
    final cert = _prefs.getString(_keyCert);
    final key = _prefs.getString(_keyKey);
    final id = _prefs.getString(_keyId);
    if (cert == null || key == null || id == null) return null;
    final der = _decodePem(cert, 'CERTIFICATE');
    return DeviceIdentity(
      id: id,
      name: _prefs.getString(_keyName) ?? 'Wishare device',
      privateKeyPem: key,
      certificatePem: cert,
      fingerprint: sha256.convert(der).toString().toUpperCase(),
    );
  }

  /// Generates and persists a fresh identity. Existing identities are never
  /// silently replaced: callers must explicitly rotate.
  Future<DeviceIdentity> generate({String? name}) async {
    final identity = await CertificateManager.create(name: name);
    await _persist(identity);
    return identity;
  }

  /// Pure generation, usable without platform preferences (e.g. in tools).
  static Future<DeviceIdentity> create({String? name}) async {
    final domain = ECDomainParameters('prime256v1');
    final rng = FortunaRandom()
      ..seed(
        KeyParameter(
          Uint8List.fromList(
            List<int>.generate(32, (_) => Random.secure().nextInt(256)),
          ),
        ),
      );
    final generator = KeyGenerator('EC')
      ..init(
        ParametersWithRandom<ECKeyGeneratorParameters>(
          ECKeyGeneratorParameters(domain),
          rng,
        ),
      );
    final pair = generator.generateKeyPair();
    final private = pair.privateKey as ECPrivateKey;
    final public = pair.publicKey as ECPublicKey;

    final now = DateTime.now().toUtc();
    final serial = BigInt.from(DateTime.now().microsecondsSinceEpoch);
    final subject = _name(name ?? 'Wishare device');

    final spki = ASN1Sequence(
      elements: [
        ASN1Sequence(
          elements: [
            ASN1ObjectIdentifier.fromIdentifierString('1.2.840.10045.2.1'),
            ASN1ObjectIdentifier.fromIdentifierString('1.2.840.10045.3.1.7'),
          ],
        ),
        ASN1BitString(stringValues: public.Q!.getEncoded(false)),
      ],
    );
    final sigAlg = ASN1Sequence(
      elements: [
        ASN1ObjectIdentifier.fromIdentifierString('1.2.840.10045.4.3.2'),
      ],
    );

    // X.509 v3 explicit version tag [0] { INTEGER 2 }.
    final version = Uint8List.fromList([0xA0, 0x03, 0x02, 0x01, 0x02]);
    final validity = ASN1Sequence(
      elements: [
        ASN1UtcTime(now),
        ASN1UtcTime(now.add(const Duration(days: 3650))),
      ],
    );
    final tbs = ASN1Sequence(
      elements: [
        _RawAsn1(version),
        ASN1Integer(serial),
        sigAlg,
        subject,
        validity,
        subject,
        spki,
      ],
    );
    final tbsBytes = tbs.encode();

    final signer = Signer('SHA-256/ECDSA')
      ..init(
        true,
        ParametersWithRandom<PrivateKeyParameter<ECPrivateKey>>(
          PrivateKeyParameter<ECPrivateKey>(private),
          rng,
        ),
      );
    final signature = signer.generateSignature(tbsBytes) as ECSignature;
    final signatureBits = ASN1BitString(
      stringValues: ASN1Sequence(
        elements: [ASN1Integer(signature.r), ASN1Integer(signature.s)],
      ).encode(),
    );
    final certBytes = ASN1Sequence(elements: [tbs, sigAlg, signatureBits])
        .encode();

    final certificatePem = _pem('CERTIFICATE', certBytes);
    final privateKeyPem = _pem('PRIVATE KEY', _pkcs8(private, domain));
    final id = const Uuid4().newId();
    final identity = DeviceIdentity(
      id: id,
      name: name ?? 'Wishare device',
      privateKeyPem: privateKeyPem,
      certificatePem: certificatePem,
      fingerprint: sha256.convert(certBytes).toString().toUpperCase(),
    );

    return identity;
  }

  Future<void> _persist(DeviceIdentity identity) async {
    await _prefs.setString(_keyId, identity.id);
    await _prefs.setString(_keyName, identity.name);
    await _prefs.setString(_keyCert, identity.certificatePem);
    await _prefs.setString(_keyKey, identity.privateKeyPem);
  }

  Future<void> rename(String name) => _prefs.setString(_keyName, name);

  static String fingerprintOfCertificate(String pem) {
    final der = _decodePem(pem, 'CERTIFICATE');
    return sha256.convert(der).toString().toUpperCase();
  }

  static ASN1Sequence _name(String commonName) => ASN1Sequence(
    elements: [
      ASN1Set(
        elements: [
          ASN1Sequence(
            elements: [
              ASN1ObjectIdentifier.fromIdentifierString('2.5.4.3'),
              ASN1UTF8String(utf8StringValue: commonName),
            ],
          ),
        ],
      ),
    ],
  );

  static Uint8List _pkcs8(ECPrivateKey key, ECDomainParameters domain) {
    final ecPrivateKey = ASN1Sequence(
      elements: [
        ASN1Integer(BigInt.one),
        ASN1OctetString(octets: _fixed32(key.d!)),
        // RFC 5915: publicKey is an explicit [0] BIT STRING, not a plain one.
        _RawAsn1(
          _contextOneBitString((key.parameters!.G * key.d!)!.getEncoded(false)),
        ),
      ],
    );
    return ASN1Sequence(
      elements: [
        ASN1Integer(BigInt.zero),
        ASN1Sequence(
          elements: [
            ASN1ObjectIdentifier.fromIdentifierString('1.2.840.10045.2.1'),
            ASN1ObjectIdentifier.fromIdentifierString('1.2.840.10045.3.1.7'),
          ],
        ),
        ASN1OctetString(octets: ecPrivateKey.encode()),
      ],
    ).encode();
  }

  static Uint8List _fixed32(BigInt value) {
    final bytes = Uint8List(32);
    var v = value;
    for (var i = 31; i >= 0; i--) {
      bytes[i] = (v & BigInt.from(0xFF)).toInt();
      v >>= 8;
    }
    return bytes;
  }

  static String _pem(String label, List<int> bytes) {
    final body = base64.encode(bytes);
    final lines = <String>[];
    for (var i = 0; i < body.length; i += 64) {
      lines.add(body.substring(i, min(i + 64, body.length)));
    }
    return '-----BEGIN $label-----\n${lines.join('\n')}\n-----END $label-----\n';
  }

  static Uint8List _decodePem(String pem, String label) {
    final begin = '-----BEGIN $label-----';
    final end = '-----END $label-----';
    final start = pem.indexOf(begin);
    final stop = pem.indexOf(end);
    if (start < 0 || stop < 0) throw FormatException('Invalid $label PEM');
    final body = pem
        .substring(start + begin.length, stop)
        .replaceAll(RegExp(r'\s'), '');
    return base64.decode(body);
  }
}

/// RFC 5915 encodes the optional public key as `[1] IMPLICIT BIT STRING`.
Uint8List _contextOneBitString(List<int> bytes) {
  final bitString = ASN1BitString(stringValues: bytes).encode();
  // Strip the universal BIT STRING tag+length, keep the unused-bits byte and
  // point, then re-tag as context-specific [1].
  return Uint8List.fromList([0xA1, bitString.length, ...bitString]);
}

/// Minimal DER object for injecting a pre-encoded explicit context tag.
class _RawAsn1 extends ASN1Object {
  _RawAsn1(this.bytes);

  final Uint8List bytes;

  @override
  Uint8List encode({
    ASN1EncodingRule encodingRule = ASN1EncodingRule.ENCODING_DER,
  }) => bytes;
}

/// Tiny UUID v4 generator; avoids an extra dependency.
class Uuid4 {
  const Uuid4();

  String newId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0F) | 0x40;
    bytes[8] = (bytes[8] & 0x3F) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
