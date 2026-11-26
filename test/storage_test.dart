import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wishare/core/models/settings.dart';
import 'package:wishare/core/storage/app_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('corrupt preferences fall back instead of blocking startup', () async {
    SharedPreferences.setMockInitialValues({
      'peers': '[{"id": 42, "name": "broken"}]',
      'transfers': 'not a list',
    });
    final store = await AppStore.create();
    expect(store.loadPeers(), isEmpty);
    expect(store.loadTransfers(), isEmpty);
  });

  test('stale enum names and bad numbers fall back to defaults', () async {
    final json = jsonDecode(
      '{"themeMode":"future-mode","contrast":"future","maxFiles":"oops"}',
    ) as Map<String, dynamic>;
    // Parsing must not throw on values written by a future or edited build.
    final settings = AppSettings.fromJson(json, '/tmp/wishare');
    expect(settings.themeMode.name, isNot('future-mode'));
    expect(settings.contrast.name, isNot('future'));
    expect(settings.maxFiles, greaterThan(0));

    SharedPreferences.setMockInitialValues({
      'peers': '[{"id":"p","name":"PC","address":"","port":0}]',
    });
    expect((await AppStore.create()).loadPeers(), isEmpty);
  });
}
