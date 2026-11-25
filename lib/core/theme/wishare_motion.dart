import 'package:flutter/physics.dart';

/// M3 Expressive spring tokens (from `tokens.md`).
///
/// Flutter has no motion physics library, so these values are mapped to
/// Flutter's [SpringSimulation] — my design decision, not M3 guidance.
/// Geometry uses spatial springs (bounce); colour/opacity uses effects springs
/// (damping 1.0 — never overshoots) in both schemes.
enum WiSpring {
  defaultSpatial(0.8, 380),
  fastSpatial(0.6, 800),
  slowSpatial(0.8, 200),
  defaultEffects(1.0, 1600),
  fastEffects(1.0, 3800),
  slowEffects(1.0, 800);

  const WiSpring(this.damping, this.stiffness);

  final double damping;
  final double stiffness;

  SpringDescription get description => SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: stiffness,
    ratio: damping,
  );

  /// Advance an animation value from [from] towards [to] over [elapsed].
  double evaluate({
    required double from,
    required double to,
    required double velocity,
    required Duration elapsed,
  }) {
    final simulation = SpringSimulation(description, from, to, velocity);
    return simulation.x(elapsed.inMilliseconds / 1000);
  }
}
