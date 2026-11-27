import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wishare/core/models/settings.dart';
import 'package:wishare/core/network/transfer_coordinator.dart';
import 'package:wishare/core/state/providers.dart';
import 'package:wishare/features/transfer/send_screen.dart';

class _TestSettings extends SettingsController {
  @override
  Future<AppSettings> build() async => AppSettings.initial('/tmp/wishare');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late File file;
  late Directory folder;

  // Filesystem work happens in setUp, outside the testWidgets fake-async zone
  // where real I/O completions are never pumped.
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('wishare-drop-');
    file = File('${root.path}/report.txt');
    await file.writeAsString('hello');
    folder = Directory('${root.path}/photos');
    await folder.create();
    await File('${folder.path}/one.txt').writeAsString('x');
  });

  tearDown(() async => root.delete(recursive: true));

  test('dropped folders expand with the normal collector', () async {
    final entries = await TransferCoordinator(
      AppSettings.initial('/tmp/wishare'),
    ).collect([folder.path]);
    expect(entries.map((entry) => entry.relativePath), contains('photos'));
    expect(
      entries.map((entry) => entry.relativePath),
      contains('photos/one.txt'),
    );
  });

  testWidgets('a dropped file is added to the selection', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsProvider.overrideWith(_TestSettings.new)],
        child: const MaterialApp(home: SendScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Nothing selected yet'), findsOneWidget);

    const codec = StandardMethodCodec();
    tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'desktop_drop',
      codec.encodeMethodCall(const MethodCall('entered', [100.0, 100.0])),
      (_) {},
    );
    await tester.pumpAndSettle();
    expect(find.text('Drop files or folders to send'), findsOneWidget);

    tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'desktop_drop',
      codec.encodeMethodCall(MethodCall('performOperation', [file.path])),
      (_) {},
    );
    await tester.pumpAndSettle();

    expect(find.text('Nothing selected yet'), findsNothing);
    expect(find.text('report.txt'), findsOneWidget);
  });
}
