/// M3 corner radius scale — 10 steps (from `tokens.md`).
///
/// Bold steps added by the M3 Expressive update: large increased, extra large
/// increased, extra extra large. Values are exact; do not round.
abstract final class WiRadius {
  static const double none = 0;
  static const double extraSmall = 4;
  static const double small = 8;
  static const double medium = 12;
  static const double large = 16;
  static const double largeIncreased = 20;
  static const double extraLarge = 28;
  static const double extraLargeIncreased = 32;
  static const double extraExtraLarge = 48;
  static const double full = 999;

  /// M3 nesting rule: inner radius = outer radius - padding. Never reuse the
  /// parent's radius for a nested child.
  static double inner(double outer, double padding) =>
      (outer - padding).clamp(0, full);
}
