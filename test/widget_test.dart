import 'package:flutter_test/flutter_test.dart';
import 'package:wishare/core/theme/wishare_shape.dart';

void main() {
  test('M3 nested radius follows inner = outer - padding', () {
    expect(WiRadius.inner(WiRadius.extraExtraLarge, 14), 34);
  });

  test('corner radius scale has the published steps', () {
    expect(
      const [
        WiRadius.none,
        WiRadius.extraSmall,
        WiRadius.small,
        WiRadius.medium,
        WiRadius.large,
        WiRadius.largeIncreased,
        WiRadius.extraLarge,
        WiRadius.extraLargeIncreased,
        WiRadius.extraExtraLarge,
      ],
      [0, 4, 8, 12, 16, 20, 28, 32, 48],
    );
  });
}
