/// App version, shared by the Settings footer and the update checker.
///
/// My design decision (not in M3): a single constant in Dart rather than a
/// runtime package-info plugin. A test asserts it matches `pubspec.yaml`, so
/// the two cannot silently drift.
abstract final class WiVersion {
  static const String current = '0.4.1';

  /// A semantic version with the optional leading `v` and build metadata
  /// removed. Prerelease suffixes are kept only as text: releases/latest
  /// excludes prereleases upstream, but a hostile payload must not crash us.
  static ({int major, int minor, int patch})? parse(Object? value) {
    if (value is! String) return null;
    var text = value.trim();
    if (text.isEmpty) return null;
    if (text.startsWith('v') || text.startsWith('V')) {
      text = text.substring(1);
    }
    final plus = text.indexOf('+');
    if (plus >= 0) text = text.substring(0, plus);
    // Ignore a prerelease suffix such as `-rc.1`; releases/latest is stable.
    final dash = text.indexOf('-');
    if (dash >= 0) text = text.substring(0, dash);
    final parts = text.split('.');
    if (parts.isEmpty || parts.length > 3) return null;
    final numbers = <int>[];
    for (final part in parts) {
      final parsed = int.tryParse(part);
      if (parsed == null || parsed < 0) return null;
      numbers.add(parsed);
    }
    while (numbers.length < 3) {
      numbers.add(0);
    }
    return (major: numbers[0], minor: numbers[1], patch: numbers[2]);
  }

  /// Positive when [candidate] is newer than [baseline]. Invalid versions
  /// never win an update check.
  static int compare(String candidate, String baseline) {
    final a = parse(candidate);
    final b = parse(baseline);
    if (a == null || b == null) return 0;
    if (a.major != b.major) return a.major > b.major ? 1 : -1;
    if (a.minor != b.minor) return a.minor > b.minor ? 1 : -1;
    if (a.patch != b.patch) return a.patch > b.patch ? 1 : -1;
    return 0;
  }

  static bool isNewer(String candidate, String baseline) =>
      compare(candidate, baseline) > 0;
}
