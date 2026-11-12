// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../gen/app_localizations.dart';
import '../meshcore/meshcore_controller.dart';
import '../sos/checkin.dart';
import '../sos/sos_controller.dart';
import '../sos/sos_message.dart';
import '../theme/mm_skin.dart';
import '../ui/mm_components.dart';
import '../ui/mm_scaffold.dart';

/// The check-in (`meshmore-sos-spec.md` §3, D8.5).
///
/// One bounded send with a deadline the app watches locally. The radio keeps
/// no timer and cannot know whether the message arrived, so the only thing
/// this surface may claim is that the deadline passed — never that nobody is
/// coming.
class CheckinScreen extends StatefulWidget {
  const CheckinScreen({super.key});

  /// D8.5's intervals: 15, 30 and 60 minutes.
  static const List<int> intervals = <int>[15, 30, 60];

  @override
  State<CheckinScreen> createState() => _CheckinScreenState();
}

class _CheckinScreenState extends State<CheckinScreen> {
  int _minutes = CheckinScreen.intervals.first;
  bool _sent = false;

  Future<void> _send(SosController sos) async {
    final CheckinState state =
        await sos.sendCheckin(within: Duration(minutes: _minutes));
    if (!mounted) return;
    setState(() => _sent = state != CheckinState.pending);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;
    final SosController sos = context.watch<SosController>();
    final bool ready = context.select<MeshcoreController, bool>(
        (MeshcoreController mc) => mc.isReady);
    final CheckinWatch? watch = sos.checkin;

    return Scaffold(
      appBar: AppBar(title: Text(l.checkinTitle)),
      body: MmScaffold(
        child: ListView(
          padding: EdgeInsets.fromLTRB(skin.space.rowInset, skin.space.rowGap,
              skin.space.rowInset, skin.space.emptyState),
          children: <Widget>[
            Text(l.checkinIntro,
                style: TextStyle(
                    color: skin.color.fgMuted,
                    fontSize: skin.type.sizeBody,
                    height: 1.5)),
            SizedBox(height: skin.space.step(4)),
            if (!ready || !sos.canArm)
              Text(l.checkinNeedsRadio,
                  key: const ValueKey<String>('checkin-needs-radio'),
                  style: TextStyle(
                      color: skin.color.alert, fontSize: skin.type.sizeBody)),
            if (watch == null) ...<Widget>[
              SizedBox(height: skin.space.step(3)),
              MmSectionHeader(l.checkinInMinutes(_minutes)),
              SizedBox(height: skin.space.step(2)),
              Wrap(
                spacing: skin.space.step(2),
                children: <Widget>[
                  for (final int m in CheckinScreen.intervals)
                    MmChoiceChip(
                      key: ValueKey<String>('checkin-interval-$m'),
                      label: Text(l.checkinInMinutes(m)),
                      selected: _minutes == m,
                      onSelected: (_) => setState(() => _minutes = m),
                    ),
                ],
              ),
              SizedBox(height: skin.space.step(4)),
              MmAction(
                key: const ValueKey<String>('checkin-send'),
                icon: Icons.schedule_send,
                label: l.checkinSend,
                onPressed: ready && sos.canArm ? () => _send(sos) : null,
              ),
              SizedBox(height: skin.space.step(3)),
              Text(l.checkinOneMessage,
                  style: TextStyle(
                      color: skin.color.fgMuted,
                      fontSize: skin.type.sizeSm)),
              if (_sent)
                Text(l.checkinSent,
                    key: const ValueKey<String>('checkin-sent'),
                    style: TextStyle(
                        color: skin.color.fgMuted,
                        fontSize: skin.type.sizeSm)),
            ] else ...<Widget>[
              SizedBox(height: skin.space.step(3)),
              _WatchRow(watch: watch, l: l),
            ],
          ],
        ),
      ),
    );
  }
}

/// The watch: the deadline, and the only three things it can say.
class _WatchRow extends StatelessWidget {
  const _WatchRow({required this.watch, required this.l});

  final CheckinWatch watch;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final MmSkin skin = context.skin;
    final String stamp = formatUntil(watch.checkin.until);
    final (String pill, String copy) = switch (watch.state) {
      CheckinState.pending => (l.checkinOneMessage, l.checkinOneMessage),
      CheckinState.watching => (l.checkinWatching, ''),
      CheckinState.overdue => (l.checkinOverdue, l.checkinOverdue),
      CheckinState.answered => switch (watch.answer) {
          CheckinAnswer.directKey =>
            (l.checkinAnsweredDirect, l.checkinAnsweredDirect),
          CheckinAnswer.claimedOnChannel =>
            (l.checkinAnsweredChannel, l.checkinAnsweredChannel),
          null => (l.checkinWatching, ''),
        },
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        MmStatusPill(pill,
            key: const ValueKey<String>('checkin-pill'),
            alert: watch.state == CheckinState.overdue),
        SizedBox(height: skin.space.step(3)),
        Text(l.checkinUntil(stamp),
            key: const ValueKey<String>('checkin-until'),
            style: TextStyle(
                color: skin.color.fg,
                fontSize: skin.type.sizeBodyLg,
                fontWeight: FontWeight.w600)),
        if (copy.isNotEmpty) ...<Widget>[
          SizedBox(height: skin.space.step(2)),
          Text(copy,
              key: const ValueKey<String>('checkin-state'),
              style: TextStyle(
                  color: skin.color.fg, fontSize: skin.type.sizeBody)),
        ],
        SizedBox(height: skin.space.step(2)),
        Text(l.checkinOneMessage,
            style:
                TextStyle(color: skin.color.fgMuted, fontSize: skin.type.sizeSm)),
      ],
    );
  }
}
