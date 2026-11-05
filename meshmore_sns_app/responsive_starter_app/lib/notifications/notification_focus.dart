// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT

/// Where the user already is, so the app does not announce what is on screen.
///
/// "Do not notify for the thread I am reading" is a user promise that no OS
/// API answers: the notification plugin cannot know which thread is open, so
/// the shell publishes it here and the notification decision reads it.
class NotificationFocus {
  /// False while the app is backgrounded (or the screen is off).
  bool foreground = true;

  /// The channel slot the chat screen currently shows, if any.
  int? openChannel;

  /// The peer whose DM thread is open, if any.
  String? openPeer;

  bool isChannelOpen(int channelIdx) =>
      foreground && openChannel == channelIdx;

  bool isPeerOpen(String peerKey) => foreground && openPeer == peerKey;

  /// A thread leaving the screen stops suppressing its notifications.
  void clearThread() {
    openChannel = null;
    openPeer = null;
  }
}
