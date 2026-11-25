import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

import 'wishare_shape.dart';
import 'wishare_type.dart';

/// Contrast levels published by M3 (May 2025): standard, medium (min 3:1),
/// high (7:1). Flutter has no contrast-level API, so the mapping below is
/// my design decision: preserve role semantics, move foreground tones further
/// from their surface tones using HCT (the same space Material uses).
enum WiContrast { standard, medium, high }

extension WiContrastLabel on WiContrast {
  String get label => switch (this) {
    WiContrast.standard => 'Standard',
    WiContrast.medium => 'Medium',
    WiContrast.high => 'High',
  };
}

abstract final class WishareTheme {
  /// Baseline-style seed. My design decision: a violet brand seed so the
  /// static fallback is recognisably Wishare before dynamic colour is active.
  static const int seedArgb = 0xFF6750A4;

  static ColorScheme baseline(Brightness brightness) => ColorScheme.fromSeed(
    seedColor: const Color(seedArgb),
    brightness: brightness,
  );

  static ColorScheme applyContrast(ColorScheme scheme, WiContrast level) {
    if (level == WiContrast.standard) return scheme;
    final dark = scheme.brightness == Brightness.dark;
    final foregroundTone = switch (level) {
      WiContrast.medium => dark ? 90 : 15,
      WiContrast.high => dark ? 98 : 8,
      WiContrast.standard => dark ? 90 : 10,
    };
    final mutedTone = switch (level) {
      WiContrast.medium => dark ? 80 : 30,
      WiContrast.high => dark ? 90 : 20,
      WiContrast.standard => dark ? 80 : 30,
    };
    Color stronger(Color source, int tone) {
      final hct = Hct.fromInt(source.toARGB32());
      return Color(
        Hct.from(
          hct.hue.toDouble(),
          hct.chroma.toDouble(),
          tone.toDouble(),
        ).toInt(),
      );
    }

    return scheme.copyWith(
      onSurface: stronger(scheme.onSurface, foregroundTone),
      onSurfaceVariant: stronger(scheme.onSurfaceVariant, mutedTone),
      onPrimary: stronger(scheme.onPrimary, dark ? 10 : 98),
      onPrimaryContainer: stronger(scheme.onPrimaryContainer, dark ? 90 : 10),
      onSecondaryContainer: stronger(
        scheme.onSecondaryContainer,
        dark ? 90 : 10,
      ),
      onTertiaryContainer: stronger(scheme.onTertiaryContainer, dark ? 90 : 10),
      onErrorContainer: stronger(scheme.onErrorContainer, dark ? 90 : 10),
      outline: stronger(scheme.outline, dark ? 80 : 35),
    );
  }

  static ThemeData build(
    ColorScheme colors, {
    required WiContrast contrast,
    required bool reduceMotion,
  }) {
    final scheme = applyContrast(colors, contrast);
    final base = Typography.material2021(
      platform: defaultTargetPlatform,
      colorScheme: scheme,
    );
    final text = WiType.applyTokens(base.black);
    final emphasized = WiType.emphasized(text);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      // Baseline is the default scale; emphasized is opt-in per element.
      textTheme: text,
      scaffoldBackgroundColor: scheme.surface,
      visualDensity: VisualDensity.standard,
      // M3 interactive targets stay 48dp even when the visual button is 40dp.
      materialTapTargetSize: MaterialTapTargetSize.padded,
      splashFactory: InkSparkle.splashFactory,
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          for (final platform in TargetPlatform.values)
            platform: reduceMotion
                ? const NoTransitionBuilder()
                : const ZoomPageTransitionsBuilder(),
        },
      ),
      extensions: [
        WiEmphasis(emphasized),
        WiMotionExtension(reduceMotion: reduceMotion),
        WiContrastExtension(contrast),
      ],
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        // Medium FAB: 80dp container, 28dp icon (Compose FabMedium tokens).
        sizeConstraints: const BoxConstraints.tightFor(width: 80, height: 80),
        iconSize: 28,
        // FabPrimaryContainer elevation level 3; hover level 4.
        elevation: 6,
        hoverElevation: 8,
        // Small extended FAB: 16dp leading space, 8dp icon-label space,
        // label `title medium` (emphasized).
        extendedPadding: const EdgeInsets.symmetric(horizontal: 16),
        extendedIconLabelSpacing: 8,
        extendedTextStyle: emphasized.titleMedium,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.secondaryContainer,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final style = states.contains(WidgetState.selected)
              ? emphasized.labelLarge
              : text.labelLarge;
          return style?.copyWith(
            color: states.contains(WidgetState.selected)
                ? scheme.secondary
                : scheme.onSurfaceVariant,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.secondaryContainer,
        selectedIconTheme: IconThemeData(color: scheme.onSecondaryContainer),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        selectedLabelTextStyle: emphasized.labelMedium?.copyWith(
          color: scheme.secondary,
        ),
        unselectedLabelTextStyle: text.labelMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      // Filled card: container `surface container highest`, elevation 0,
      // 12dp corners (cards guideline + Compose token Card shape).
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerHighest,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.secondaryContainer,
        linearMinHeight: 4,
        stopIndicatorColor: scheme.primary,
        stopIndicatorRadius: 2, // 4dp circle (Compose token StopSize)
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 40),
          shape: const StadiumBorder(),
        ),
      ),
      // Dialog container shape = CornerExtraLarge (28dp), elevation level 3.
      dialogTheme: DialogThemeData(
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WiRadius.extraLarge),
        ),
      ),
      // Bottom sheets: 28dp top corners, container `surface container low`.
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(WiRadius.extraLarge),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: text.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        behavior: SnackBarBehavior.floating,
        // Compose token Snackbar container shape = CornerExtraSmall (4dp).
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        // Compose token OutlinedTextField shape = CornerExtraSmall (4dp).
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: scheme.outline),
        ),
      ),
    );
  }
}

class WiMotionExtension extends ThemeExtension<WiMotionExtension> {
  const WiMotionExtension({required this.reduceMotion});

  final bool reduceMotion;

  @override
  WiMotionExtension copyWith({bool? reduceMotion}) =>
      WiMotionExtension(reduceMotion: reduceMotion ?? this.reduceMotion);

  @override
  WiMotionExtension lerp(WiMotionExtension? other, double t) => this;
}

class WiContrastExtension extends ThemeExtension<WiContrastExtension> {
  const WiContrastExtension(this.level);

  final WiContrast level;

  @override
  WiContrastExtension copyWith({WiContrast? level}) =>
      WiContrastExtension(level ?? this.level);

  @override
  WiContrastExtension lerp(WiContrastExtension? other, double t) => this;
}

class NoTransitionBuilder extends PageTransitionsBuilder {
  const NoTransitionBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}
