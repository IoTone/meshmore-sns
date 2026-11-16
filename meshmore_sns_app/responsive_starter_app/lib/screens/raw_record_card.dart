// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:meshcore/meshcore.dart';

import '../gen/app_localizations.dart';
import '../meshcore/failure.dart';
import '../meshcore/mesh_sender.dart';
import '../meshcore/meshcore_controller.dart';
import '../ui/mm_confirm.dart';
import '../meshcore/raw_record_input.dart';
import '../theme/mm_skin.dart';
import '../ui/mm_components.dart';

/// Sends one typed record to a contact as a direct raw-data packet.
///
/// This is the caller the retained raw-send capability was kept for
/// (`meshmore-scope-of-record.md` D10.1): `0x19` with the contact's path and
/// the record, answered by the radio's own OK or ERR rather than by a chat
/// row. It lives in the developer half of Diagnostics because the bytes are
/// opaque to the app: it composes the frame but cannot know what the record
/// means, so it asks before every send instead of guessing which bytes are
/// safe.
///
/// It is a record, not a frame. A "send arbitrary frame" tool would need a
/// command-byte field and could emit `CMD_FACTORY_RESET` or
/// `CMD_EXPORT_PRIVATE_KEY`; the firmware's command surface is reached through
/// the typed whitelist instead, and this tool composes only `0x19`.
class RawRecordCard extends StatefulWidget {
  const RawRecordCard({super.key, required this.mc, this.sender});

  final MeshcoreController mc;

  /// Injected by tests. Production builds one sender per card, which is also
  /// what serialises sends: the firmware's OK/ERR carries no correlation tag.
  final MeshcoreMeshSender? sender;

  @override
  State<RawRecordCard> createState() => _RawRecordCardState();
}

class _RawRecordCardState extends State<RawRecordCard> {
  final TextEditingController _hex = TextEditingController();
  late final MeshcoreMeshSender _sender;
  late final bool _ownsSender;

  /// The contact's public-key hex, so a contact list refresh does not silently
  /// retarget the send.
  String? _contactKey;

