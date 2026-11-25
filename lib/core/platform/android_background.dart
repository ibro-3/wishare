import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Keeps the receiver reachable while Wishare is backgrounded on Android.
/// My design decision: dataSync foreground service with a Wi-Fi lock.
abstract final class AndroidBackground {
  static Future<void> initialize() async {
    if (!Platform.isAndroid) return;
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'wishare_receive',
        channelName: 'Wishare receiver',
        channelDescription: 'Wishare stays ready to receive files',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    try {
      await FlutterForegroundTask.startService(
        serviceId: 256,
        notificationTitle: 'Wishare is ready',
        notificationText: 'Ready to receive files on this network',
        serviceTypes: const [ForegroundServiceTypes.dataSync],
        callback: _wishareTaskCallback,
      );
    } on Object {
      // A denied notification permission must not prevent the app from running.
    }
  }
}

@pragma('vm:entry-point')
void _wishareTaskCallback() {
  FlutterForegroundTask.setTaskHandler(_WishareTaskHandler());
}

class _WishareTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}
