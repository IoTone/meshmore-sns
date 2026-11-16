// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/foundation.dart';

/// "Show me this view", from outside the shell.
///
/// A notification tap is the case this exists for: the tap handler runs in the
/// app root, which cannot reach the shell's private page controller, so tapping
/// a channel notification used to land on the Dashboard while the DM path
/// pushed its thread directly. The shell listens; everything else asks.
class ShellViewRequest extends ChangeNotifier {
  int _seq = 0;
  int? _chatSlot;
  RequestedView? _view;

  /// Which view was asked for, or null when nothing asked.
  RequestedView? get view => _view;

  /// Increments on every request, so two taps on the same channel are still
  /// two requests and the shell cannot miss the second one.
  int get seq => _seq;

  /// The channel slot to show in Chat, or null when nothing asked.
  int? get chatSlot => _chatSlot;

  /// Ask the shell to show Chat on [slot].
  void openChat(int slot) {
    _chatSlot = slot;
    _view = RequestedView.chat;
    _seq++;
    notifyListeners();
  }

  /// Ask the shell to show the Map tab.
  ///
  /// No surface calls this today — the grid's street-map view left the picker
  /// and the Map tab became a page of the shell — but the shell answers it, and
  /// the case it exists for has not gone away: anything that can name a place
  /// on a map (a place notification, a shared position) needs to send the reader
  /// there from outside the shell.
  void openMap() {
    _chatSlot = null;
    _view = RequestedView.map;
    _seq++;
    notifyListeners();
  }
}

/// The views another surface can ask the shell to show.
enum RequestedView { chat, map }
