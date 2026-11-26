import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
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
