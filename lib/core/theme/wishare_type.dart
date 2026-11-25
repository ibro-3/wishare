import 'package:material_ui/material_ui.dart';

/// M3 type scale values (from `tokens.md`).
///
/// Flutter provides `Typography.material2021` but not the emphasized set.
/// Emphasized styles below are built from the published token values — my
/// design decision, to be replaced by a library implementation if Flutter
/// ships one. Same size/line height; only weight and tracking change.
/// Opt-in emphasized styles, supplied by the theme as an extension.
///
/// M3: baseline and emphasized are used together — emphasized marks the
/// exception (selection, actions, headlines, badges), never the default.
class WiEmphasis extends ThemeExtension<WiEmphasis> {
  const WiEmphasis(this.text);

  final TextTheme text;

  @override
  WiEmphasis copyWith({TextTheme? text}) => WiEmphasis(text ?? this.text);

  @override
  WiEmphasis lerp(WiEmphasis? other, double t) => this;
}

extension WiTypeContext on BuildContext {
  TextTheme get emphasizedText =>
      Theme.of(this).extension<WiEmphasis>()?.text ??
      WiType.emphasized(Theme.of(this).textTheme);
}

abstract final class WiType {
  static TextTheme emphasized(TextTheme base) {
    TextStyle em(TextStyle? style, FontWeight weight, double tracking) =>
        (style ?? const TextStyle()).copyWith(
          fontWeight: weight,
          letterSpacing: tracking,
        );

    return base.copyWith(
      displayLarge: em(base.displayLarge, FontWeight.w500, 0),
      displayMedium: em(base.displayMedium, FontWeight.w500, 0),
      displaySmall: em(base.displaySmall, FontWeight.w500, 0),
      headlineLarge: em(base.headlineLarge, FontWeight.w500, 0),
      headlineMedium: em(base.headlineMedium, FontWeight.w500, 0),
      headlineSmall: em(base.headlineSmall, FontWeight.w500, 0),
      titleLarge: em(base.titleLarge, FontWeight.w500, 0),
      titleMedium: em(base.titleMedium, FontWeight.w700, 0.15),
      titleSmall: em(base.titleSmall, FontWeight.w700, 0.1),
      bodyLarge: em(base.bodyLarge, FontWeight.w500, 0.15),
      bodyMedium: em(base.bodyMedium, FontWeight.w500, 0.25),
      bodySmall: em(base.bodySmall, FontWeight.w500, 0.4),
      labelLarge: em(base.labelLarge, FontWeight.w700, 0.1),
      labelMedium: em(base.labelMedium, FontWeight.w700, 0.5),
      labelSmall: em(base.labelSmall, FontWeight.w700, 0.5),
    );
  }

  /// Exact baseline token sizes, used by golden tests and documentation.
  /// Apply the exact published M3 values to a Flutter text theme.
  ///
  /// Flutter's `Typography.material2021` may leave sizes to platform defaults;
  /// the token table is the authoritative source, so copy the values onto it.
  static TextTheme applyTokens(TextTheme base) {
    TextStyle apply(TextStyle? style, String key, FontWeight weight) {
      final token = tokens[key]!;
      return (style ?? const TextStyle()).copyWith(
        fontSize: token.size,
        height: token.height / token.size,
        letterSpacing: token.tracking,
        fontWeight: weight,
      );
    }

    return base.copyWith(
      displayLarge: apply(base.displayLarge, 'display-large', FontWeight.w400),
      displayMedium: apply(
        base.displayMedium,
        'display-medium',
        FontWeight.w400,
      ),
      displaySmall: apply(base.displaySmall, 'display-small', FontWeight.w400),
      headlineLarge: apply(
        base.headlineLarge,
        'headline-large',
        FontWeight.w400,
      ),
      headlineMedium: apply(
        base.headlineMedium,
        'headline-medium',
        FontWeight.w400,
      ),
      headlineSmall: apply(
        base.headlineSmall,
        'headline-small',
        FontWeight.w400,
      ),
      titleLarge: apply(base.titleLarge, 'title-large', FontWeight.w400),
      titleMedium: apply(base.titleMedium, 'title-medium', FontWeight.w500),
      titleSmall: apply(base.titleSmall, 'title-small', FontWeight.w500),
      bodyLarge: apply(base.bodyLarge, 'body-large', FontWeight.w400),
      bodyMedium: apply(base.bodyMedium, 'body-medium', FontWeight.w400),
      bodySmall: apply(base.bodySmall, 'body-small', FontWeight.w400),
      labelLarge: apply(base.labelLarge, 'label-large', FontWeight.w500),
      labelMedium: apply(base.labelMedium, 'label-medium', FontWeight.w500),
      labelSmall: apply(base.labelSmall, 'label-small', FontWeight.w500),
    );
  }

  static const Map<String, ({double size, double height, double tracking})>
  tokens = {
    'display-large': (size: 57, height: 64, tracking: -0.2),
    'display-medium': (size: 45, height: 52, tracking: 0),
    'display-small': (size: 36, height: 44, tracking: 0),
    'headline-large': (size: 32, height: 40, tracking: 0),
    'headline-medium': (size: 28, height: 36, tracking: 0),
    'headline-small': (size: 24, height: 32, tracking: 0),
    'title-large': (size: 22, height: 28, tracking: 0),
    'title-medium': (size: 16, height: 24, tracking: 0.2),
    'title-small': (size: 14, height: 20, tracking: 0.1),
    'body-large': (size: 16, height: 24, tracking: 0.5),
    'body-medium': (size: 14, height: 20, tracking: 0.2),
    'body-small': (size: 12, height: 16, tracking: 0.4),
    'label-large': (size: 14, height: 20, tracking: 0.1),
    'label-medium': (size: 12, height: 16, tracking: 0.5),
    'label-small': (size: 11, height: 16, tracking: 0.5),
  };
}
