// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../gen/app_localizations.dart';
import '../meshcore/meshcore_controller.dart';
import '../sos/sos_controller.dart';
import '../sos/sos_engine.dart';
import '../sos/sos_schedule.dart';
import '../theme/mm_skin.dart';
import '../ui/mm_components.dart';
import '../ui/mm_scaffold.dart';
import '../ui/mm_shape.dart';

/// The emergency alarm (`meshmore-sos-spec.md` §8, §10).
///
/// Raising an alarm is destructive to a shared channel, so it is a
/// **three-second hold** with the destination and the fix in front of the
/// user — not a dialog to read. The copy is the spec's list, in its order:
/// what repeats, where it goes, and that nobody is notified unless they are in
/// radio range. Nothing on this screen says "sent" or "delivered", because a
/// channel text has no acknowledgement at all.
class SosScreen extends StatefulWidget {
  const SosScreen({super.key});

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> {
  final TextEditingController _words = TextEditingController();
  Timer? _hold;

  /// What the hold has reached, 0..1, for the progress bar under the finger.
  double _held = 0;

  /// Why the last hold was refused or released early; shown under the control.
  String? _note;

  bool _prefilled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The engine refuses an alarm with no words (`SosRefusal.noWords`), and
    // asking someone to type during an emergency is the wrong trade. The field
    // starts with a minimum the user can overwrite, so the hold works on its
    // own and the wire text still says something useful.
    if (_prefilled) return;
    _prefilled = true;
    _words.text = AppLocalizations.of(context).sosDefaultWords;
  }

  @override
  void dispose() {
    _hold?.cancel();
    _words.dispose();
    super.dispose();
  }

