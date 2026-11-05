// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT

import 'message_notification.dart';
import 'notification_service.dart';

/// The app's answer to [NotificationEffects]: play a cue, vibrate, speak.
///
/// Held as functions so the notification layer never imports the cue or TTS
/// controllers: this class is what the app fills in at startup, and a test
/// can fill in recorders instead.
class AppNotificationEffects implements NotificationEffects {
  const AppNotificationEffects({
    required this.onCue,
    required this.onVibrate,
    required this.onSpeakChannel,
  });

  final void Function(NotificationClass cls) onCue;
  final void Function() onVibrate;
  final void Function(int channelIdx, String text) onSpeakChannel;

  @override
  void cue(NotificationClass cls) => onCue(cls);

  @override
  void vibrate() => onVibrate();

  @override
  void speakChannel(int channelIdx, String text) =>
      onSpeakChannel(channelIdx, text);
}
