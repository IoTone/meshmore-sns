// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../gen/app_localizations.dart';
import '../meshcore/discovered_node.dart';
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
    // The field is a default, not a form: clearing it means "send the default
    // words", not "send nothing". The engine still refuses an alarm with no
    // words from any other caller (`SosRefusal.noWords`), so the wire always
    // carries a sentence.
    final String typed = _words.text.trim();
    final SosRefusal? refused =
        c.arm(words: typed.isEmpty ? l.sosDefaultWords : typed);
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

  /// Opens the destination picker. The controller saves the choice, so the
  /// next launch starts where this one left off.
  Future<void> _openDestinationPicker(
    BuildContext context,
    SosController sos,
    MeshcoreController mc,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _DestinationPicker(sos: sos, mc: mc),
    );
  }

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
      // One control on this screen raises an alarm, and the app bar carries
      // nothing beside the title: a clock-shaped action here read as a second
      // way to send (owner, 2026-11-05). Check-in is in Settings -> Tools, so
      // it is still reachable without being met while raising an alarm.
      appBar: AppBar(title: Text(l.sosTitle)),
      body: MmScaffold(
        child: ListView(
          padding: EdgeInsets.fromLTRB(skin.space.rowInset, skin.space.rowGap,
              skin.space.rowInset, skin.space.emptyState),
          children: <Widget>[
            if (ended)
              _Ended(sos: sos, l: l)
            else ...<Widget>[
              // Configure first, then hold. UX audit E1/E2 put the control at
              // the top so the eye landed on the alarm; the owner reversed
              // that on 2026-11-05, because the rows above the hold are what
              // make it clear they can be changed before it is held. Do not
              // move the hold back above them.
              //
              // Where it goes, one row, one tap to change it.
              _DestinationRow(
                sos: sos,
                l: l,
                // A running alarm is a snapshot: it keeps repeating on the
                // targets it raised with, so the row must not offer to change
                // them mid-run and then describe a destination the repeats are
                // not using.
                onTap: sos.isRunning
                    ? null
                    : () => _openDestinationPicker(context, sos, mc),
              ),
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
                SizedBox(height: skin.space.step(1)),
                Text(l.sosWordsOptional,
                    key: const ValueKey<String>('sos-words-optional'),
                    style: TextStyle(
                        color: skin.color.fgMuted,
                        fontSize: skin.type.sizeSm)),
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
                // One line above the hold: what will be sent and where. The
                // hold raises whatever the two rows above it currently say.
                Text(l.sosHoldSummary(sos.channelName),
                    key: const ValueKey<String>('sos-hold-summary'),
                    style: TextStyle(
                        color: skin.color.fgMuted,
                        fontSize: skin.type.sizeSm,
                        height: 1.4)),
                SizedBox(height: skin.space.step(2)),
                _holdControl(context, sos, l, skin, mc.isReady),
                if (_note != null) ...<Widget>[
                  SizedBox(height: skin.space.step(3)),
                  Text(_note!,
                      key: const ValueKey<String>('sos-note'),
                      style: TextStyle(
                          color: skin.color.alert,
                          fontSize: skin.type.sizeBody)),
                ],
                SizedBox(height: skin.space.step(4)),
              ],
              _AboutLines(sos: sos, l: l),
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
    // an empty closure, so the alarm was reachable by finger only (UX audit E3).
    // Both semantic actions run the same three-second hold the finger runs, and
    // the recogniser below is excluded from semantics: it turns a semantic tap
    // into a down and an up in the same frame, which would arm and then abort
    // the alarm a moment after raising it.
    return Semantics(
      button: true,
      enabled: enabled,
      label: l.sosHoldToArm,
      onTap: enabled ? () => _beginHold(sos, l) : null,
      onLongPress: enabled ? () => _beginHold(sos, l) : null,
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

/// Where the alarm goes: one row, one line, one tap to change it.
///
/// §10 items 2 and 3 are the title and the subtitle. A channel and a direct
/// copy guarantee different things, and the row states both: the channel the
/// alarm is heard on, and how many keyed copies it carries.
class _DestinationRow extends StatelessWidget {
  const _DestinationRow({
    required this.sos,
    required this.l,
    required this.onTap,
  });

  final SosController sos;
  final AppLocalizations l;

  /// Null while an alarm is running: the row then states where the repeats are
  /// going and offers nothing to change, because they cannot be changed.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final MmSkin skin = context.skin;
    final bool missing = sos.destinationMissing;
    final int copies = sos.contactKeysHex.length;
    final String sub = missing
        ? l.sosDestinationMissing
        : '${l.sosGoesToContacts(copies)} · ${l.sosRepeatsShort}';
    return Semantics(
      button: onTap != null,
      label: '${l.sosDestination}: ${l.sosGoesToChannel(sos.channelName)}. $sub',
      child: InkWell(
        key: const ValueKey<String>('sos-destination-row'),
        onTap: onTap,
        borderRadius: mmRadius(context, kRadiusSm),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: skin.space.step(2)),
          child: Row(
            children: <Widget>[
              Icon(
                missing ? Icons.error_outline : Icons.campaign_outlined,
                size: skin.type.sizeLg,
                color: missing ? skin.color.alert : skin.color.fgMuted,
              ),
              SizedBox(width: skin.space.step(3)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      l.sosGoesToChannel(sos.channelName),
                      style: TextStyle(
                        color: skin.color.fg,
                        fontSize: skin.type.sizeBodyLg,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: skin.space.step(1)),
                    Text(
                      sub,
                      style: TextStyle(
                        color: missing
                            ? skin.color.alert
                            : skin.color.fgMuted,
                        fontSize: skin.type.sizeSm,
                      ),
                    ),
                  ],
                ),
              ),
              if (onTap != null) ...<Widget>[
                SizedBox(width: skin.space.step(3)),
                Text(
                  l.sosDestinationChange,
                  style: TextStyle(
                    color: skin.color.fgMuted,
                    fontSize: skin.type.sizeSm,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The consequences, one line each, with the long explanation behind the info
/// affordance. APP-H5 needs the fact stated, not recited on every visit.
class _AboutLines extends StatelessWidget {
  const _AboutLines({required this.sos, required this.l});

  final SosController sos;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final MmSkin skin = context.skin;
    final TextStyle muted =
        TextStyle(color: skin.color.fgMuted, fontSize: skin.type.sizeSm);
    final bool emergency = sos.emergencyChannelSlot != null &&
        sos.channelSlot == sos.emergencyChannelSlot;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (sos.contactKeysHex.isEmpty)
          Padding(
            padding: EdgeInsets.only(bottom: skin.space.step(2)),
            child: Text(
              l.sosContactsNone,
              key: const ValueKey<String>('sos-no-copies'),
              style: muted,
            ),
          ),
        if (emergency)
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  l.sosEmergencyShort,
                  key: const ValueKey<String>('sos-emergency-key'),
                  style: muted,
                ),
              ),
              IconButton(
                key: const ValueKey<String>('sos-about'),
                tooltip: l.sosAboutTitle,
                iconSize: skin.type.sizeLg,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                icon: Icon(Icons.info_outline, color: skin.color.fgMuted),
                onPressed: () => _showAbout(context),
              ),
            ],
          ),
        Text(l.sosInRange, style: muted),
      ],
    );
  }

  void _showAbout(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(l.sosAboutTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(l.sosEmergencyPublicKey),
            const SizedBox(height: 12),
            Text(l.sosEmergencyRepeat),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(MaterialLocalizations.of(ctx).closeButtonLabel),
          ),
        ],
      ),
    );
  }
}

