import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wishare/app.dart';
import 'package:wishare/core/models/settings.dart';
import 'package:wishare/core/state/providers.dart';
import 'package:wishare/core/theme/wishare_motion.dart';
import 'package:wishare/core/theme/wishare_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('sub-flows push above the shell and back restores the tab', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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

    // History is now a top-level destination inside the same shell.
    await tester.tap(find.byIcon(Icons.history_outlined));
    await tester.pumpAndSettle();
    expect(find.text('History'), findsWidgets);
    expect(find.byType(NavigationBar), findsOneWidget);

    appRouter.go('/send');
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

  testWidgets('the scanner can open the QR generator for the other device', (
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
        // path_provider is unavailable on the Linux test host.
        overrides: [
          settingsProvider.overrideWith(() => _FixedSettingsController()),
        ],
        child: MaterialApp.router(routerConfig: appRouter, theme: theme),
      ),
    );
    await tester.pumpAndSettle();

    appRouter.go('/scan');
    await tester.pumpAndSettle();
    expect(find.text('Scan pairing code'), findsWidgets);

    await tester.tap(find.byTooltip('Show my code'));
    await tester.pumpAndSettle();
    expect(find.text('Show pairing code'), findsWidgets);
    // The scanner is now underneath the pushed generator page.
    expect(find.byTooltip('Show my code'), findsNothing);
  });

  testWidgets('uses a navigation rail at medium widths', (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() => appRouter.go('/send'));

    final theme = WishareTheme.build(
      WishareTheme.baseline(Brightness.light),
      contrast: WiContrast.standard,
      reduceMotion: true,
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(routerConfig: appRouter, theme: theme),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    await tester.tap(find.byIcon(Icons.history_outlined));
    await tester.pumpAndSettle();
    expect(find.text('History'), findsWidgets);
    expect(find.byType(NavigationRail), findsOneWidget);
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

class _FixedSettingsController extends SettingsController {
  @override
  Future<AppSettings> build() async =>
      AppSettings.initial('/tmp/wishare')
          .copyWith(discoveryEnabled: false, broadcastEnabled: false);
}

class _StoppedAnimation extends AlwaysStoppedAnimation<double> {
  const _StoppedAnimation(super.value, this.statusOverride);

  final AnimationStatus statusOverride;

  @override
  AnimationStatus get status => statusOverride;
}
