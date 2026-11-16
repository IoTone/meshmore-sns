// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:meshcore/meshcore.dart';

import '../gen/app_localizations.dart';
import '../meshcore/meshcore_controller.dart';
import '../theme/mm_skin.dart';
import '../ui/mm_collapse_controller.dart';
import '../ui/mm_collapsible.dart';
import '../ui/mm_components.dart';
import '../ui/mm_confirm.dart';
import '../ui/mm_shape.dart';

/// Making a channel, in the order a person thinks about it.
///
/// The screen that used to be the only way to make one is a list of numbered
/// slots with a "Set" button each, and the dialog behind that button asks for a
/// name and then for one of four key sources — Public, #tag, Hex, Shake. That is
/// the radio's model, not the reader's: "slot 3", "PSK", "#tag" and "Hex" are
/// four words a newcomer has no use for, and the *default* was Public, so naming
/// a channel and pressing save quietly produced a channel keyed with the
/// well-known public key, readable by every radio in range. A private-sounding
/// name over a public key is the worst possible default, and nothing on screen
/// said so.
///
/// This asks two things: what is it called, and who should be able to read it.
/// The key follows from the answer, and the slot is chosen — the first empty
/// one — because a slot number is the radio's business. The four-way key picker
/// still exists where it belongs: editing a slot on the channels screen, for a
/// reader who is deliberately pasting a key.
class ChannelCreateSheet extends StatefulWidget {
  const ChannelCreateSheet({super.key, required this.controller});

  final MeshcoreController controller;

  /// Shows the sheet; resolves true when a channel was written.
  static Future<bool?> show(BuildContext context,
          {required MeshcoreController controller}) =>
      showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => ChannelCreateSheet(controller: controller),
      );

  /// The firmware's channel-name limit, in bytes.
  ///
  /// `ChannelDetails::name` is `char name[32]` in the MeshCore firmware, so a
  /// longer name is silently truncated by the radio. That matters more than
  /// cosmetics: this sheet derives the key from the name, so deriving from a
  /// 40-character string while the radio stores 32 bytes gives two clients the
  /// same visible name and different keys — they simply cannot hear each other,
  /// with nothing on either screen to say why.
  static const int maxNameBytes = 32;

  /// The name as the radio will store it: capped at the firmware's 32 bytes,
  /// counted in UTF-8 bytes rather than characters so a multi-byte name is
  /// capped where the firmware caps it.
  static String capName(String raw) {
    final String trimmed = raw.trim();
    final List<int> bytes = utf8.encode(trimmed);
    if (bytes.length <= maxNameBytes) return trimmed;
    // Cut on a character boundary so a multi-byte rune is never halved.
    final StringBuffer out = StringBuffer();
    int used = 0;
    for (final int rune in trimmed.runes) {
      final int len = utf8.encode(String.fromCharCode(rune)).length;
      if (used + len > maxNameBytes) break;
      out.writeCharCode(rune);
      used += len;
    }
    return out.toString();
  }

  @override
  State<ChannelCreateSheet> createState() => _ChannelCreateSheetState();
}

class _ChannelCreateSheetState extends State<ChannelCreateSheet> {
  final TextEditingController _name = TextEditingController();

  /// The pasted or generated key field. Kept apart from `_hexKey` so the text and
  /// the parsed value cannot drift, and disposed with the sheet.
  final TextEditingController _hex = TextEditingController();

  /// Who may read it. The default is the name-derived key, because that is the
  /// choice that cannot surprise anyone: the same name in the same place gives
  /// the same channel, and nothing else joins it.
  bool _publicKey = false;
  bool _busy = false;
  String? _error;

  /// The advanced disclosure: everything the old slot dialog could do, folded
  /// away so the two-tap path stays two taps.
  final bool _advanced = false;


  /// A slot the reader picked, when they did. Null means "the first free one".
  int? _slotOverride;

  /// A pasted or generated 32-hex key. When set, it wins over the name-derived
  /// key: somebody pasting a key has the key, and deriving one from a name would
  /// silently replace it with a different channel.
  String? _hexKey;

  @override
  void dispose() {
    _name.dispose();
    _hex.dispose();
    super.dispose();
  }

