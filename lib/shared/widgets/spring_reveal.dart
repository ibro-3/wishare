import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../core/theme/wishare_motion.dart';

/// Expressive entrance for hero moments.
///
/// From M3: geometry uses a **spatial** spring (bounces); opacity uses an
/// **effects** spring (damping 1.0, never overshoots). Flutter has no motion
/// physics library, so the published spring tokens are applied through
/// [SpringSimulation] — my design decision (see `platforms.md`).
///
/// M3 publishes no stagger or choreography values: this widget animates a
/// single child with no stagger.
class WiSpringReveal extends StatefulWidget {
  const WiSpringReveal({
    required this.child,
    this.enabled = true,
    this.spatial = WiSpring.defaultSpatial,
    this.effects = WiSpring.defaultEffects,
    this.onEnd,
    super.key,
  });

  final Widget child;
  final bool enabled;
  final WiSpring spatial;
  final WiSpring effects;
  final VoidCallback? onEnd;

  @override
  State<WiSpringReveal> createState() => _WiSpringRevealState();
}

class _WiSpringRevealState extends State<WiSpringReveal>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late final SpringSimulation _spatial;
  late final SpringSimulation _effects;
  Duration? _startedAt;
  double _scale = 1;
  double _opacity = 1;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _spatial = SpringSimulation(widget.spatial.description, 0.88, 1, 0);
    _effects = SpringSimulation(widget.effects.description, 0, 1, 0);
    _scale = widget.enabled ? 0.88 : 1;
    _opacity = widget.enabled ? 0 : 1;
    _ticker = createTicker(_tick);
    if (widget.enabled) _ticker.start();
  }

  @override
  void didUpdateWidget(covariant WiSpringReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) {
      _startedAt = null;
      _finished = false;
      if (widget.enabled) {
        _spatial = SpringSimulation(widget.spatial.description, 0.88, 1, 0);
        _effects = SpringSimulation(widget.effects.description, 0, 1, 0);
        _scale = 0.88;
        _opacity = 0;
        _ticker.start();
      } else {
        _ticker.stop();
        _scale = 1;
        _opacity = 1;
      }
    }
  }

  void _tick(Duration elapsed) {
    _startedAt ??= elapsed;
    final t = (elapsed - _startedAt!).inMicroseconds / 1_000_000;
    setState(() {
      _scale = _spatial.x(t);
      // Effects springs never overshoot; clamp guards numerical drift.
      _opacity = _effects.x(t).clamp(0.0, 1.0);
    });
    if (_spatial.isDone(t) && _effects.isDone(t) && !_finished) {
      _finished = true;
      _ticker.stop();
      widget.onEnd?.call();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: _opacity,
    child: Transform.scale(
      scale: _scale,
      alignment: Alignment.center,
      child: widget.child,
    ),
  );
}
