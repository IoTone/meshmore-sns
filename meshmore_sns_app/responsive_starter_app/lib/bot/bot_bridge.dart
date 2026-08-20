// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';

import '../meshcore/chat_message.dart';
import '../meshcore/meshcore_controller.dart';
import 'bot_controller.dart';
import 'bot_scope.dart';

/// Wires inbound mesh traffic to the bot and its replies back out
/// (R59).
///
/// App-scoped, like `CueBridge` and for the same reason: a soak client
/// that only answered while you happened to be looking at the thread
/// would be useless. The decision itself lives in [BotController];
/// this class is only plumbing, so the interesting behaviour stays
/// testable without a radio.
class BotBridge {
  BotBridge(this._mc, this._bot) {
    _msgSub = _mc.incomingChannelMessages.listen(_onChannel);
    _dmSub = _mc.incomingDirectMessages.listen(_onDm);
    _mc.addListener(_syncOwnKey);
    _syncOwnKey();
  }

  final MeshcoreController _mc;
  final BotController _bot;
  StreamSubscription<ChatMessage>? _msgSub;
  StreamSubscription<ChatMessage>? _dmSub;

  /// Keep the bot's idea of "us" current. It arrives with `SelfInfo`,
  /// after the streams are already live, and without it the
  /// own-message guard cannot fire.
  void _syncOwnKey() {
    final String? hex = _mc.ownPubKeyHex;
    if (hex != null && hex != _bot.ownPubKeyHex) _bot.ownPubKeyHex = hex;
  }

  void _onChannel(ChatMessage m) {
    // Never answer our own echo, whatever the guards would say.
    if (m.outgoing) return;
    // Draining the device queue on reconnect replays old traffic;
    // answering all of it would produce a burst of stale replies and
    // burn the airtime budget on messages nobody is waiting for.
    if (_mc.isDraining) return;

    final BotScope scope = ChannelScope(m.channelIdx);
    final String? reply = _bot.handleInbound(
      scope: scope,
      text: m.text,
      fromPubKeyHex: m.peerPubKeyHex,
    );
    if (reply == null) return;
    unawaited(_mc.sendChannelTextTo(m.channelIdx, reply));
  }

  void _onDm(ChatMessage m) {
    if (m.outgoing) return;
    if (_mc.isDraining) return;
    final String? peer = m.peerPubKeyHex;
    if (peer == null) return;

    final String? reply = _bot.handleInbound(
      scope: DmScope(peer),
      text: m.text,
      fromPubKeyHex: peer,
    );
    if (reply == null) return;
    unawaited(_mc.sendDirectText(peer, reply));
  }

  void dispose() {
    _mc.removeListener(_syncOwnKey);
    _msgSub?.cancel();
    _dmSub?.cancel();
  }
}
