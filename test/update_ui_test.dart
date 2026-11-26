import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wishare/core/models/settings.dart';
import 'package:wishare/core/state/providers.dart';
import 'package:wishare/core/state/update_provider.dart';
import 'package:wishare/core/update/update_service.dart';
import 'package:wishare/features/settings/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // path_provider has no implementation on the Linux test host, so provide
  // settings directly instead of going through AppStore.
  final settingsOverride = settingsProvider.overrideWith(
    () => _FakeSettingsController(),
  );

  testWidgets('manual check shows release notes when an update exists', (
    tester,
  ) async {
    final service = _FakeUpdateService(
      const UpdateInfo(
        version: '0.4.0',
        releaseNotes: 'A faster transfer engine',
        releaseUrl: 'https://github.com/ibro-3/wishare/releases',
        asset: UpdateAsset(
          name: 'wishare-0.4.0-linux-x64.zip',
          url: 'https://example.test/linux.zip',
          size: 1,
        ),
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsOverride,
          updateServiceProvider.overrideWithValue(service),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Software update'), findsOneWidget);
    expect(find.text('Check on startup'), findsOneWidget);
    await tester.tap(find.text('Check now'));
    await tester.pumpAndSettle();

    expect(find.text('Update available · 0.4.0'), findsOneWidget);
    expect(find.text('A faster transfer engine'), findsOneWidget);
    expect(find.text('Later'), findsOneWidget);
    expect(find.text('Download'), findsWidgets);
    expect(service.calls, 1);
  });

  testWidgets('manual check reports when already up to date', (tester) async {
    final service = _FakeUpdateService(null);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsOverride,
          updateServiceProvider.overrideWithValue(service),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Check now'));
    await tester.pumpAndSettle();

    expect(find.text('You’re on the latest version'), findsOneWidget);
    expect(find.textContaining('Update available'), findsNothing);
  });
}

class _FakeSettingsController extends SettingsController {
  @override
  Future<AppSettings> build() async => AppSettings.initial('/tmp/wishare');
}

class _FakeUpdateService extends UpdateService {
  _FakeUpdateService(this.result)
    : super(
        client: MockClient((_) async => throw UnimplementedError()),
        platform: UpdatePlatform.linux,
      );

  final UpdateInfo? result;
  int calls = 0;

  @override
  Future<UpdateInfo?> checkLatest() async {
    calls++;
    return result;
  }
}
