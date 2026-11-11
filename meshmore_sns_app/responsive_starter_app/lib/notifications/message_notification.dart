// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT

/// What a notification is for, which decides its OS channel.
///
/// One OS channel per class is a user promise (D8.20): a mesh alert and a
/// chat line must be silenceable separately, and the SOS class must be able
/// to outrank both without changing the others.
enum NotificationClass {
  /// A message received on a channel slot.
  channel,

  /// A direct message from one peer.
  direct,

  /// An SOS or its ACK — the one class allowed to be loud by default.
  sos,
}

/// A message notification, already resolved to the text the OS will show.
///
/// Deliberately platform-free: the notifier decides how to present it, so a
/// test can assert the decision without touching a platform channel.
class MessageNotification {
  const MessageNotification({
    required this.id,
    required this.cls,
    required this.title,
    required this.body,
    required this.payload,
  });

  /// Stable per-message integer for the OS notification id, so replacing a
  /// notification for the same message cannot stack a second one.
  final int id;

  final NotificationClass cls;
  final String title;
  final String body;

  /// Tap routing. Carries the thread, never an index into a list that can be
  /// reordered: `ch:<slot>` or `dm:<pubkeyHex>`.
  final String payload;

  /// The OS channel id. Constant per class, so the user's per-channel
  /// silence setting keeps working across releases.
  String get channelId => switch (cls) {
        NotificationClass.channel => 'mm_messages_channel',
        NotificationClass.direct => 'mm_messages_direct',
        NotificationClass.sos => 'mm_messages_sos',
      };
}

/// One line standing in for a batch of messages the app deliberately did not
/// announce one at a time.
///
/// When the link comes up the radio hands over whatever queued while the phone
/// was away, and that queue can be a dozen messages in two seconds. A dozen
/// OS notifications for a moment the user did not witness is noise: one entry
/// says "unread messages" and the count, and a tap opens the newest thread.
class MessageDigest {
  const MessageDigest({
    required this.count,
    required this.cls,
    required this.title,
    required this.body,
    required this.payload,
  });

  /// How many messages this line stands for. Always at least one.
  final int count;

  /// The channel class of the newest message, which decides the OS channel.
  final NotificationClass cls;

  final String title;
  final String body;
  final String payload;

  String get channelId => switch (cls) {
        NotificationClass.channel => 'mm_messages_channel',
        NotificationClass.direct => 'mm_messages_direct',
        NotificationClass.sos => 'mm_messages_sos',
      };
}
