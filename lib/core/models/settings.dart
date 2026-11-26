import 'dart:io';

import 'package:material_ui/material_ui.dart';

import 'package:path_provider/path_provider.dart';

import '../theme/wishare_theme.dart';
import 'parse_helpers.dart';

class AppSettings {
  const AppSettings({
    required this.deviceName,
    required this.themeMode,
    required this.dynamicColor,
    required this.contrast,
    required this.downloadDirectory,
    required this.discoveryEnabled,
    required this.broadcastEnabled,
    required this.notificationsEnabled,
    required this.startMinimized,
    required this.maxFolderDepth,
    required this.maxFiles,
    required this.maxTransferBytes,
  });

  final String deviceName;
  final ThemeMode themeMode;
  final bool dynamicColor;
  final WiContrast contrast;
  final String? downloadDirectory;
  final bool discoveryEnabled;
  final bool broadcastEnabled;
  final bool notificationsEnabled;
  final bool startMinimized;
  final int maxFolderDepth;
  final int maxFiles;
  final int maxTransferBytes;

  /// My design decision: safe defaults for folder traversal limits.
  static AppSettings initial(String fallbackDirectory) => AppSettings(
    deviceName: 'Wishare device',
    themeMode: ThemeMode.system,
    dynamicColor: true,
    contrast: WiContrast.standard,
    downloadDirectory: fallbackDirectory,
    discoveryEnabled: true,
    broadcastEnabled: true,
    notificationsEnabled: true,
    startMinimized: false,
    maxFolderDepth: 32,
    maxFiles: 10000,
    maxTransferBytes: 20 * 1024 * 1024 * 1024,
  );

  static Future<String> defaultDownloadDirectory() async {
    final dir =
        await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    return '${dir.path}${Platform.pathSeparator}wishare';
  }

  AppSettings copyWith({
    String? deviceName,
    ThemeMode? themeMode,
    bool? dynamicColor,
    WiContrast? contrast,
    String? downloadDirectory,
    bool? discoveryEnabled,
    bool? broadcastEnabled,
    bool? notificationsEnabled,
    bool? startMinimized,
    int? maxFolderDepth,
    int? maxFiles,
    int? maxTransferBytes,
  }) {
    return AppSettings(
      deviceName: deviceName ?? this.deviceName,
      themeMode: themeMode ?? this.themeMode,
      dynamicColor: dynamicColor ?? this.dynamicColor,
      contrast: contrast ?? this.contrast,
      downloadDirectory: downloadDirectory ?? this.downloadDirectory,
      discoveryEnabled: discoveryEnabled ?? this.discoveryEnabled,
      broadcastEnabled: broadcastEnabled ?? this.broadcastEnabled,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      startMinimized: startMinimized ?? this.startMinimized,
      maxFolderDepth: maxFolderDepth ?? this.maxFolderDepth,
      maxFiles: maxFiles ?? this.maxFiles,
      maxTransferBytes: maxTransferBytes ?? this.maxTransferBytes,
    );
  }

  Map<String, dynamic> toJson() => {
    'deviceName': deviceName,
    'themeMode': themeMode.name,
    'dynamicColor': dynamicColor,
    'contrast': contrast.name,
    'downloadDirectory': downloadDirectory,
    'discoveryEnabled': discoveryEnabled,
    'broadcastEnabled': broadcastEnabled,
    'notificationsEnabled': notificationsEnabled,
    'startMinimized': startMinimized,
    'maxFolderDepth': maxFolderDepth,
    'maxFiles': maxFiles,
    'maxTransferBytes': maxTransferBytes,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json, String fallback) {
    final depth = integer(json['maxFolderDepth'], 32);
    final files = integer(json['maxFiles'], 10000);
    final bytes = integer(json['maxTransferBytes'], 20 * 1024 * 1024 * 1024);
    return AppSettings(
      deviceName: text(json['deviceName']) ?? 'Wishare device',
      themeMode:
          enumByName(ThemeMode.values, json['themeMode']) ?? ThemeMode.system,
      dynamicColor: boolean(json['dynamicColor'], true),
      contrast:
          enumByName(WiContrast.values, json['contrast']) ??
          WiContrast.standard,
      downloadDirectory: text(json['downloadDirectory']) ?? fallback,
      discoveryEnabled: boolean(json['discoveryEnabled'], true),
      broadcastEnabled: boolean(json['broadcastEnabled'], true),
      notificationsEnabled: boolean(json['notificationsEnabled'], true),
      startMinimized: boolean(json['startMinimized'], false),
      maxFolderDepth: depth < 1 ? 32 : (depth > 128 ? 128 : depth),
      maxFiles: files < 1 ? 10000 : (files > 100000 ? 100000 : files),
      maxTransferBytes: bytes < 1 ? 20 * 1024 * 1024 * 1024 : bytes,
    );
  }
}
