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
      // Mirror horizontally only; a 180° rotation would point the icon down
      // as well as backwards (wrong for send arrows and similar glyphs).
      return Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()..scaleByDouble(-1.0, 1.0, 1.0, 1.0),
        child: icon,
      );
    }
    return icon;
  }
}