/// The sheet that picks the destination: the radio's channels, and up to four
/// contacts that also get a direct copy.
///
/// It writes through [SosController.setDestination], which persists the
/// choice, so this is the one place a destination is ever chosen.
class _DestinationPicker extends StatefulWidget {
  const _DestinationPicker({required this.sos, required this.mc});

  final SosController sos;
  final MeshcoreController mc;

  @override
  State<_DestinationPicker> createState() => _DestinationPickerState();
}

class _DestinationPickerState extends State<_DestinationPicker> {
  late int _slot = widget.sos.channelSlot;
  late final List<String> _keys =
      List<String>.of(widget.sos.contactKeysHex);

  void _toggle(String keyHex) {
    setState(() {
      if (_keys.contains(keyHex)) {
        _keys.remove(keyHex);
      } else if (_keys.length < SosTargets.maxContactTargets) {
        _keys.add(keyHex);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;
    final Set<String> contacts = <String>{
      for (final DiscoveredNode n in widget.mc.nodes)
        if (n.type == 1) n.pubKeyHex.toLowerCase(),
    };
    final TextStyle rowStyle =
        TextStyle(color: skin.color.fg, fontSize: skin.type.sizeBody);
    final TextStyle muted =
        TextStyle(color: skin.color.fgMuted, fontSize: skin.type.sizeSm);
    final List<String> orphans = <String>[
      for (final String hex in _keys)
        if (!contacts.contains(hex)) hex,
    ];
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          skin.space.step(5),
          skin.space.step(4),
          skin.space.step(5),
          skin.space.step(5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              l.sosDestinationPickerTitle,
              style: TextStyle(
                color: skin.color.fg,
                fontSize: skin.type.sizeLg,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (widget.sos.destinationMissing) ...<Widget>[
              SizedBox(height: skin.space.step(2)),
              Text(
                l.sosDestinationMissing,
                key: const ValueKey<String>('sos-destination-missing'),
                style:
                    TextStyle(color: skin.color.alert, fontSize: skin.type.sizeSm),
              ),
            ],
            SizedBox(height: skin.space.step(3)),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(l.sosDestinationChannelHeader, style: muted),
                    for (final MapEntry<int, String> c in widget.mc.channels)
                      ListTile(
                        key: ValueKey<String>('sos-destination-channel-${c.key}'),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(c.value, style: rowStyle),
                        trailing: _slot == c.key
                            ? Icon(Icons.check,
                                size: skin.type.sizeLg, color: skin.color.link)
                            : null,
                        selected: _slot == c.key,
                        onTap: () => setState(() => _slot = c.key),
                      ),
                    SizedBox(height: skin.space.step(3)),
                    Text(l.sosDestinationContactsHeader, style: muted),
                    Text(l.sosDestinationContactsHelp, style: muted),
                    if (widget.mc.nodes.where((DiscoveredNode n) => n.type == 1).isEmpty)
                      Padding(
                        padding: EdgeInsets.only(top: skin.space.step(2)),
                        child: Text(l.sosDestinationNoContacts, style: muted),
                      ),
                    for (final DiscoveredNode n in widget.mc.nodes)
                      if (n.type == 1)
                        CheckboxListTile(
                          key: ValueKey<String>(
                              'sos-destination-contact-${n.pubKeyHex.toLowerCase()}'),
                          value: _keys.contains(n.pubKeyHex.toLowerCase()),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(n.name, style: rowStyle),
                          subtitle: Text(
                              l.sosDestinationContactsLimit(
                                  SosTargets.maxContactTargets),
                              style: muted),
                          onChanged: (_) => _toggle(n.pubKeyHex.toLowerCase()),
                        ),
                    // A saved key that is no longer a contact is still a
                    // destination the alarm addresses: it stays visible so it
                    // can be removed deliberately, never dropped in silence.
                    for (final String hex in orphans)
                      CheckboxListTile(
                        key: ValueKey<String>('sos-destination-contact-$hex'),
                        value: true,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(hex.substring(0, 8), style: rowStyle),
                        subtitle:
                            Text(l.sosDestinationNotAContact, style: muted),
                        onChanged: (_) => _toggle(hex),
                      ),
                  ],
                ),
              ),
            ),
            SizedBox(height: skin.space.step(3)),
            Wrap(
              spacing: skin.space.step(3),
              runSpacing: skin.space.step(2),
              alignment: WrapAlignment.end,
              children: <Widget>[
                // Back to what a first launch would have chosen: the
                // emergency channel when the radio lists one, the active
                // channel otherwise, and no direct copies. The alarm already
                // works without this being touched; this is how a user undoes
                // a choice without hunting for the original.
                MmAction(
                  key: const ValueKey<String>('sos-destination-defaults'),
                  icon: Icons.settings_backup_restore,
                  label: l.sosUseDefaults,
                  onPressed: () {
                    widget.sos.setDestination(
                      channelSlot: widget.sos.emergencyChannelSlot ??
                          widget.mc.activeChannel,
                      contactKeysHex: const <String>[],
                    );
                    Navigator.of(context).pop();
                  },
                ),
                FilledButton(
                  key: const ValueKey<String>('sos-destination-done'),
                  onPressed: () {
                    widget.sos.setDestination(
                      channelSlot: _slot,
                      contactKeysHex: _keys,
                    );
                    Navigator.of(context).pop();
                  },
                  child: Text(l.sosDestinationDone),
                ),
              ],
            ),
          ],
        ),
      ),
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
        // L3: a one-second timer is not an alarm clock. Under Doze the OS
        // defers it, and the panel says what that costs rather than implying
        // a punctual schedule the app cannot keep.
        SizedBox(height: skin.space.step(2)),
        Text(l.sosBestEffort,
            key: const ValueKey<String>('sos-best-effort'),
            style: TextStyle(
                color: skin.color.fgMuted, fontSize: skin.type.sizeSm, height: 1.5)),
        if (sos.resumedFromRestart) ...<Widget>[
          SizedBox(height: skin.space.step(2)),
          Text(l.sosResumed,
              key: const ValueKey<String>('sos-resumed'),
              style: TextStyle(
                  color: skin.color.fgMuted,
                  fontSize: skin.type.sizeSm,
                  height: 1.5)),
        ],
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
        if (sos.unconfirmedSends > 0) ...<Widget>[
          SizedBox(height: skin.space.step(2)),
          Text(l.sosSendUnconfirmed(sos.unconfirmedSends),
              key: const ValueKey<String>('sos-send-unconfirmed'),
              style: TextStyle(
                  color: skin.color.fgMuted, fontSize: skin.type.sizeSm)),
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
        // SOS-3: a stop that never left the phone must not read like one that
        // reached the mesh. Only the "I'm safe" path tells anyone, so only it
        // carries this line; a silent stop says nothing was sent.
        if (sos.safeSent != null || sos.safeUnconfirmed) ...<Widget>[
          SizedBox(height: skin.space.step(3)),
          Text(
            sos.safeUnconfirmed
                ? l.sosSafeUnconfirmed
                : (sos.safeSent! ? l.sosSafeSent : l.sosSafeNotSent),
            key: const ValueKey<String>('sos-safe-outcome'),
            style: TextStyle(
                color: sos.safeSent == true && !sos.safeUnconfirmed
                    ? skin.color.fgMuted
                    : skin.color.alert,
                fontSize: skin.type.sizeBody,
                height: 1.5),
          ),
        ],
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
