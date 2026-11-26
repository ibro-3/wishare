/// Small, dependency-free helpers for tolerant JSON parsing.
///
/// Persisted preferences and network payloads are untrusted: stale enum names,
/// bad casts and truncated values must degrade to defaults instead of throwing.
T? enumByName<T extends Enum>(Iterable<T> values, Object? name) {
  if (name is! String) return null;
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}

DateTime? dateTime(Object? value) {
  if (value is! String) return null;
  try {
    return DateTime.parse(value);
  } on FormatException {
    return null;
  }
}

int integer(Object? value, int fallback) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

double decimal(Object? value, double fallback) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

String? text(Object? value) => value is String ? value : null;

bool boolean(Object? value, bool fallback) => value is bool ? value : fallback;

List<dynamic>? list(Object? value) =>
    value is List ? List<dynamic>.from(value) : null;

Map<String, dynamic>? object(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : null;
