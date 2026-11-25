import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// Mirrors directional icons in RTL layouts.
///
/// From M3: send buttons and directional UI icons are mirrored in RTL;
/// non-directional icons such as checkmarks must not be mirrored.
class WiDirectionalIcon extends StatelessWidget {
  const WiDirectionalIcon(
    this.icon, {
    this.mirrored = true,
    this.size,
    this.color,
    super.key,
  });

  final IconData icon;
  final bool mirrored;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(this.icon, size: size, color: color);
    if (mirrored && Directionality.of(context) == TextDirection.rtl) {
      return Transform.rotate(angle: math.pi, child: icon);
    }
    return icon;
  }
}
