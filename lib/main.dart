// ignore_for_file: deprecated_member_use
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:window_manager/legacy.dart';
import 'package:windows_single_instance/windows_single_instance.dart';

import 'app.dart';
import 'core/platform/android_background.dart';
import 'core/platform/desktop_platform.dart';
import 'core/platform/notifications.dart';
import 'core/platform/share_intent.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DesktopPlatform.initialize();
  await AndroidBackground.initialize();
  if (Platform.isWindows) {
    await WindowsSingleInstance.ensureSingleInstance(
      const [],
      'wishare_single_instance',
      onSecondWindow: (_) {
        windowManager.show();
        windowManager.focus();
      },
    );
  }
  WidgetsBinding.instance.addObserver(AppLifecycle());
  await Notifications.initialize();
  ShareIntents.onFiles = (_) => appRouter.go('/send');
  runApp(const ProviderScope(child: WishareApp()));
  await ShareIntents.initialize();
}
