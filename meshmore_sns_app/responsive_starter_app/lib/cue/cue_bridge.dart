// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';

import '../meshcore/chat_message.dart';
import '../meshcore/meshcore_connection.dart';
import '../meshcore/meshcore_controller.dart';
import '../peer/peer_profiles.dart';
import '../tts/tts_controller.dart';
import 'cue_service.dart';

/// Wires [MeshcoreController] events to [CueService] (R12). Lives
/// app-scoped so cues fire wherever — independent of which screen is
/// foregrounded — and the call site (UI) is free to provide the
/// matching visual parity.
class CueBridge {
  CueBridge(this._mc, this._cue, [this._tts]) {
    _prev = _mc.state;
    _wasScanning = _mc.isScanning;
    _wasBacklogDrain = _mc.isBacklogDrain;
    _mc.addListener(_onChange);
    _msgSub =
        _mc.incomingChannelMessages.listen(_onIncomingChannelMessage);
    _dmSub =
        _mc.incomingDirectMessages.listen(_onIncomingDm);
    _errSub = _mc.taskErrors.listen((_) => _cue.play(CueKind.taskError));
    _advSub = _mc.incomingAdverts.listen(_onAdvert);
  }

  final MeshcoreController _mc;
  final CueService _cue;

  /// Speaks inbound traffic: channel messages per their per-channel
  /// mute (R5), DMs per the peer's tri-state (R58). Optional so
  /// existing construction sites (and the cue tests) are unaffected;
  /// null simply means no speech.
  ///
  /// Speech belongs **here** rather than in `ChatScreen` / `DmScreen`
  /// precisely because this bridge is app-scoped. Channel speech used
  /// to live in `ChatScreen.initState`, which meant it only spoke the
  /// channel you were already looking at — the one case where you did
  /// not need it read aloud — and went silent the moment you switched
  /// to Map or Nodes. `PeerSpeechMode.always` has the same shape: it
  /// means "I always want to hear this radio", which a screen-scoped
  /// subscription cannot honour.
  final TtsController? _tts;
  StreamSubscription<ChatMessage>? _msgSub;
  StreamSubscription<ChatMessage>? _dmSub;
  StreamSubscription<String>? _errSub;
  StreamSubscription<bool>? _advSub;
  late MeshcoreConnectionState _prev;
  late bool _wasScanning;

  /// Re-adverts arrive far faster than they should be sounded on a busy
  /// fabric; gate the ambient `advert` ping to at most one per window.
  DateTime _lastAdvertCue = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _advertThrottle = Duration(milliseconds: 1500);

  /// Messages delivered while a connect/resume **backlog** is replaying.
  ///
  /// The firmware does not push text in real time: every inbound message
  /// arrives through a SYNC drain. A radio that has been away for a while
  /// returns that history in one burst, and cuing each message produced a
  /// haptic and speech storm on launch — dozens of overlapping patterns for
  /// messages that were already minutes or hours old. Backlogged messages
  /// are counted here and answered with a single cue when the drain ends.
  ///
  /// Deliberately gated on [MeshcoreController.isBacklogDrain] and not
  /// [MeshcoreController.isDraining]: a drain kicked off by a live
  /// `MSGS_WAITING` push while already connected is fresh traffic and must
  /// still cue. See the comment on `isBacklogDrain` for the same trap in the
  /// bot bridge, where gating on `isDraining` made the feature inert.
  int _backlogMessages = 0;
  bool _wasBacklogDrain = false;

  void _onChange() {
    final MeshcoreConnectionState s = _mc.state;
    if (s != _prev) {
      switch (s) {
        case MeshcoreConnectionState.ready:
          _cue.play(CueKind.linkUp);
        case MeshcoreConnectionState.failed:
          _cue.play(CueKind.alert);
        case MeshcoreConnectionState.reconnecting:
          _cue.play(CueKind.linkDown);
        case MeshcoreConnectionState.disconnected:
        case MeshcoreConnectionState.handshaking:
          break; // no cue
      }
      _prev = s;
    }
    // Backlog falling edge → one summary cue. Detected here because the
    // per-message handlers cannot know that a burst has finished.
    final bool nowBacklog = _mc.isBacklogDrain;
    if (_wasBacklogDrain && !nowBacklog) {
      if (_backlogMessages > 0) {
        _backlogMessages = 0;
        _cue.play(CueKind.messageIn);
      }
    }
    _wasBacklogDrain = nowBacklog;

    // Scan rising/falling edge → scanStart / taskOk. Detected on any
    // controller notify since isScanning is set & notifyListeners'd by
    // mc.scan() + the scan-window timer.
    final bool nowScanning = _mc.isScanning;
    if (nowScanning != _wasScanning) {
      // Scanning drone runs for the *whole* window: start the loop on the
      // rising edge, stop it + chime taskOk on the falling edge.
      if (nowScanning) {
        _cue.startScanHum();
      } else {
        _cue.stopScanHum();
        _cue.play(CueKind.taskOk);
      }
      _wasScanning = nowScanning;
    }
  }

  /// A live advert was folded into the fabric. `isNew` is true for a
  /// node we'd never heard (→ discovery, the Geiger tick) and false for
  /// a re-advert from a known node (→ advert, the ambient ping). The
  /// stream only fires for over-the-air adverts, so the post-connect
  /// contact-sync dump never reaches here — no machine-gunning.
  void _onAdvert(bool isNew) {
    if (_mc.isDraining) return;
    if (isNew) {
      _cue.play(CueKind.discovery);
      return;
    }
    final DateTime now = DateTime.now();
    if (now.difference(_lastAdvertCue) < _advertThrottle) return;
    _lastAdvertCue = now;
    _cue.play(CueKind.advert);
  }

  void _onIncomingChannelMessage(ChatMessage m) {
    // History, not an arrival: count it and let the drain-end summary speak.
    if (_mc.isBacklogDrain) {
      _backlogMessages++;
      return;
    }
    _cue.play(CueKind.messageIn);
    final TtsController? tts = _tts;
    if (tts == null) return;
    // Fire-and-forget, as with DMs: a slow platform TTS call must not
    // stall the cue path or the message store behind it. The gate
    // (master + global + per-channel mute) lives in the controller.
    unawaited(tts.speakForChannel(m.channelIdx, m.text));
  }

  void _onIncomingDm(ChatMessage m) {
    // See _onIncomingChannelMessage: replayed history never cues or speaks.
    if (_mc.isBacklogDrain) {
      _backlogMessages++;
      return;
    }
    final String? peer = m.peerPubKeyHex;
    final TtsController? tts = _tts;

    // R58 — a peer with a signature gets it *instead of* `dmIn`, never
    // as well as it. `playSignature(null)` is the ordinary DM cue, so
    // there is no branch here and no way to accidentally play both.
    final PeerProfiles? peers = _tts?.peers;
    _cue.playSignature(
      peer == null || peers == null ? null : peers.signatureFor(peer),
    );

    if (peer == null || tts == null) return;
    // Fire-and-forget: a slow platform TTS call must not stall the
    // cue path or the message store behind it.
    unawaited(tts.speakForPeer(peer, m.text));
  }

  void dispose() {
    _cue.stopScanHum(); // don't leave the drone looping if torn down mid-scan
    _mc.removeListener(_onChange);
    _msgSub?.cancel();
    _dmSub?.cancel();
    _errSub?.cancel();
    _advSub?.cancel();
  }
}