  SendOutcome? _outcome;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _ownsSender = widget.sender == null;
    _sender = widget.sender ?? MeshcoreMeshSender(widget.mc);
    _hex.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _hex.dispose();
    if (_ownsSender) _sender.dispose();
    super.dispose();
  }

  /// Contacts the radio holds with a direct route. A contact reachable only by
  /// flood cannot be addressed, and a raw record cannot be flooded.
  List<Contact> get _targets => <Contact>[
        for (final Contact c in widget.mc.syncedContacts)
          if (c.directPath != null) c,
      ]..sort((Contact a, Contact b) => a.name.compareTo(b.name));

  Contact? get _selected {
    final List<Contact> targets = _targets;
    if (targets.isEmpty) return null;
    final String? key = _contactKey;
    if (key != null) {
      for (final Contact c in targets) {
        if (_hexOf(c.publicKey) == key) return c;
      }
    }
    return targets.first;
  }

  RawRecordInput get _parsed => parseRawRecord(
        _hex.text,
        maxBytes: _selected == null
            ? MeshCarryLimits.maxFrameSize
            : MeshcoreMeshSender.recordMaxFor(_selected!),
      );

  Future<void> _confirmAndSend() async {
    final Contact? to = _selected;
    final RawRecordInput parsed = _parsed;
    if (to == null || !parsed.ok) return;
    final AppLocalizations l = AppLocalizations.of(context);
    final bool go = await mmConfirm(
      context,
      title: l.rawRecordConfirmTitle,
      body: l.rawRecordConfirmBody(_nameOf(l, to), '${parsed.length}'),
      cancelLabel: l.cancel,
      confirmLabel: l.diagnosticsSend,
    );
    if (!go || !mounted) return;
    setState(() {
      _busy = true;
      _outcome = null;
    });
    final SendOutcome out =
        await _sender.sendRecord(parsed.bytes!, to: to);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _outcome = out;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;
    // Everything that depends on the radio is read *inside* the listenable
    // builder. Reading it here would freeze the first frame's contact list and
    // ready state: a notify would repaint the captured values, and the card
    // would keep saying "no radio connected" after the link came up.
    return ListenableBuilder(
      listenable: widget.mc,
      builder: (BuildContext _, Widget? __) {
        final Contact? to = _selected;
        final List<Contact> targets = _targets;
        final RawRecordInput parsed = _parsed;
        final bool ready = widget.mc.isReady;
        final int budget = _budgetFor(to);
        final bool canSend = ready && to != null && parsed.ok && !_busy;
        return Padding(
          padding: EdgeInsets.fromLTRB(
              skin.space.screenEdge, 4, skin.space.screenEdge, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(l.rawRecordTitle,
                  style: TextStyle(
                      color: skin.color.fg,
                      fontSize: skin.type.sizeBodyLg,
                      fontWeight: FontWeight.w600)),
              SizedBox(height: skin.space.step(2)),
              Text(l.rawRecordHelp,
                  style: TextStyle(
                      color: skin.color.fgMuted,
                      fontSize: skin.type.sizeSm,
                      height: 1.35)),
              SizedBox(height: skin.space.step(3)),
              // The target. A contact with no direct route is not an empty
              // list: the state is named so it does not read as a load failure.
              if (targets.isEmpty)
                Text(l.rawRecordNoContact,
                    style: TextStyle(
                        color: skin.color.fgMuted,
                        fontSize: skin.type.sizeSm,
                        height: 1.35))
              else
                DropdownButton<String>(
                  value: _hexOf(to!.publicKey),
                  isExpanded: true,
                  items: <DropdownMenuItem<String>>[
                    for (final Contact c in targets)
                      DropdownMenuItem<String>(
                        value: _hexOf(c.publicKey),
                        child: Text(_nameOf(l, c)),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (String? v) => setState(() => _contactKey = v),
                ),
              SizedBox(height: skin.space.step(3)),
              TextField(
                controller: _hex,
                enabled: !_busy,
                keyboardType: TextInputType.text,
                style: TextStyle(
                    fontFamily: skin.type.monoFamily,
                    fontSize: skin.type.sizeBody),
                decoration: InputDecoration(
                  labelText: l.rawRecordBytes,
                  hintText: '01 02 ab cd',
                  errorText:
                      parsed.ok ? null : _refusalText(l, parsed.refusal!),
                ),
              ),
              SizedBox(height: skin.space.step(1)),
              // The two ceilings: the frame the radio accepts, and what this
              // contact's path leaves for the record.
              Text(
                l.rawRecordBudget('${MeshCarryLimits.maxFrameSize}',
                    '$budget', '${parsed.length}'),
                style: TextStyle(
                    color: skin.color.fgMuted, fontSize: skin.type.sizeSm),
              ),
              SizedBox(height: skin.space.step(3)),
              if (!ready)
                Text(l.rawRecordNotReady,
                    style: TextStyle(
                        color: skin.color.fgMuted,
                        fontSize: skin.type.sizeSm))
              else
                MmAction(
                  dense: true,
                  onPressed: canSend ? _confirmAndSend : null,
                  label: _busy ? l.rawRecordSending : l.diagnosticsSend,
                ),
              if (_outcome != null) ...<Widget>[
                SizedBox(height: skin.space.step(3)),
                Text(
                  _outcomeText(l, _outcome!, to),
                  key: const ValueKey<String>('raw-record-outcome'),
                  style: TextStyle(
                      color: _outcome!.kind == SendOutcomeKind.accepted
                          ? skin.color.fgMuted
                          : skin.color.alert,
                      fontSize: skin.type.sizeSm,
                      height: 1.35),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  String _refusalText(AppLocalizations l, RawRecordRefusal r) => switch (r) {
        RawRecordRefusal.empty => l.rawRecordEmpty,
        RawRecordRefusal.notHex => l.rawRecordNotHex,
        RawRecordRefusal.tooShort =>
          l.rawRecordTooShort('${MeshCarryLimits.rawDataMinPayload}'),
        RawRecordRefusal.tooLong => l.rawRecordTooLong('${_budgetFor(_selected)}'),
      };

  /// What the radio did, in the words a person needs.
  ///
  /// A refusal names the firmware's code and its meaning, because the codes
  /// are not interchangeable: capacity clears and a missing route does not.
  /// Accepted says what it is not — a receipt — because a raw record carries
  /// no acknowledgement from the peer.
  String _outcomeText(AppLocalizations l, SendOutcome o, Contact? to) =>
      switch (o.kind) {
        SendOutcomeKind.accepted => l.rawRecordSent,
        SendOutcomeKind.noRoute => l.rawRecordNoRoute(_nameOf(l, to)),
        SendOutcomeKind.refusedByRadio => l.rawRecordRefused(
            failureText(l, Failure.deviceError(o.firmwareCode)),
            '${o.firmwareCode ?? '?'}'),
        SendOutcomeKind.tooLong => l.rawRecordTooLong('${_budgetFor(to)}'),
        SendOutcomeKind.noAnswer =>
          l.rawRecordNoAnswer('${_sender.answerTimeout.inSeconds}'),
      };

  int _budgetFor(Contact? to) => to == null
      ? MeshCarryLimits.maxFrameSize
      : MeshcoreMeshSender.recordMaxFor(to);

  /// A contact the radio never named still needs a word in the sentence, and
  /// it has to be the app's word, not an English one baked into the source.
  String _nameOf(AppLocalizations l, Contact? c) =>
      c == null ? '' : (c.name.isEmpty ? l.dashboardUnnamed : c.name);

  static String _hexOf(List<int> b) =>
      b.map((int x) => x.toRadixString(16).padLeft(2, '0')).join();
}
