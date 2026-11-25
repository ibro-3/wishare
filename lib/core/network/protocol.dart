import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// LAN protocol constants and helpers. All values here are my design decision;
/// M3 does not specify networking.
abstract final class WiProtocol {
  static const int port = 45821;
  static const String scheme = 'https';
  static const String serviceType = '_wishare._tcp.local';
  static const String version = '0.1';

  static const String headerDeviceId = 'X-Wishare-Id';
  static const String headerToken = 'X-Wishare-Token';
  static const String headerFingerprint = 'X-Wishare-Fingerprint';

  static const int chunkSize = 256 * 1024;
  static const Duration requestTimeout = Duration(seconds: 15);

  static const String qrScheme = 'wishare://pair';
}

class PairingPayload {
  const PairingPayload({
    required this.host,
    required this.port,
    required this.name,
    required this.fingerprint,
    required this.pin,
  });

  final String host;
  final int port;
  final String name;
  final String fingerprint;
  final String pin;

  String toQrUri() => Uri(
    scheme: 'wishare',
    host: 'pair',
    queryParameters: {
      'host': host,
      'port': '$port',
      'name': name,
      'fp': fingerprint,
      'pin': pin,
    },
  ).toString();

  factory PairingPayload.fromUri(Uri uri) {
    if (uri.scheme != 'wishare' || uri.host != 'pair') {
      throw const FormatException('Not a Wishare pairing code');
    }
    final q = uri.queryParameters;
    return PairingPayload(
      host: q['host'] ?? '',
      port: int.tryParse(q['port'] ?? '') ?? WiProtocol.port,
      name: q['name'] ?? 'Wishare device',
      fingerprint: q['fp'] ?? '',
      pin: q['pin'] ?? '',
    );
  }
}

/// Generate a 6-digit PIN with a secure source (my design decision).
String newPin() {
  final random = Random.secure();
  return List<int>.generate(6, (_) => random.nextInt(10)).join();
}

/// Verify / normalise a certificate fingerprint from a QR code or /info reply.
String normaliseFingerprint(String value) =>
    value.replaceAll(RegExp(r'[\s:-]'), '').toUpperCase();

/// Byte-range safety for folder transfers (my design decision).
///
/// Rejects absolute paths, drive prefixes, `..` segments, and NUL bytes before
/// any file is created on the receiver.
class SafePath {
  SafePath._();

  static String sanitise(String relativePath) {
    if (relativePath.isEmpty || relativePath.contains('\u0000')) {
      throw const FormatException('Unsafe path');
    }
    final normalised = relativePath.replaceAll(r'\', '/');
    if (normalised.startsWith('/') ||
        RegExp(r'^[A-Za-z]:/').hasMatch(normalised)) {
      throw const FormatException('Absolute paths are not allowed');
    }
    final segments = normalised.split('/');
    if (segments.any((s) => s == '..')) {
      throw const FormatException('Parent traversal is not allowed');
    }
    return segments.where((s) => s.isNotEmpty && s != '.').join('/');
  }
}

String encodePath(String relativePath) =>
    base64Url.encode(utf8.encode(SafePath.sanitise(relativePath)));

String decodePath(String encoded) => utf8.decode(base64Url.decode(encoded));

String checksumBytes(List<int> bytes) => sha256.convert(bytes).toString();

Uint8List jsonBytes(Map<String, dynamic> json) =>
    Uint8List.fromList(utf8.encode(jsonEncode(json)));
