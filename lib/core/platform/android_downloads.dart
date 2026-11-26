import 'dart:io';

import 'package:flutter/services.dart';

/// Android DownloadManager bridge.
///
/// My design decision (not in M3): enqueue update APKs in the system download
/// manager instead of opening a browser, so the download continues in the
/// background and appears in the Downloads app with a completion notification.
/// Other platforms keep the browser path.
abstract final class AndroidDownloads {
  static const MethodChannel channel = MethodChannel(
    'dev.ibro.wishare/downloads',
  );

  static bool get isSupported => Platform.isAndroid;

  /// Returns the DownloadManager id, or null when the enqueue failed.
  static Future<int?> enqueue({
    required String url,
    required String fileName,
    required String title,
    String description = 'Wishare update',
  }) async {
    if (!isSupported) return null;
    try {
      return await channel.invokeMethod<int>('enqueue', {
        'url': url,
        'fileName': downloadFileName(fileName),
        'title': title,
        'description': description,
      });
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// DownloadManager cannot create nested paths. Keep only a safe basename;
  /// any query string or traversal segment is collapsed into the file name.
  static String downloadFileName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'wishare-update.apk';
    final base = trimmed.split(RegExp(r'[\\/]')).last;
    final safe = base.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return safe.isEmpty || safe == '.' || safe == '..'
        ? 'wishare-update.apk'
        : safe;
  }
}
