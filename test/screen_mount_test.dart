import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wishare/features/devices/scan_screen.dart';
import 'package:wishare/features/transfer/send_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('SendScreen mounts without a GoRouter ancestor', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SendScreen())),
    );
    await tester.pumpAndSettle();
    expect(find.text('Send to'), findsOneWidget);
    expect(find.byTooltip('Scan again'), findsOneWidget);
  });

  testWidgets('Send tab lists devices without a separate Send button', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'peers': jsonEncode([
        {
          'id': 'peer-1',
          'name': 'Living room PC',
          'address': '192.168.1.20',
          'port': 45821,
          'colorSeed': 0xFF6750A4,
          'sessionToken': 'token',
          'trustLevel': 'paired',
        },
      ]),
    });
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SendScreen())),
    );
    await tester.pumpAndSettle();
    expect(find.text('Living room PC'), findsOneWidget);
    expect(find.text('Send'), findsNothing);
  });

  testWidgets('Send to lists paired and nearby devices in one list', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'peers': jsonEncode([
        {
          'id': 'nearby-1',
          'name': 'Nearby laptop',
          'address': '192.168.1.30',
          'port': 45821,
          'colorSeed': 0xFF6750A4,
        },
        {
          'id': 'paired-1',
          'name': 'Paired PC',
          'address': '192.168.1.20',
          'port': 45821,
          'colorSeed': 0xFF6750A4,
          'sessionToken': 'token',
          'trustLevel': 'paired',
        },
      ]),
    });
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SendScreen())),
    );
    await tester.pumpAndSettle();
    expect(find.text('Send to'), findsOneWidget);
    expect(find.text('Nearby devices'), findsNothing);
    expect(find.text('Paired PC'), findsOneWidget);
    expect(find.text('Nearby laptop'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Pair'), findsOneWidget);
    final firstTile = find.byType(ListTile).first;
    final titleText =
        find
                .descendant(of: firstTile, matching: find.byType(Text))
                .evaluate()
                .first
                .widget
            as Text;
    expect(titleText.data, 'Paired PC');
  });

  testWidgets(
    'ScanScreen falls back to manual pairing without a camera plugin',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: ScanScreen())),
      );
      await tester.pumpAndSettle();
      expect(find.text('Enter pairing details'), findsOneWidget);
      expect(find.byType(MobileScanner), findsNothing);
      expect(find.byTooltip('Show my code'), findsOneWidget);
    },
  );

  testWidgets('ScanScreen takes route parameters via its constructor', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: ScanScreen(host: '192.168.1.20')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Enter pairing details'), findsOneWidget);
  });
}
