import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

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
}

/// M3 legacy transition tokens (`transitions.md`): transitions still use the
/// easing/duration system, with Emphasized easing for most transitions.
abstract final class WiTransition {
  /// Emphasized decelerate: enter the screen (suggested 400ms pairing).
  static const Duration enterDuration = Duration(milliseconds: 400);

  /// Emphasized accelerate: exit the screen (suggested 200ms pairing).
  static const Duration exitDuration = Duration(milliseconds: 200);

  /// `short2` — used for the subtle reduced-motion fade.
  static const Duration reducedDuration = Duration(milliseconds: 100);

  /// Flutter mapping for `md.sys.motion.easing.emphasized.decelerate`.
  static const Cubic enterCurve = Cubic(0.05, 0.7, 0.1, 1);

  /// Flutter mapping for `md.sys.motion.easing.emphasized.accelerate`.
  static const Cubic exitCurve = Cubic(0.3, 0, 0.8, 0.15);
}

/// Top-level destination fade.
///
/// From M3: a quick fade with no persistent elements, using emphasized
/// decelerate on enter and emphasized accelerate on exit. M3 also says to
/// fully fade the outgoing content out before the incoming content appears.
///
/// My design decision (not in M3): `CustomTransitionPage` only receives the
/// incoming child, so the outgoing half of the timeline is left uncovered and
/// the incoming child fades in during the second half. This avoids a
/// cross-fade without a custom route implementation.
class WiTopLevelFade extends StatelessWidget {
  const WiTopLevelFade({
    required this.animation,
    required this.child,
    super.key,
  });

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final t = animation.value.clamp(0.0, 1.0);
        final double opacity;
        if (animation.status == AnimationStatus.reverse) {
          final outgoing = ((1 - t) / 0.5).clamp(0.0, 1.0);
          opacity = 1 - WiTransition.exitCurve.transform(outgoing);
        } else {
          final incoming = ((t - 0.5) / 0.5).clamp(0.0, 1.0);
          opacity = WiTransition.enterCurve.transform(incoming);
        }
        return Opacity(opacity: opacity, child: child);
      },
    );
  }
}
