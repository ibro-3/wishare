// ignore_for_file: deprecated_member_use
import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/legacy.dart';
import 'package:window_manager/legacy.dart';

/// Desktop shell setup: window sizing plus a system-tray icon and menu.
/// My design decision: close-to-tray interception is deferred; the tray keeps
/// a visible "Show Wishare" affordance and an explicit exit action.
abstract final class DesktopPlatform {
  static Future<void> initialize() async {
    final desktop = Platform.isLinux || Platform.isWindows;
    if (!desktop) return;

    await windowManager.ensureInitialized();
    final prefs = await SharedPreferences.getInstance();
    final savedWidth = prefs.getDouble('window.width');
    final savedHeight = prefs.getDouble('window.height');
    final settingsRaw = prefs.getString('settings');
    final startMinimized = settingsRaw == null
        ? false
        : (jsonDecode(settingsRaw)['startMinimized'] as bool? ?? false);
    const options = WindowOptions(
      size: Size(1100, 720),
      minimumSize: Size(600, 480),
      center: true,
      skipTaskbar: false,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      if (savedWidth != null && savedHeight != null) {
        await windowManager.setSize(Size(savedWidth, savedHeight));
      }
      if (startMinimized) {
        await windowManager.hide();
      } else {
        await windowManager.show();
        await windowManager.focus();
      }
    });

    // Close-to-tray: the window hides instead of ending the app; Exit in the
    // tray menu ends it explicitly.
    windowManager.addListener(_WindowDelegate());
    await windowManager.setPreventClose(true);

    try {
      trayManager.addListener(_TrayDelegate());
      await trayManager.setIcon('assets/icons/tray_icon.png');
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(key: 'show', label: 'Show Wishare'),
            MenuItem.separator(),
            MenuItem(key: 'exit', label: 'Exit'),
          ],
        ),
      );
    } on Object {
      // A missing tray provider must not prevent the app from starting.
    }
  }
}

class _WindowDelegate with WindowListener {
  @override
  void onWindowClose() async {
    final size = await windowManager.getSize();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('window.width', size.width);
    await prefs.setDouble('window.height', size.height);
    await windowManager.hide();
  }
}

class _TrayDelegate with TrayListener {
  @override
  void onTrayIconMouseDown() {
    windowManager.show();
    windowManager.focus();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        windowManager.show();
        windowManager.focus();
      case 'exit':
        windowManager.setPreventClose(false).then((_) => exit(0));
    }
  }
}
