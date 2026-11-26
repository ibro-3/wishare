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

    final host = q['host']?.trim() ?? '';
    if (host.isEmpty) {
      throw const FormatException('Pairing code has an empty host');
    }

    final port = int.tryParse(q['port'] ?? '') ?? WiProtocol.port;
    if (port < 1 || port > 65535) {
      throw FormatException('Pairing code has an invalid port: $port');
    }

    // QR codes may carry abbreviated (but still well-formed) fingerprints;
    // full 64-hex validation is reserved for TOFU pinning.
    final fingerprint = normaliseFingerprint(q['fp'] ?? '');
    if (!RegExp(r'^[0-9A-F]{8,64}$').hasMatch(fingerprint)) {
      throw const FormatException(
        'Pairing code has an invalid certificate fingerprint',
      );
    }

    final pin = q['pin'] ?? '';
    if (!RegExp(r'^\d{4,12}$').hasMatch(pin)) {
      throw const FormatException('Pairing code PIN must be 4 to 12 digits');
    }

    return PairingPayload(
      host: host,
      port: port,
      name: q['name'] ?? 'Wishare device',
      fingerprint: fingerprint,
      pin: pin,
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

/// True when [value] looks like a SHA-256 fingerprint we can safely pin.
bool isValidFingerprint(String value) =>
    RegExp(r'^[0-9A-F]{64}$').hasMatch(normaliseFingerprint(value));

/// Human-readable abbreviation that never throws on short or malformed input.
String abbreviateFingerprint(String value, {int edge = 8}) {
  final normalised = normaliseFingerprint(value);
  if (normalised.isEmpty) return '—';
  final safeEdge = edge < 1 ? 8 : edge;
  if (normalised.length <= safeEdge * 2) return normalised;
  return '${normalised.substring(0, safeEdge)}…'
      '${normalised.substring(normalised.length - safeEdge)}';
}

final RegExp _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// True when [id] is safe to use as a single filesystem path component and as
/// a transfer map key. Canonical UUIDs are preferred; conservative legacy
/// tokens remain accepted for older clients. Traversal, separators, whitespace
/// and NUL bytes are always rejected.
bool isValidTransferId(String id) {
  if (id.isEmpty || id.length > 64) return false;
  if (_uuidPattern.hasMatch(id)) return true;
  return RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]*$').hasMatch(id);
}

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
