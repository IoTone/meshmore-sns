// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:meshcore/meshcore.dart';

import '../bot/bot_scope.dart';
import '../meshcore/chat_message.dart';
import 'mesh_tool.dart';

/// Rule 2 for every tool that sends text: Public is refused,
/// structurally — the same gate the R59 bot uses.
ToolFailure? scopeRefusal(BotScope scope, List<int>? Function(int) pskFor) =>
    switch (botRefusalFor(scope, pskFor)) {
      null => null,
      BotRefusal.unknownPsk => ToolFailure.unknownChannel,
      _ => ToolFailure.publicScope,
    };

class SoakEntry {
  SoakEntry(this.seq, this.sentAt, this.message);
  final int seq;
  final DateTime sentAt;

  /// The conversation row; its `delivery` evolves as the radio confirms
  /// and (DM only) the recipient ACKs.
  final ChatMessage? message;

  DateTime? ackAt;

  /// The radio's own send→ACK time, when it reported one.
  int? ackRttMs;

  /// When the first echo carrying this seq came back.
  DateTime? echoAt;
  int echoes = 0;

  MessageDelivery? get delivery => message?.delivery;
  int? get echoRttMs => echoAt?.difference(sentAt).inMilliseconds;
}

/// R60 T5 — many sequenced messages to one conversation, counted.
///
/// Each message is `echo soak <run> <seq>/<count>`. The leading `echo`
/// makes an R59 bot with the default pack answer
/// `#<N> echo soak <run> <seq>/<count>`, so a soak against a bot on
/// another radio counts drops, duplicates and reordering by itself.
class SoakTool extends MeshTool {
  SoakTool(super.mc, {super.now, Random? rng}) : _rng = rng ?? Random();

  final Random _rng;

  static const int maxCount = 500;
  static const Duration minIntervalDm = Duration(seconds: 5);
  static const Duration minIntervalChannel = Duration(seconds: 15);

  /// After the last send, how long to keep listening for late echoes.
  static const Duration echoGrace = Duration(seconds: 60);

  BotScope? scope;
  String scopeLabel = '';
  int count = 50;
  Duration interval = const Duration(seconds: 30);

  String? runId;
  DateTime? startedAt;
  DateTime? stoppedAt;

  /// True while sends are done and we only listen for late echoes.
  bool listening = false;

  final List<SoakEntry> entries = <SoakEntry>[];

  int duplicates = 0;
  int reordered = 0;
  int _maxEchoSeq = 0;

  bool get isDm => scope is DmScope;

  Duration get minInterval => isDm ? minIntervalDm : minIntervalChannel;

  int get sent => entries.length;
  int get delivered => entries
      .where((SoakEntry e) => e.delivery == MessageDelivery.delivered)
      .length;
  int get failed => entries
      .where((SoakEntry e) => e.delivery == MessageDelivery.failed)
      .length;
  int get echoed => entries.where((SoakEntry e) => e.echoAt != null).length;

  /// Seqs sent but never echoed (meaningful once echoes are coming).
  List<int> get missingEchoes => <int>[
        for (final SoakEntry e in entries)
          if (e.echoAt == null) e.seq,
      ];

  void configure({
    BotScope? scope,
    String? scopeLabel,
    int? count,
    Duration? interval,
  }) {
    if (running) return;
    if (scope != null) this.scope = scope;
    if (scopeLabel != null) this.scopeLabel = scopeLabel;
    if (count != null) this.count = count.clamp(1, maxCount);
    final Duration iv = interval ?? this.interval;
    this.interval = iv < minInterval ? minInterval : iv;
    notifyListeners();
  }

  /// The message for [seq] in the current run.
  String textFor(int seq) => 'echo soak $runId $seq/$count';

