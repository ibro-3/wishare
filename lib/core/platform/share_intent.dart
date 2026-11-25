import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

/// Android "Share to Wishare" intake.
///
/// My design decision: shared files are copied by the plugin into a cache
/// folder; their paths are exposed to the send screen, which builds a normal
/// transfer manifest from them. Links and plain text are ignored.
abstract final class ShareIntents {
  static final ValueNotifier<List<String>> pending =
      ValueNotifier<List<String>>(const []);

  /// Set by the app shell to navigate to the send screen on a new share.
  static void Function(List<String> paths)? onFiles;

  static Future<void> initialize() async {
    if (!Platform.isAndroid) return;
    try {
      final initial = await ReceiveSharingIntent.instance.getInitialMedia();
      await ReceiveSharingIntent.instance.reset();
      _consume(initial);
      ReceiveSharingIntent.instance.getMediaStream().listen(_consume);
    } on Object {
      // Sharing is optional; a plugin failure must not stop the app.
    }
  }

  static void _consume(List<SharedMediaFile> files) {
    final paths = files
        .where(
          (file) =>
              file.type != SharedMediaType.text &&
              file.type != SharedMediaType.url,
        )
        .map((file) => file.path)
        .toList();
    if (paths.isEmpty) return;
    pending.value = paths;
    onFiles?.call(paths);
  }

  static List<String> takePending() {
    final paths = List<String>.from(pending.value);
    pending.value = const [];
    return paths;
  }
}
