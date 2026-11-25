import 'dart:io';

import 'package:material_ui/material_ui.dart';

import 'package:path_provider/path_provider.dart';

import '../theme/wishare_theme.dart';

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

  factory AppSettings.fromJson(Map<String, dynamic> json, String fallback) =>
      AppSettings(
        deviceName: json['deviceName'] as String? ?? 'Wishare device',
        themeMode: json['themeMode'] == null
            ? ThemeMode.system
            : ThemeMode.values.byName(json['themeMode'] as String),
        dynamicColor: json['dynamicColor'] as bool? ?? true,
        contrast: json['contrast'] == null
            ? WiContrast.standard
            : WiContrast.values.byName(json['contrast'] as String),
        downloadDirectory: json['downloadDirectory'] as String? ?? fallback,
        discoveryEnabled: json['discoveryEnabled'] as bool? ?? true,
        broadcastEnabled: json['broadcastEnabled'] as bool? ?? true,
        notificationsEnabled: json['notificationsEnabled'] as bool? ?? true,
        startMinimized: json['startMinimized'] as bool? ?? false,
        maxFolderDepth: json['maxFolderDepth'] as int? ?? 32,
        maxFiles: json['maxFiles'] as int? ?? 10000,
        maxTransferBytes:
            json['maxTransferBytes'] as int? ?? 20 * 1024 * 1024 * 1024,
      );
}
