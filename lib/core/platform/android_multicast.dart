import 'dart:io';

import 'package:flutter/services.dart';

/// Android needs a Wi-Fi multicast lock to receive mDNS datagrams reliably.
/// My design decision (not in M3): a tiny method channel backed by
/// WifiManager.MulticastLock; other platforms are no-ops.
abstract final class AndroidMulticast {
  static const MethodChannel _channel = MethodChannel(
    'dev.ibro.wishare/multicast',
  );

  static Future<void> acquire() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('acquire');
    } on Object {
      // Discovery still has the broadcast heartbeat and manual fallback.
    }
  }

  static Future<void> release() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('release');
    } on Object {
      // Nothing to release when the channel never acquired a lock.
    }
  }
}
