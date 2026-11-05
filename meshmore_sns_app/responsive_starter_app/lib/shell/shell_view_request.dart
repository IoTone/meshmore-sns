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

  /// Increments on every request, so two taps on the same channel are still
  /// two requests and the shell cannot miss the second one.
  int get seq => _seq;

  /// The channel slot to show in Chat, or null when nothing asked.
  int? get chatSlot => _chatSlot;

  /// Ask the shell to show Chat on [slot].
  void openChat(int slot) {
    _chatSlot = slot;
    _seq++;
    notifyListeners();
  }
}