  void _beginHold(SosController c, AppLocalizations l) {
    if (c.state == SosState.arming) return;
    final SosRefusal? refused = c.arm(words: _words.text);
    setState(() {
      _note = null;
      _held = 0;
      if (refused != null) _note = _refusalText(l, refused);
    });
    if (refused != null) return;
    // The engine times the hold itself; this only draws it and calls confirm
    // once it has elapsed. A little margin over the engine's three seconds,
    // so the confirm cannot land a frame early.
    const Duration step = Duration(milliseconds: 100);
    final int total = SosEngine.hold.inMilliseconds + 100;
    int elapsed = 0;
    _hold = Timer.periodic(step, (Timer t) {
      elapsed += step.inMilliseconds;
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _held = elapsed / total);
      if (elapsed < total) return;
      t.cancel();
      _hold = null;
      c.confirm();
    });
  }

  /// True while the framework is mid-frame and `setState` is illegal.
  ///
  /// A released hold can be delivered from the gesture arena's own teardown
  /// (leaving the screen while the finger is down), and the alarm still has to
  /// be aborted then — an alarm left `arming` would block every later attempt.
  /// Only the note cannot be painted, because there is no frame left to paint
  /// it in.
  bool get _treeLocked {
    final SchedulerPhase p = SchedulerBinding.instance.schedulerPhase;
    return p == SchedulerPhase.persistentCallbacks ||
        p == SchedulerPhase.midFrameMicrotasks;
  }

  void _endHold(SosController c, AppLocalizations l) {
    if (_hold == null) return;
    _hold!.cancel();
    _hold = null;
    if (c.state != SosState.arming) return;
    c.abort();
    if (_treeLocked) return;
    setState(() {
      _held = 0;
      _note = l.sosHoldReleased;
    });
  }

  String _refusalText(AppLocalizations l, SosRefusal r) => switch (r) {
        SosRefusal.alreadyActive => l.sosRefusedAlreadyActive,
        SosRefusal.holdNotComplete => l.sosRefusedHold,
        SosRefusal.tooLong => l.sosRefusedTooLong,
        SosRefusal.noDestination => l.sosRefusedNoDestination,
        SosRefusal.noWords => l.sosRefusedNoWords,
        SosRefusal.noIdentity => l.sosNoIdentity,
      };

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;
    final SosController sos = context.watch<SosController>();
    final MeshcoreController mc = context.watch<MeshcoreController>();

    final bool ended = sos.state == SosState.expired ||
        sos.state == SosState.cancelled ||
        sos.state == SosState.acknowledged;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.sosTitle),
        actions: <Widget>[
          IconButton(
            key: const ValueKey<String>('checkin-entry'),
            tooltip: l.checkinEntryTooltip,
            icon: const Icon(Icons.schedule_send),
            onPressed: () => context.push('/checkin'),
          ),
        ],
      ),
      body: MmScaffold(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
              skin.space.step(5), skin.space.step(4), skin.space.step(5), 40),
          children: <Widget>[
            if (ended)
              _Ended(sos: sos, l: l)
            else ...<Widget>[
              _Destination(sos: sos, mc: mc, l: l),
              SizedBox(height: skin.space.step(4)),
              // While the hold is still under the finger the hold control
              // stays: swapping it for the running panel would dispose the
              // gesture recognizer mid-press, and the release would abort the
              // alarm it was meant to raise.
              if (sos.isRunning)
                _Running(sos: sos, l: l)
              else ...<Widget>[
                Text(l.sosWords,
                    style: TextStyle(
                        color: skin.color.fg,
                        fontSize: skin.type.sizeBodyLg,
                        fontWeight: FontWeight.w600)),
                SizedBox(height: skin.space.step(2)),
                TextField(
                  key: const ValueKey<String>('sos-words'),
                  controller: _words,
                  maxLines: 2,
                  style: TextStyle(
                      color: skin.color.fg, fontSize: skin.type.sizeBody),
                  decoration: InputDecoration(
                    hintText: l.sosWordsHint,
                    hintStyle: TextStyle(
                        color: skin.color.fgMuted, fontSize: skin.type.sizeSm),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: mmRadius(context, kRadiusSm),
                      borderSide: BorderSide(color: skin.color.line),
                    ),
                  ),
                ),
                SizedBox(height: skin.space.step(4)),
                _holdControl(context, sos, l, skin, mc.isReady),
                if (_note != null) ...<Widget>[
                  SizedBox(height: skin.space.step(3)),
                  Text(_note!,
                      key: const ValueKey<String>('sos-note'),
                      style: TextStyle(
                          color: skin.color.alert,
                          fontSize: skin.type.sizeBody)),
                ],
              ],
            ],
          ],
        ),
      ),
    );
  }

  /// The three-second hold. A press that ends early raises nothing, and the
  /// screen says so rather than leaving the user wondering (`§8`).
  Widget _holdControl(BuildContext context, SosController sos,
      AppLocalizations l, MmSkin skin, bool radioReady) {
    final bool armed = sos.state == SosState.arming;
    final bool enabled = radioReady && !armed;
    final Color fg = enabled ? skin.color.fg : skin.color.fgMuted;
    // A screen reader cannot press and hold, and the semantic action used to be
    // an empty closure: the alarm was reachable by finger only. Both semantic
    // actions start the same hold the finger starts, and the hold is timed by
    // this widget rather than by the gesture, so the alarm raises exactly as it
    // does with a finger on the control.
    return Semantics(
      button: true,
      enabled: enabled,
      label: l.sosHoldToArm,
      onTap: enabled ? () => _beginHold(sos, l) : null,
      onLongPress: enabled ? () => _beginHold(sos, l) : null,
      // The recognizer below turns a semantic tap into a down and an up in the
      // same frame, which arms and then aborts — "released too early" to a
      // screen reader who did nothing wrong. Its own semantics are excluded so
      // the action above is the only one a screen reader can reach; the finger
      // path is unchanged.
      child: ExcludeSemantics(
        child: GestureDetector(
          key: const ValueKey<String>('sos-hold'),
          onTapDown: (_) => _beginHold(sos, l),
          onTapUp: (_) => _endHold(sos, l),
          onTapCancel: () => _endHold(sos, l),
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: EdgeInsets.symmetric(
                horizontal: skin.space.step(4), vertical: skin.space.step(3)),
            decoration: ShapeDecoration(
              color: skin.color.surfaceAlt,
              shape: mmShapeBorder(
                skin.shape,
                side: BorderSide(
                    color: enabled ? skin.color.alert : skin.color.line,
                    width: skin.shape.borderWidth),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(Icons.emergency_share,
                        size: skin.type.sizeXl, color: skin.color.alert),
                    SizedBox(width: skin.space.step(3)),
                    Expanded(
                      child: Text(
                        armed
                            ? l.sosHoldRemaining(
                                ((1 - _held) * SosEngine.hold.inSeconds)
                                    .ceil()
                                    .clamp(0, SosEngine.hold.inSeconds))
                            : l.sosHoldToArm,
                        style: TextStyle(
                            color: fg,
                            fontSize: skin.type.sizeBodyLg,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                if (armed) ...<Widget>[
                  SizedBox(height: skin.space.step(2)),
                  LinearProgressIndicator(
                    value: _held,
                    minHeight: 4,
                    color: skin.color.alert,
                    backgroundColor: skin.color.line,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Where the alarm goes, and the two honest lines about reach (§10 items 1-3).
class _Destination extends StatelessWidget {
  const _Destination({required this.sos, required this.mc, required this.l});

  final SosController sos;
  final MeshcoreController mc;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final MmSkin skin = context.skin;
    final bool emergency = sos.emergencyChannelSlot != null &&
        sos.channelSlot == sos.emergencyChannelSlot;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(l.sosRepeatsOneHour,
            style: TextStyle(
                color: skin.color.fg,
                fontSize: skin.type.sizeLg,
                fontWeight: FontWeight.w700)),
        SizedBox(height: skin.space.step(3)),
        Text(l.sosDestination,
            style: TextStyle(
                color: skin.color.fgMuted,
                fontSize: skin.type.sizeSm,
                letterSpacing: 1.5)),
        SizedBox(height: skin.space.step(1)),
        // Where it goes is two separate lines, because a channel and a direct
        // message guarantee different things (§10 item 2).
        Text(l.sosGoesToChannel(sos.channelName),
            style:
                TextStyle(color: skin.color.fg, fontSize: skin.type.sizeBody)),
        Text(l.sosGoesToContacts(sos.contactKeysHex.length),
            style: TextStyle(
                color: sos.contactKeysHex.isEmpty
                    ? skin.color.fgMuted
                    : skin.color.fg,
                fontSize: skin.type.sizeBody)),
        if (sos.contactKeysHex.isEmpty) ...<Widget>[
          SizedBox(height: skin.space.step(1)),
          Text(l.sosContactsNone,
              style: TextStyle(
                  color: skin.color.fgMuted, fontSize: skin.type.sizeSm)),
        ],
        if (emergency) ...<Widget>[
          SizedBox(height: skin.space.step(2)),
          // APP-H5: the key is computable from the name, so the alarm is
          // public by construction. No surface may call it private.
          Text(l.sosEmergencyPublicKey,
              key: const ValueKey<String>('sos-emergency-key'),
              style: TextStyle(
                  color: skin.color.fgMuted,
                  fontSize: skin.type.sizeSm,
                  height: 1.4)),
          Text(l.sosEmergencyRepeat,
              style: TextStyle(
                  color: skin.color.fgMuted,
                  fontSize: skin.type.sizeSm,
                  height: 1.4)),
        ],
        SizedBox(height: skin.space.step(3)),
        Text(l.sosInRange,
            style: TextStyle(
                color: skin.color.fgMuted, fontSize: skin.type.sizeSm)),
      ],
    );
  }
}

/// The running alarm: how much is left, what answered, and the way out.
class _Running extends StatelessWidget {
  const _Running({required this.sos, required this.l});

  final SosController sos;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final MmSkin skin = context.skin;
    final Duration? next = sos.untilNextSend;
    final int total = SosSchedule.packetCount;
    final int left = sos.remaining.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            MmStatusPill(l.sosActive,
                key: const ValueKey<String>('sos-active'), alert: true),
            SizedBox(width: skin.space.step(3)),
            if (next != null)
              Text(l.sosNextSend(next.inSeconds),
                  key: const ValueKey<String>('sos-next'),
                  style: TextStyle(
                      color: skin.color.fg, fontSize: skin.type.sizeBody)),
          ],
        ),
        SizedBox(height: skin.space.step(2)),
        Text(
            '${l.sosElapsed(sos.elapsed.inMinutes)}  ·  '
            '${l.sosRemaining(left, total)}',
            style: TextStyle(
                color: skin.color.fgMuted, fontSize: skin.type.sizeSm)),
        // What the schedule did not manage, said plainly: a sleep window skips
        // repeats rather than firing a burst the radio would drop, and a
        // refused repeat is a repeat nobody heard.
        if (sos.missedSends > 0) ...<Widget>[
          SizedBox(height: skin.space.step(2)),
          Text(l.sosMissedSends(sos.missedSends),
              key: const ValueKey<String>('sos-missed'),
              style: TextStyle(
                  color: skin.color.alert, fontSize: skin.type.sizeSm)),
        ],
        if (sos.failedSends > 0) ...<Widget>[
          SizedBox(height: skin.space.step(2)),
          Text(l.sosSendFailed,
              key: const ValueKey<String>('sos-send-failed'),
              style: TextStyle(
                  color: skin.color.alert, fontSize: skin.type.sizeSm)),
        ],
        SizedBox(height: skin.space.step(4)),
        if (sos.acks.isNotEmpty) ...<Widget>[
          MmSectionHeader(l.sosAcknowledgedHeading),
          for (final SosAckRow a in sos.acks)
            Padding(
              padding: EdgeInsets.only(top: skin.space.step(2)),
              child: Text(
                a.claimed ? l.sosClaimedBy(a.name) : l.sosSeenBy(a.name),
                style: TextStyle(
                    color: a.claimed ? skin.color.fgMuted : skin.color.link,
                    fontSize: skin.type.sizeBody,
                    height: 1.4),
              ),
            ),
          SizedBox(height: skin.space.step(4)),
        ],
        MmAction(
          key: const ValueKey<String>('sos-im-safe'),
          icon: Icons.check,
          label: l.sosImSafe,
          // "I'm safe" is the one stop that tells the mesh; it sends exactly
          // one [SAFE] and ends both loops (§7).
          onPressed: () => sos.iAmSafe(),
        ),
        SizedBox(height: skin.space.step(2)),
        Text(l.sosImSafeHint,
            style: TextStyle(
                color: skin.color.fgMuted, fontSize: skin.type.sizeSm)),
        SizedBox(height: skin.space.step(3)),
        // §8's `--cancel-->`: stop the repeats here without telling the mesh.
        // It is separate from "I'm safe" because the two say opposite things
        // to everyone listening, and only the user knows which is true.
        MmAction(
          key: const ValueKey<String>('sos-cancel'),
          icon: Icons.stop,
          label: l.sosStopRepeats,
          onPressed: () => sos.cancel(),
        ),
        SizedBox(height: skin.space.step(2)),
        Text(l.sosStopHint,
            style: TextStyle(
                color: skin.color.fgMuted, fontSize: skin.type.sizeSm)),
      ],
    );
  }
}

/// A finished alarm: what happened, and that the situation is not resolved.
class _Ended extends StatelessWidget {
  const _Ended({required this.sos, required this.l});

  final SosController sos;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final MmSkin skin = context.skin;
    final SosAckRow? seen = sos.stoppedBy;
    final List<SosAckRow> other = <SosAckRow>[
      for (final SosAckRow a in sos.acks)
        if (!identical(a, seen)) a,
    ];
    final String copy = switch (sos.state) {
      SosState.acknowledged => seen == null
          ? l.sosAcknowledgedHeading
          : (seen.claimed ? l.sosClaimedBy(seen.name) : l.sosSeenBy(seen.name)),
      SosState.cancelled => l.sosCancelled,
      _ => l.sosExpired,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        MmStatusPill(
          switch (sos.state) {
            SosState.acknowledged => l.sosAcknowledgedHeading,
            SosState.cancelled => l.sosCancelled,
            _ => l.sosExpired,
          },
          key: const ValueKey<String>('sos-ended-pill'),
          alert: sos.state == SosState.expired,
        ),
        SizedBox(height: skin.space.step(3)),
        Text(copy,
            key: const ValueKey<String>('sos-ended'),
            style: TextStyle(
                color: skin.color.fg,
                fontSize: skin.type.sizeBodyLg,
                height: 1.5)),
        SizedBox(height: skin.space.step(4)),
        // The headline already names the acknowledgement that stopped the
        // alarm, so the list below carries the others only. Repeating the same
        // sentence twice reads as two different people answering.
        if (other.isNotEmpty)
          for (final SosAckRow a in other)
            Padding(
              padding: EdgeInsets.only(bottom: skin.space.step(1)),
              child: Text(
                a.claimed ? l.sosClaimedBy(a.name) : l.sosSeenBy(a.name),
                style: TextStyle(
                    color: skin.color.fgMuted, fontSize: skin.type.sizeBody),
              ),
            ),
        if (other.isNotEmpty) SizedBox(height: skin.space.step(4)),
        MmAction(
          key: const ValueKey<String>('sos-dismiss'),
          label: l.sosDismiss,
          onPressed: () => sos.dismiss(),
        ),
      ],
    );
  }
}
