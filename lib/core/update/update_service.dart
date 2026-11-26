import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/parse_helpers.dart';
import '../version.dart';

/// Which published release asset belongs to this device.
enum UpdatePlatform { android, linux, windows, other }

/// My design decision (not in M3): the app targets Linux, Android and Windows,
/// so platform detection is limited to those three; anything else falls back
/// to the release page.
UpdatePlatform detectUpdatePlatform() {
  if (Platform.isAndroid) return UpdatePlatform.android;
  if (Platform.isLinux) return UpdatePlatform.linux;
  if (Platform.isWindows) return UpdatePlatform.windows;
  return UpdatePlatform.other;
}

class UpdateException implements Exception {
  const UpdateException(this.message);

  final String message;

  @override
  String toString() => 'UpdateException: $message';
}

class UpdateAsset {
  const UpdateAsset({
    required this.name,
    required this.url,
    required this.size,
  });

  final String name;
  final String url;
  final int size;
}

class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.releaseNotes,
    required this.releaseUrl,
    required this.asset,
  });

  final String version;
  final String releaseNotes;
  final String releaseUrl;
  final UpdateAsset? asset;

  /// My design decision (not in M3): no matching build means we open the
  /// release page instead of a broken download link.
  String get downloadUrl => asset?.url ?? releaseUrl;

  String get downloadLabel => asset == null ? 'View release' : 'Download';
}

/// Reads the newest stable GitHub release.
///
/// My design decisions (not in M3): GitHub Releases is the update source, the
/// request times out after 10 seconds, and the download itself is opened in a
/// browser rather than installed in-app.
class UpdateService {
  UpdateService({http.Client? client, Uri? endpoint, UpdatePlatform? platform})
    : _client = client ?? http.Client(),
      _endpoint = endpoint ?? Uri.parse(defaultEndpoint),
      _platform = platform ?? detectUpdatePlatform();

  static const defaultEndpoint =
      'https://api.github.com/repos/ibro-3/wishare/releases/latest';
  static const fallbackReleaseUrl =
      'https://github.com/ibro-3/wishare/releases';
  static const timeout = Duration(seconds: 10);

  final http.Client _client;
  final Uri _endpoint;
  final UpdatePlatform _platform;

  Future<UpdateInfo?> checkLatest() async {
    late final http.Response response;
    try {
      response = await _client
          .get(
            _endpoint,
            headers: const {
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'wishare-update-checker',
              'X-GitHub-Api-Version': '2022-11-28',
            },
          )
          .timeout(timeout);
    } on Object {
      throw const UpdateException('Could not reach the release server.');
    }
    if (response.statusCode != 200) {
      throw UpdateException('Release server returned ${response.statusCode}.');
    }

    Map<String, dynamic>? map;
    try {
      map = object(json.decode(response.body));
    } on Object {
      map = null;
    }
    if (map == null) {
      throw const UpdateException('Unexpected release response.');
    }

    final tag = text(map['tag_name'])?.trim();
    if (tag == null || tag.isEmpty) {
      throw const UpdateException('Release has no version.');
    }
    final version = normaliseVersion(tag);
    // A malformed tag can never trigger an update prompt.
    if (!WiVersion.isNewer(version, WiVersion.current)) return null;

    final assets = <UpdateAsset>[];
    for (final entry in list(map['assets']) ?? const <dynamic>[]) {
      final assetMap = object(entry);
      if (assetMap == null) continue;
      final name = text(assetMap['name']);
      final url = text(assetMap['browser_download_url']);
      if (name == null || name.isEmpty || url == null || url.isEmpty) continue;
      assets.add(
        UpdateAsset(name: name, url: url, size: integer(assetMap['size'], 0)),
      );
    }

    return UpdateInfo(
      version: version,
      releaseNotes: text(map['body'])?.trim() ?? '',
      releaseUrl: text(map['html_url']) ?? fallbackReleaseUrl,
      asset: pickAsset(assets, _platform, version),
    );
  }

  /// `v0.4.0` and `0.4.0+7` both become `0.4.0`, which is what release assets
  /// are named after.
  static String normaliseVersion(String tag) {
    final parsed = WiVersion.parse(tag);
    if (parsed == null) return tag.replaceFirst(RegExp(r'^[vV]'), '');
    return '${parsed.major}.${parsed.minor}.${parsed.patch}';
  }

  /// Prefer the exact asset for this version, then the platform pattern.
  static UpdateAsset? pickAsset(
    List<UpdateAsset> assets,
    UpdatePlatform platform,
    String version,
  ) {
    final String exact;
    final RegExp fallback;
    switch (platform) {
      case UpdatePlatform.android:
        exact = 'wishare-$version-android.apk';
        fallback = RegExp(r'-android\.apk$');
      case UpdatePlatform.linux:
        exact = 'wishare-$version-linux-x64.zip';
        fallback = RegExp(r'-linux-x64\.zip$');
      case UpdatePlatform.windows:
        exact = 'wishare-$version-windows-x64.zip';
        fallback = RegExp(r'-windows-x64\.zip$');
      case UpdatePlatform.other:
        return null;
    }
    for (final asset in assets) {
      if (asset.name == exact) return asset;
    }
    for (final asset in assets) {
      if (fallback.hasMatch(asset.name)) return asset;
    }
    return null;
  }
}
