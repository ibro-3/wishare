import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wishare/app.dart';
import 'package:wishare/core/models/pair_request.dart';
import 'package:wishare/core/models/settings.dart';
import 'package:wishare/core/state/providers.dart';
import 'package:wishare/core/theme/wishare_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the receiver gets an approve/decline pairing prompt', (
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
        overrides: [
          settingsProvider.overrideWith(() => _QuietSettingsController()),
          pairRequestsProvider.overrideWith(() => _PendingPairRequests()),
        ],
        child: MaterialApp.router(routerConfig: appRouter, theme: theme),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pairing request'), findsOneWidget);
    expect(
      find.text('Nearby laptop wants to pair with this device.'),
      findsOneWidget,
    );
    expect(find.textContaining('Certificate AAAA'), findsOneWidget);
    expect(find.text('Approve'), findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);
  });
}

class _QuietSettingsController extends SettingsController {
  @override
  Future<AppSettings> build() async => AppSettings.initial('/tmp/wishare')
      .copyWith(
        autoUpdateCheck: false,
        discoveryEnabled: false,
        broadcastEnabled: false,
      );
}

class _PendingPairRequests extends PairRequestsController {
  @override
  Future<List<PairRequest>> build() async => [
    PairRequest(
      id: 'sender-1',
      name: 'Nearby laptop',
      fingerprint: 'A' * 64,
      createdAt: DateTime(2026),
    ),
  ];
}
