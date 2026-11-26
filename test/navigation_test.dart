import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wishare/app.dart';
import 'package:wishare/core/theme/wishare_motion.dart';
import 'package:wishare/core/theme/wishare_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('sub-flows push above the shell and back restores the tab', (
    tester,
  ) async {
    final theme = WishareTheme.build(
      WishareTheme.baseline(Brightness.light),
      contrast: WiContrast.standard,
      reduceMotion: true,
    );
    addTearDown(() => appRouter.go('/send'));
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(routerConfig: appRouter, theme: theme),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);

    // History is a pushed page, so the shell stays mounted underneath.
    await tester.tap(find.byTooltip('Transfer history'));
    await tester.pumpAndSettle();
    expect(find.text('History'), findsWidgets);
    expect(find.byType(NavigationBar, skipOffstage: false), findsOneWidget);

    appRouter.pop();
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);

    // Returning from Settings lands on the tab the user was on.
    appRouter.go('/receive');
    await tester.pumpAndSettle();
    appRouter.push('/settings');
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsWidgets);
    expect(find.byType(NavigationBar, skipOffstage: false), findsOneWidget);

    appRouter.pop();
    await tester.pumpAndSettle();
    expect(find.text('Receive'), findsWidgets);
  });

  testWidgets('top-level fade waits for the outgoing screen', (tester) async {
    Widget build(double value, AnimationStatus status) => Directionality(
      textDirection: TextDirection.ltr,
      child: WiTopLevelFade(
        animation: _StoppedAnimation(value, status),
        child: const SizedBox.expand(),
      ),
    );

    // First half of the forward timeline: incoming is fully hidden.
    await tester.pumpWidget(build(0.25, AnimationStatus.forward));
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 0);

    // End of the forward timeline: incoming is fully visible.
    await tester.pumpWidget(build(1, AnimationStatus.completed));
    expect(
      tester.widget<Opacity>(find.byType(Opacity)).opacity,
      closeTo(1, 0.001),
    );

    // Reverse: the outgoing screen fades out during the first half.
    await tester.pumpWidget(build(0.75, AnimationStatus.reverse));
    final reversing = tester.widget<Opacity>(find.byType(Opacity)).opacity;
    expect(reversing, greaterThan(0));
    expect(reversing, lessThan(1));

    await tester.pumpWidget(build(0.5, AnimationStatus.reverse));
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 0);
  });
}

class _StoppedAnimation extends AlwaysStoppedAnimation<double> {
  const _StoppedAnimation(super.value, this.statusOverride);

  final AnimationStatus statusOverride;

  @override
  AnimationStatus get status => statusOverride;
}
