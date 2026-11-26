import 'package:material_ui/material_ui.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishare/core/theme/wishare_motion.dart';
import 'package:wishare/core/theme/wishare_shape.dart';
import 'package:wishare/core/theme/wishare_theme.dart';
import 'package:wishare/core/theme/wishare_type.dart';

void main() {
  test('baseline typography is the default; emphasized is opt-in', () {
    final theme = WishareTheme.build(
      ColorScheme.fromSeed(seedColor: const Color(WishareTheme.seedArgb)),
      contrast: WiContrast.standard,
      reduceMotion: false,
    );

    // label large baseline = 14sp / 20sp / 0.1sp tracking, Medium.
    expect(theme.textTheme.labelLarge?.fontSize, 14);
    expect(theme.textTheme.labelLarge?.height, 20 / 14);
    expect(theme.textTheme.labelLarge?.letterSpacing, 0.1);
    expect(theme.textTheme.labelLarge?.fontWeight, FontWeight.w500);

    // Emphasized label large = Bold, same size and line height.
    final emphasized = theme.extension<WiEmphasis>()!.text.labelLarge!;
    expect(emphasized.fontWeight, FontWeight.w700);
    expect(emphasized.fontSize, theme.textTheme.labelLarge?.fontSize);
  });

  test('dark theme body text uses onSurface, not surface', () {
    final theme = WishareTheme.build(
      WishareTheme.baseline(Brightness.dark),
      contrast: WiContrast.standard,
      reduceMotion: false,
    );
    expect(theme.textTheme.bodyLarge?.color, theme.colorScheme.onSurface);
    expect(theme.textTheme.bodyLarge?.color, isNot(theme.colorScheme.surface));
  });

  test('all emphasized token sizes and weights match the published scale', () {
    final emphasized = WiType.emphasized(
      WiType.applyTokens(Typography.material2021().black),
    );
    expect(emphasized.headlineMedium?.fontSize, 28);
    expect(emphasized.headlineMedium?.fontWeight, FontWeight.w500);
    expect(emphasized.titleMedium?.fontWeight, FontWeight.w700);
    expect(emphasized.labelSmall?.fontWeight, FontWeight.w700);
    expect(emphasized.bodyLarge?.fontWeight, FontWeight.w500);
  });

  test('spatial springs bounce; effects springs never overshoot', () {
    expect(WiSpring.defaultEffects.damping, 1.0);
    expect(WiSpring.fastEffects.damping, 1.0);
    expect(WiSpring.defaultSpatial.damping, lessThan(1.0));

    double peak(WiSpring spring) {
      final simulation = SpringSimulation(spring.description, 0, 1, 0);
      var max = 0.0;
      for (var ms = 0; ms < 1000; ms += 5) {
        final value = simulation.x(ms / 1000);
        if (value > max) max = value;
      }
      return max;
    }

    expect(peak(WiSpring.defaultSpatial), greaterThan(1.0));
    expect(peak(WiSpring.defaultEffects), lessThanOrEqualTo(1.0));
  });

  test('nested radius follows inner = outer - padding', () {
    expect(WiRadius.inner(WiRadius.extraLarge, 8), 20);
  });
}
