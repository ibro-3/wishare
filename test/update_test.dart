import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wishare/core/models/settings.dart';
import 'package:wishare/core/state/providers.dart';
import 'package:wishare/core/state/update_provider.dart';
import 'package:wishare/core/update/update_service.dart';
import 'package:wishare/core/version.dart';

void main() {
  test('published version matches the Dart source of truth', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*(\S+)',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(match, isNotNull);
    expect(match!.group(1)!.split('+').first, WiVersion.current);
  });

  test('semantic comparison ignores v prefix and build metadata', () {
    expect(WiVersion.isNewer('v0.4.0', WiVersion.current), isTrue);
    expect(WiVersion.isNewer('v0.3.1', WiVersion.current), isTrue);
    expect(WiVersion.isNewer('0.3.0+7', WiVersion.current), isFalse);
    expect(WiVersion.isNewer('0.2.9', WiVersion.current), isFalse);
    expect(WiVersion.isNewer('nonsense', WiVersion.current), isFalse);
    expect(UpdateService.normaliseVersion('v0.4.0+12'), '0.4.0');
  });

  test('asset picker prefers the exact build then the platform pattern', () {
    final assets = [
      const UpdateAsset(
        name: 'wishare-0.4.0-android-arm64-v8a.apk',
        url: 'arm',
        size: 1,
      ),
      const UpdateAsset(
        name: 'wishare-0.4.0-linux-x64.zip',
        url: 'linux',
        size: 2,
      ),
      const UpdateAsset(
        name: 'wishare-0.4.0-android.apk',
        url: 'universal',
        size: 3,
      ),
    ];
    expect(
      UpdateService.pickAsset(assets, UpdatePlatform.android, '0.4.0')?.url,
      'universal',
    );
    expect(
      UpdateService.pickAsset(assets, UpdatePlatform.linux, '0.4.0')?.url,
      'linux',
    );
    expect(
      UpdateService.pickAsset(assets, UpdatePlatform.windows, '0.4.0'),
      isNull,
    );
    expect(
      UpdateService.pickAsset(assets, UpdatePlatform.other, '0.4.0'),
      isNull,
    );
  });

  test('a newer release becomes update info with the right asset', () async {
    final client = MockClient((request) async {
      expect(request.url.host, 'api.github.com');
      expect(request.headers['User-Agent'], 'wishare-update-checker');
      return http.Response(
        jsonEncode({
          'tag_name': 'v0.4.0',
          'body': 'New things',
          'html_url': 'https://github.com/ibro-3/wishare/releases/tag/v0.4.0',
          'assets': [
            {
              'name': 'wishare-0.4.0-linux-x64.zip',
              'browser_download_url': 'https://example.test/linux.zip',
              'size': 42,
            },
          ],
        }),
        200,
      );
    });
    final info = await UpdateService(
      client: client,
      platform: UpdatePlatform.linux,
    ).checkLatest();
    expect(info, isNotNull);
    expect(info!.version, '0.4.0');
    expect(info.releaseNotes, 'New things');
    expect(info.downloadUrl, 'https://example.test/linux.zip');
    expect(info.downloadLabel, 'Download');
  });

  test('an older release yields no update', () async {
    final client = MockClient(
      (_) async => http.Response(jsonEncode({'tag_name': 'v0.2.0'}), 200),
    );
    expect(
      await UpdateService(
        client: client,
        platform: UpdatePlatform.linux,
      ).checkLatest(),
      isNull,
    );
  });

  test('unavailable assets fall back to the release page', () async {
    final client = MockClient((_) async {
      return http.Response(
        jsonEncode({
          'tag_name': 'v0.4.0',
          'html_url': 'https://github.com/ibro-3/wishare/releases/tag/v0.4.0',
          'assets': [
            {
              'name': 'wishare-0.4.0-android.apk',
              'browser_download_url': 'https://example.test/app.apk',
              'size': 1,
            },
          ],
        }),
        200,
      );
    });
    final info = await UpdateService(
      client: client,
      platform: UpdatePlatform.windows,
    ).checkLatest();
    expect(info!.asset, isNull);
    expect(info.downloadUrl, contains('/releases/tag/v0.4.0'));
    expect(info.downloadLabel, 'View release');
  });

  test('HTTP and JSON failures surface as update exceptions', () async {
    final failing = MockClient((_) async => http.Response('', 503));
    expect(
      UpdateService(client: failing).checkLatest(),
      throwsA(isA<UpdateException>()),
    );
    final broken = MockClient((_) async => http.Response('not json', 200));
    expect(
      UpdateService(client: broken).checkLatest(),
      throwsA(isA<UpdateException>()),
    );
  });

  test('autoUpdateCheck defaults on and survives a JSON round trip', () {
    final defaults = AppSettings.fromJson({}, '/tmp/wishare');
    expect(defaults.autoUpdateCheck, isTrue);
    final disabled = defaults.copyWith(autoUpdateCheck: false);
    expect(
      AppSettings.fromJson(disabled.toJson(), '/tmp/wishare').autoUpdateCheck,
      isFalse,
    );
  });

  test('startup check honours the Settings toggle', () async {
    for (final enabled in [true, false]) {
      final service = _CountingUpdateService();
      final container = ProviderContainer(
        overrides: [
          updateServiceProvider.overrideWithValue(service),
          settingsProvider.overrideWith(
            () => _FixedSettingsController(enabled),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(startupUpdateCheckProvider.future);
      expect(service.calls, enabled ? 1 : 0);
    }
  });
}

class _FixedSettingsController extends SettingsController {
  _FixedSettingsController(this.enabled);

  final bool enabled;

  @override
  Future<AppSettings> build() async =>
      AppSettings.initial('/tmp/wishare').copyWith(autoUpdateCheck: enabled);
}

class _CountingUpdateService extends UpdateService {
  _CountingUpdateService()
    : super(
        client: MockClient((_) async => throw UnimplementedError()),
        platform: UpdatePlatform.linux,
      );

  int calls = 0;

  @override
  Future<UpdateInfo?> checkLatest() async {
    calls++;
    return null;
  }
}
