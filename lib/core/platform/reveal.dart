import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// Opens received files in the system's default app and reveals their folder.
///
/// From M3: opening a received item is an action, so it uses the same role
/// colours as other filled/tonal actions in the app. My design decision (not
/// in M3): xdg-open on Linux, explorer on Windows and a FileProvider-backed
/// ACTION_VIEW intent on Android. Android has no comparable "reveal folder"
/// intent, so callers show the saved path instead.
abstract final class RevealInFolder {
  static const MethodChannel _channel = MethodChannel('dev.ibro.wishare/open');

  static Future<bool> openFolder(String path) async {
    final directory = Directory(path);
    if (!await directory.exists()) return false;
    if (Platform.isAndroid) return false;
    return _runDesktop(path);
  }

  static Future<bool> openFile(String path) async {
    final file = File(path);
    if (!await file.exists()) return false;
    if (Platform.isAndroid) {
      final opened = await _channel.invokeMethod<bool>('openFile', {
        'path': file.absolute.path,
      });
      return opened ?? false;
    }
    return _runDesktop(file.absolute.path);
  }

  /// Find the real path of a saved entry. The receiver adds a `-<timestamp>`
  /// suffix when a file with the same name already exists, so the manifest's
  /// relative path is only a first guess.
  static Future<String> resolveSavedFile(
    String saveDirectory,
    String relativePath,
  ) async {
    final direct = File(p.join(saveDirectory, relativePath));
    if (await direct.exists()) return direct.path;
    final parent = Directory(p.dirname(direct.path));
    if (!await parent.exists()) return direct.path;
    final base = p.basenameWithoutExtension(relativePath);
    final extension = p.extension(relativePath);
    await for (final entity in parent.list()) {
      if (entity is! File) continue;
      final name = p.basenameWithoutExtension(entity.path);
      if (name.startsWith('$base-') && p.extension(entity.path) == extension) {
        return entity.path;
      }
    }
    return direct.path;
  }

  static Future<bool> _runDesktop(String path) async {
    try {
      if (Platform.isLinux) {
        final result = await Process.run('xdg-open', [path]);
        return result.exitCode == 0;
      }
      if (Platform.isWindows) {
        final result = await Process.run('explorer', [path]);
        return result.exitCode == 0;
      }
    } on Object {
      return false;
    }
    return false;
  }
}