  Future<void> start() async {
    final BotScope? sc = scope;
    if (sc == null) {
      if (begin(exclusive: false)) finish(ToolFailure.noTarget);
      return;
    }
    final ToolFailure? refusal = scopeRefusal(sc, mc.channelPsk);
    if (refusal != null) {
      if (begin(exclusive: false)) finish(refusal);
      return;
    }
    if (!begin()) return;
    if (interval < minInterval) interval = minInterval;
    runId = _rng.nextInt(0x10000).toRadixString(16).padLeft(4, '0');
    entries.clear();
    duplicates = 0;
    reordered = 0;
    _maxEchoSeq = 0;
    listening = false;
    startedAt = now();
    stoppedAt = null;
    notifyListeners();

    final RegExp echo = RegExp('soak $runId (\\d+)/');
    final List<StreamSubscription<Object?>> subs =
        <StreamSubscription<Object?>>[
      mc.inboundFrames.listen((MeshcoreInbound f) {
        if (f is AckFrame) _onAck(f);
      }),
      switch (sc) {
        DmScope(:final String pubKeyHex) => mc.incomingDirectMessages
            // A sender the controller can't resolve is stored under its
            // 12-hex prefix, so match on the prefix too.
            .where((ChatMessage m) =>
                m.peerPubKeyHex != null &&
                pubKeyHex.startsWith(m.peerPubKeyHex!))
            .listen((ChatMessage m) => _onEcho(echo, m)),
        ChannelScope(:final int idx) => mc.incomingChannelMessages
            .where((ChatMessage m) => m.channelIdx == idx)
            .listen((ChatMessage m) => _onEcho(echo, m)),
      },
      // Delivery states change inside the controller; repaint with it.
      _controllerChanges().listen((_) => notifyListeners()),
    ];

    try {
      for (int seq = 1; seq <= count && !stopRequested; seq++) {
        final DateTime t0 = now();
        final ChatMessage? m = switch (sc) {
          DmScope(:final String pubKeyHex) =>
            await mc.sendDirectText(pubKeyHex, textFor(seq)),
          ChannelScope(:final int idx) =>
            await mc.sendChannelTextTo(idx, textFor(seq)),
        };
        entries.add(SoakEntry(seq, t0, m));
        notifyListeners();
        if (!mc.isReady) break;
        if (seq < count && !stopRequested) {
          final Duration left = interval - now().difference(t0);
          if (left > Duration.zero) await pause(left);
        }
      }
      if (!stopRequested && mc.isReady) {
        listening = true;
        notifyListeners();
        await pause(echoGrace);
      }
    } finally {
      listening = false;
      stoppedAt = now();
      for (final StreamSubscription<Object?> s in subs) {
        unawaited(s.cancel());
      }
      finish(mc.isReady ? null : ToolFailure.notConnected);
    }
  }

  Stream<void> _controllerChanges() {
    late final StreamController<void> c;
    void onChange() => c.add(null);
    c = StreamController<void>(
      onListen: () => mc.addListener(onChange),
      onCancel: () => mc.removeListener(onChange),
    );
    return c.stream;
  }

  void _onAck(AckFrame f) {
    for (final SoakEntry e in entries) {
      if (e.message?.expectedAck == f.ackCrc && e.ackAt == null) {
        e
          ..ackAt = now()
          ..ackRttMs = f.roundTripMs;
        notifyListeners();
        return;
      }
    }
  }

  void _onEcho(RegExp echo, ChatMessage m) {
    final RegExpMatch? hit = echo.firstMatch(m.text);
    if (hit == null) return;
    final int seq = int.parse(hit.group(1)!);
    SoakEntry? e;
    for (final SoakEntry x in entries) {
      if (x.seq == seq) e = x;
    }
    if (e == null) return; // not one of ours (or not yet recorded)
    e.echoes++;
    if (e.echoes > 1) {
      duplicates++;
    } else {
      e.echoAt = now();
      if (seq < _maxEchoSeq) reordered++;
      if (seq > _maxEchoSeq) _maxEchoSeq = seq;
    }
    notifyListeners();
  }

  /// JSON report (rule 6): enough to replay and to compare runs.
  String exportReport({String? firmware}) =>
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'tool': 'soak',
        'run': runId,
        'scope': scope?.key,
        'scopeLabel': scopeLabel,
        'count': count,
        'intervalSec': interval.inSeconds,
        'firmware': firmware,
        'startedAt': startedAt?.toUtc().toIso8601String(),
        'stoppedAt': stoppedAt?.toUtc().toIso8601String(),
        'sent': sent,
        'delivered': delivered,
        'failed': failed,
        'echoed': echoed,
        'duplicates': duplicates,
        'reordered': reordered,
        'messages': <Map<String, Object?>>[
          for (final SoakEntry e in entries)
            <String, Object?>{
              'seq': e.seq,
              'sentAt': e.sentAt.toUtc().toIso8601String(),
              'delivery': e.delivery?.name,
              'ackRttMs': e.ackRttMs,
              'echoRttMs': e.echoRttMs,
              'echoes': e.echoes,
            },
        ],
      });
}
