import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishare/core/theme/wishare_theme.dart';
import 'package:wishare/core/theme/wishare_type.dart';

void main() {
  for (final entry in [
    ('light', Brightness.light, WiContrast.standard),
    ('dark', Brightness.dark, WiContrast.standard),
    ('high_contrast', Brightness.light, WiContrast.high),
  ]) {
    testWidgets('theme showcase ${entry.$1}', (tester) async {
      // Fixed logical viewport so goldens are stable across hosts.
      tester.view.physicalSize = const Size(400, 620);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final scheme = WishareTheme.baseline(entry.$2);
      await tester.pumpWidget(
        MaterialApp(
          theme: WishareTheme.build(
            scheme,
            contrast: entry.$3,
            reduceMotion: true,
          ),
          home: const _Showcase(),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(_Showcase),
        matchesGoldenFile('goldens/showcase_${entry.$1}.png'),
      );
    });
  }
}

class _Showcase extends StatelessWidget {
  const _Showcase();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final scheme = theme.colorScheme;
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Devices', style: text.headlineMedium),
            const SizedBox(height: 8),
            Text('Nearby devices on this network', style: text.bodyMedium),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: scheme.secondaryContainer,
                  child: const Text('L'),
                ),
                title: Text(
                  'Living room PC',
                  style: context.emphasizedText.titleMedium,
                ),
                subtitle: const Text('192.168.1.20 · Just now'),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton(
                  style: FilledButton.styleFrom(
                    textStyle: context.emphasizedText.labelLarge,
                  ),
                  onPressed: () {},
                  child: const Text('Send'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(onPressed: () {}, child: const Text('Pair')),
              ],
            ),
            const SizedBox(height: 16),
            const LinearProgressIndicator(value: 0.6),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: scheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'New · 3 items',
                style: context.emphasizedText.labelSmall?.copyWith(
                  color: scheme.onTertiaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
