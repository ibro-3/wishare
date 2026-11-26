import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/wishare_motion.dart';

/// M3 Expressive loading indicator for short (200ms–5s) indeterminate waits.
///
/// From M3: a looping morph sequence of seven shapes, 48dp container / 38dp
/// active indicator, primary colour (on-primary-container when contained),
/// shape morph driven by the expressive scheme, and no morphing under reduced
/// motion. Flutter has no `MaterialShapes` library, so the seven silhouettes
/// below are **my design decision**: superellipse parameter sets approximating
/// circle, square, diamond, clover, burst, pill and flower. They are decorative
/// graphics only — never placed on text-heavy containers.
class WiLoadingIndicator extends StatefulWidget {
  const WiLoadingIndicator({
    this.contained = false,
    this.reduceMotion = false,
    this.size = 48,
    super.key,
  });

  final bool contained;
  final bool reduceMotion;
  final double size;

  @override
  State<WiLoadingIndicator> createState() => _WiLoadingIndicatorState();
}

class _WiLoadingIndicatorState extends State<WiLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  int _index = 0;
  double _t = 0;
  Duration? _segmentStart;
  late SpringSimulation _simulation;

  static const _shapes = <_Shape>[
    _Shape(exponent: 2, lobes: 0, amplitude: 0, rotation: 0), // circle
    _Shape(exponent: 6, lobes: 0, amplitude: 0, rotation: 0), // rounded square
    _Shape(
      exponent: 2,
      lobes: 0,
      amplitude: 0,
      rotation: math.pi / 4,
    ), // diamond
    _Shape(exponent: 2, lobes: 4, amplitude: 0.18, rotation: 0), // clover
    _Shape(exponent: 2, lobes: 8, amplitude: 0.14, rotation: 0), // burst
    _Shape(
      exponent: 2,
      lobes: 0,
      amplitude: 0,
      rotation: 0,
      scaleY: 0.6,
    ), // pill
    _Shape(exponent: 3, lobes: 5, amplitude: 0.12, rotation: 0), // flower
  ];

  @override
  void initState() {
    super.initState();
    _simulation = _makeSimulation();
    _ticker = createTicker(_tick);
    if (!widget.reduceMotion) _ticker.start();
  }

  @override
  void didUpdateWidget(covariant WiLoadingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reduceMotion != widget.reduceMotion) {
      _index = 0;
      _t = 0;
      _segmentStart = null;
      _simulation = _makeSimulation();
      if (widget.reduceMotion) {
        _ticker.stop();
      } else {
        _ticker.start();
      }
    }
  }

  SpringSimulation _makeSimulation() =>
      SpringSimulation(WiSpring.defaultSpatial.description, 0, 1, 0);

  void _tick(Duration elapsed) {
    _segmentStart ??= elapsed;
    final seconds = (elapsed - _segmentStart!).inMicroseconds / 1_000_000;
    final value = _simulation.x(seconds);
    setState(() => _t = value.clamp(0.0, 1.0));
    if (_simulation.isDone(seconds)) {
      _index = (_index + 1) % _shapes.length;
      _segmentStart = elapsed;
      _simulation = _makeSimulation();
      _t = 0;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = widget.contained ? scheme.onPrimaryContainer : scheme.primary;
    final active = _Shape.lerp(
      _shapes[_index],
      _shapes[(_index + 1) % _shapes.length],
      widget.reduceMotion ? 0 : _t,
    );
    // Active indicator is 38dp inside a 48dp container (M3 measurements).
    final activeSize = widget.size * (38 / 48);
    final indicator = SizedBox(
      width: activeSize,
      height: activeSize,
      child: CustomPaint(
        painter: _ShapePainter(shape: active, color: color),
      ),
    );

    return Semantics(
      label: 'Loading',
      child: Center(
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: widget.contained
              ? DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Center(child: indicator),
                )
              : indicator,
        ),
      ),
    );
  }
}

class _Shape {
  const _Shape({
    required this.exponent,
    required this.lobes,
    required this.amplitude,
    required this.rotation,
    this.scaleY = 1,
  });

  final double exponent;
  final double lobes;
  final double amplitude;
  final double rotation;
  final double scaleY;

  static _Shape lerp(_Shape a, _Shape b, double t) => _Shape(
    exponent: a.exponent + (b.exponent - a.exponent) * t,
    lobes: a.lobes + (b.lobes - a.lobes) * t,
    amplitude: a.amplitude + (b.amplitude - a.amplitude) * t,
    rotation: a.rotation + (b.rotation - a.rotation) * t,
    scaleY: a.scaleY + (b.scaleY - a.scaleY) * t,
  );
}

class _ShapePainter extends CustomPainter {
  const _ShapePainter({required this.shape, required this.color});

  final _Shape shape;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    const samples = 96;
    final path = Path();
    for (var i = 0; i <= samples; i++) {
      final theta = 2 * math.pi * i / samples;
      final c = math.cos(theta);
      final s = math.sin(theta);
      final power = 2 / shape.exponent;
      final x = _signedPower(c, power) * radius;
      final y = _signedPower(s, power) * radius * shape.scaleY;
      final modulation = 1 + shape.amplitude * math.cos(shape.lobes * theta);
      final rx = x * modulation;
      final ry = y * modulation;
      final rotated = Offset(
        rx * math.cos(shape.rotation) - ry * math.sin(shape.rotation),
        rx * math.sin(shape.rotation) + ry * math.cos(shape.rotation),
      );
      final point = center + rotated;
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    final paint = Paint()..color = color;
    paint.style = PaintingStyle.fill;
    canvas.drawPath(path, paint);
  }

  double _signedPower(double value, double power) =>
      value.sign * math.pow(value.abs(), power).toDouble();

  @override
  bool shouldRepaint(covariant _ShapePainter oldDelegate) =>
      oldDelegate.shape != shape || oldDelegate.color != color;
}