  /// Pick a slot, showing which are in use.
  Future<int?> _pickSlot(BuildContext context, AppLocalizations l) async {
    final MeshcoreController mc = widget.controller;
    final int slots = mc.deviceInfo?.maxGroupChannels ?? 4;
    final Map<int, String> used = <int, String>{
      for (final MapEntry<int, String> e in mc.channels) e.key: e.value,
    };
    return showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext c) => SafeArea(
        top: false,
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            for (int i = 0; i < slots; i++)
              ListTile(
                key: ValueKey<String>('channel-create-slot-$i'),
                title: Text(l.channelCreateSlotNumber(i)),
                subtitle: Text(used[i] ?? l.channelsEmpty),
                trailing: i == _slot ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(c, i),
              ),
          ],
        ),
      ),
    );
  }

  /// The first slot nothing is using, or null when every slot is taken.
  ///
  /// Taken from the same count the channels screen shows, so the two cannot
  /// disagree about how many slots the radio has: the controller's own probe
  /// walks `maxGroupChannels`, and that is what the list renders.
  int? get _slot {
    if (_slotOverride != null) return _slotOverride;
    final MeshcoreController mc = widget.controller;
    final int slots = mc.deviceInfo?.maxGroupChannels ?? 4;
    final Set<int> used =
        mc.channels.map((MapEntry<int, String> e) => e.key).toSet();
    for (int i = 0; i < slots; i++) {
      if (!used.contains(i)) return i;
    }
    return null;
  }

  /// The key this channel will carry, once there is a name to derive it from.
  List<int>? get _psk {
    final String? hex = _hexKey?.trim();
    if (hex != null && hex.isNotEmpty) {
      if (hex.length != 32 || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex)) {
        return null;
      }
      return <int>[
        for (int i = 0; i < 32; i += 2)
          int.parse(hex.substring(i, i + 2), radix: 16),
      ];
    }
    if (_publicKey) return List<int>.from(kPublicChannelPsk);
    // Derived from the capped name, which is the one the radio will hold.
    final String raw = ChannelCreateSheet.capName(_name.text);
    if (raw.isEmpty) return null;
    return MeshcoreChannelCrypto.channelPskFromHashtag(raw);
  }

  /// Whether this name is already a channel on this radio.
  ///
  /// Compared in the same canonical form the key is derived from, so "basecamp"
  /// and "#basecamp" are one name rather than two. A second channel with the
  /// same name and the same derived key is not a second conversation: it is the
  /// same conversation with its messages split across two rows, and the reader
  /// has no way to tell which one they are reading.
  bool get _nameTaken {
    final String wanted = _storedName.toLowerCase();
    if (wanted.isEmpty) return false;
    for (final MapEntry<int, String> e in widget.controller.channels) {
      if (e.value.trim().toLowerCase() == wanted) return true;
    }
    return false;
  }

  /// The name the radio will be told, which is the canonical form of what was
  /// typed. A channel whose name reads `basecamp` while its key is
  /// sha256("#basecamp") is a channel nobody can find again by typing the name
  /// they chose, so the `#` is stored rather than implied.
  String get _storedName {
    final String raw = ChannelCreateSheet.capName(_name.text);
    // A name only gets a '#' when the key is derived from it.
    if (_publicKey) return raw;
    if ((_hexKey ?? '').trim().isNotEmpty) return raw;
    return MeshcoreChannelCrypto.canonicalHashtag(raw);
  }

  Future<void> _create() async {
    final AppLocalizations l = AppLocalizations.of(context);
    setState(() => _error = null);
    final int? slot = _slot;
    if (slot == null) {
      setState(() => _error = l.channelCreateNoSlot);
      return;
    }
    final String name = _storedName;
    if (name.isEmpty || name == '#') {
      setState(() => _error = l.channelsErrorName);
      return;
    }
    if (_nameTaken) {
      setState(() => _error = l.channelCreateExists(name));
      return;
    }
    final List<int>? psk = _psk;
    if (psk == null) {
      setState(() => _error = l.channelsErrorName);
      return;
    }
    // The name field is autofocused, so the keyboard is up over the thread the
    // reader is about to be dropped into. Half a screen of keyboard with nothing
    // focused behind it is the state the handset showed after this sheet closed.
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    await widget.controller.setChannel(idx: slot, name: name, psk: psk);
    // Made active as well as made: a reader who just created a channel is about
    // to write in it, and being returned to the thread of a different channel is
    // how a message ends up somewhere nobody expected.
    widget.controller.setActiveChannel(slot);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;
    final int? slot = _slot;
    final bool ready =
        widget.controller.state == MeshcoreConnectionState.ready;
    // The refusal is shown as the field's own error before the tap, so the
    // button never looks broken: a name already in the list is a correction to
    // make, not a failure to explain afterwards.
    final String? fieldError = _error ??
        (_nameTaken ? l.channelCreateExists(_storedName) : null);
    final bool canCreate =
        ready && slot != null && !_busy && !_nameTaken;

    return Padding(
      // The keyboard: this sheet's whole job is a text field.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: ListView(
          key: const ValueKey<String>('channel-create-sheet'),
          shrinkWrap: true,
          padding: EdgeInsets.fromLTRB(skin.space.step(4), 0, skin.space.step(4),
              skin.space.step(3)),
          children: <Widget>[
            Text(l.channelCreateTitle,
                style: TextStyle(
                    color: skin.color.fg,
                    fontSize: skin.type.sizeLg,
                    fontWeight: FontWeight.w600)),
            SizedBox(height: skin.space.step(1)),
            Text(l.channelCreateIntro,
                style: TextStyle(
                    color: skin.color.fgMuted, fontSize: skin.type.sizeSm)),
            SizedBox(height: skin.space.step(4)),
            TextField(
              key: const ValueKey<String>('channel-create-name'),
              controller: _name,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => canCreate ? _create() : null,
              decoration: InputDecoration(
                labelText: l.channelsName,
                hintText: l.channelCreateNameHint,
                isDense: true,
                errorText: fieldError,
              ),
            ),
            SizedBox(height: skin.space.step(3)),
            // The two answers as one question. Each says what follows from it,
            // because "Public" and "#tag" are the radio's words and a reader
            // choosing between them needs the consequence, not the mechanism.
            _KeyChoice(
              key: const ValueKey<String>('channel-create-open'),
              selected: !_publicKey,
              title: l.channelCreateNameKeyedTitle,
              body: l.channelCreateNameKeyedBody,
              onTap: () => setState(() => _publicKey = false),
            ),
            SizedBox(height: skin.space.step(2)),
            _KeyChoice(
              key: const ValueKey<String>('channel-create-public'),
              selected: _publicKey,
              title: l.channelCreatePublicTitle,
              body: l.channelCreatePublicBody,
              onTap: () => setState(() => _publicKey = true),
            ),
            SizedBox(height: skin.space.step(3)),
            // Everything the old slot dialog could do, one tap down. The simple
            // path above stays two taps: a name, and who may read it.
            MmCollapsibleSection(
              id: MmGroupIds.channelAdvanced,
              title: l.channelCreateAdvanced,
              initiallyExpanded: _advanced,
              children: <Widget>[
                // Slot.
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: skin.space.step(2)),
                  child: MmPickerTile(
                    key: const ValueKey<String>('channel-create-slot-pick'),
                    title: l.channelCreateSlotTile,
                    value: slot == null ? '—' : '$slot',
                    hint: l.channelCreateSlotHint,
                    onTap: () async {
                      final int? picked = await _pickSlot(context, l);
                      // The sheet can be dismissed while the picker is up.
                      if (!mounted) return;
                      if (picked != null) {
                        setState(() => _slotOverride = picked);
                      }
                    },
                  ),
                ),
                SizedBox(height: skin.space.step(2)),
                // A pasted or generated key.
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: skin.space.step(2)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      TextField(
                        key: const ValueKey<String>('channel-create-hex'),
                        controller: _hex,
                        maxLines: 1,
                        style: TextStyle(
                            color: skin.color.fg,
                            fontSize: skin.type.sizeBody,
                            fontFamily: skin.type.monoFamily),
                        decoration: InputDecoration(
                          labelText: l.channelCreateKeyLabel,
                          hintText: l.channelCreateKeyHint,
                          isDense: true,
                        ),
                        onChanged: (String v) =>
                            setState(() => _hexKey = v.trim()),
                      ),
                      SizedBox(height: skin.space.step(1)),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              l.channelCreateKeyHelp,
                              style: TextStyle(
                                  color: skin.color.fgMuted,
                                  fontSize: skin.type.sizeSm),
                            ),
                          ),
                          MmAction(
                            key: const ValueKey<String>(
                                'channel-create-key-random'),
                            label: l.channelCreateKeyRandom,
                            dense: true,
                            onPressed: () {
                              // `Random.secure()` is the platform's own entropy;
                              // the old "shake" mode collected accelerometer
                              // noise for the same result and needed a hand.
                              final math.Random r = math.Random.secure();
                              final String hex = <int>[
                                for (int i = 0; i < 16; i++) r.nextInt(256),
                              ]
                                  .map((int b) =>
                                      b.toRadixString(16).padLeft(2, '0'))
                                  .join();
                              setState(() => _hexKey = hex);
                              _hex.text = hex;
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: skin.space.step(3)),
            // Where it will live, said plainly rather than as a number to choose.
            Text(
              slot == null
                  ? l.channelCreateNoSlot
                  : l.channelCreateSlotNote(slot),
              key: const ValueKey<String>('channel-create-slot'),
              style: TextStyle(
                  color: skin.color.fgMuted, fontSize: skin.type.sizeSm),
            ),
            if (!ready)
              Padding(
                padding: EdgeInsets.only(top: skin.space.step(2)),
                child: Text(l.channelsOfflineHint,
                    style: TextStyle(
                        color: skin.color.alertInk, fontSize: skin.type.sizeSm)),
              ),
            SizedBox(height: skin.space.step(4)),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                MmAction(
                  key: const ValueKey<String>('channel-create-cancel'),
                  label: l.actionCancel,
                  onPressed: () {
                    FocusScope.of(context).unfocus();
                    Navigator.pop(context, false);
                  },
                ),
                SizedBox(width: skin.space.step(2)),
                MmAction(
                  key: const ValueKey<String>('channel-create-save'),
                  label: l.channelCreateAction,
                  onPressed: canCreate ? _create : null,
                ),
              ],
            ),
            // Removing a channel belongs in the same menu as adding one: a
            // reader who wants to get rid of a channel should not have to find
            // the slot's editor first, and "add" and "remove" are the two
            // halves of one question.
            if (widget.controller.channels.isNotEmpty) ...<Widget>[
              SizedBox(height: skin.space.step(4)),
              MmSectionHeader(l.channelRemoveSection),
              SizedBox(height: skin.space.rowGap),
              Text(l.channelRemoveBody,
                  style: TextStyle(
                      color: skin.color.fgMuted,
                      fontSize: skin.type.sizeSm)),
              SizedBox(height: skin.space.step(2)),
              for (final MapEntry<int, String> e
                  in widget.controller.channels)
                Padding(
                  padding: EdgeInsets.only(bottom: skin.space.step(1)),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          '${e.value}  ·  ${l.channelsSlotLabel(e.key)}',
                          style: TextStyle(
                              color: skin.color.fg,
                              fontSize: skin.type.sizeBody),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      MmAction(
                        key: ValueKey<String>('channel-remove-${e.key}'),
                        label: l.channelRemoveAction,
                        dense: true,
                        onPressed: ready ? () => _remove(context, e.key) : null,
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// Removes one configured channel, after the same confirmation the slot
  /// editor uses.
  Future<void> _remove(BuildContext context, int idx) async {
    final AppLocalizations l = AppLocalizations.of(context);
    final bool ok = await mmConfirm(
      context,
      title: l.channelsClearConfirmTitle(idx),
      body: l.channelsClearConfirmBody,
      cancelLabel: l.channelsCancel,
      confirmLabel: l.channelRemoveAction,
      destructive: true,
    );
    if (!ok || !mounted) return;
    await widget.controller.clearChannel(idx);
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(this.context)
      ?..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(l.channelsClearSnack(idx))));
    setState(() {});
  }
}

/// One answer to "who should be able to read it".
class _KeyChoice extends StatelessWidget {
  const _KeyChoice({
    super.key,
    required this.selected,
    required this.title,
    required this.body,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final MmSkin skin = context.skin;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(kRadiusMd),
        child: Container(
          padding: EdgeInsets.all(skin.space.step(3)),
          decoration: BoxDecoration(
            // The fill states the selection; the boundary is always drawn, so an
            // unselected answer still reads as something you can press.
            color: selected
                ? skin.color.accent.withValues(alpha: .12)
                : skin.color.surface,
            borderRadius: BorderRadius.circular(kRadiusMd),
            border: Border.all(
                color: selected ? skin.color.accent : skin.color.hairline,
                width: selected ? 2 : 1),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 20,
                color: selected ? skin.color.accent : skin.color.fgMuted,
              ),
              SizedBox(width: skin.space.step(2)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title,
                        style: TextStyle(
                            color: skin.color.fg,
                            fontSize: skin.type.sizeBody,
                            fontWeight: FontWeight.w600)),
                    SizedBox(height: skin.space.step(1)),
                    Text(body,
                        style: TextStyle(
                            color: skin.color.fgMuted,
                            fontSize: skin.type.sizeSm,
                            height: 1.3)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
