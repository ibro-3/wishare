import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Local notifications for incoming transfer offers while the app is not in
/// the foreground. My design decision: single high-importance channel,
/// notification only when the offer was not handled on screen.
abstract final class Notifications {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      if (Platform.isAndroid) {
        const channel = AndroidNotificationChannel(
          'wishare_offers',
          'Incoming transfers',
          description: 'Someone wants to send you files',
          importance: Importance.high,
        );
        await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.createNotificationChannel(channel);
        await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission();
      }
      _initialized = true;
    } on Object {
      // Notifications are optional; the in-app offer sheet is authoritative.
    }
  }

  static Future<void> showIncomingOffer(String sender, int itemCount) async {
    if (!_initialized) return;
    try {
      await _plugin.show(
        id: itemCount.hashCode,
        title: 'Incoming from $sender',
        body: '$itemCount items waiting for your approval',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'wishare_offers',
            'Incoming transfers',
            channelDescription: 'Someone wants to send you files',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        payload: '/receive',
      );
    } on Object {
      // Never let a notification failure interrupt discovery.
    }
  }
}

/// Tracks app lifecycle so offers can be notified only when backgrounded.
class AppLifecycle extends WidgetsBindingObserver {
  static final ValueNotifier<AppLifecycleState> state = ValueNotifier(
    AppLifecycleState.resumed,
  );

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    AppLifecycle.state.value = state;
  }
}
