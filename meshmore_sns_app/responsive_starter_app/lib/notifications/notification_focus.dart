// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/widgets.dart';

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

  /// Whether the app is in front *now*.
  ///
  /// `foreground` is written by a lifecycle observer, and a lifecycle event
  /// missed during a process restart left it `true` for the rest of the
  /// session, which silenced the open channel's notifications even with the
  /// screen off. The platform's own answer is authoritative, so it is read at
  /// the moment of the check and the cached flag is only the fallback for a
  /// platform that has no lifecycle state (a widget test).
  bool get _inFront {
    final AppLifecycleState? life = WidgetsBinding.instance.lifecycleState;
    if (life == null) return foreground;
    return life == AppLifecycleState.resumed;
  }

  bool isChannelOpen(int channelIdx) =>
      _inFront && openChannel == channelIdx;

  bool isPeerOpen(String peerKey) => _inFront && openPeer == peerKey;

  /// A thread leaving the screen stops suppressing its notifications.
  void clearThread() {
    openChannel = null;
    openPeer = null;
  }
}
