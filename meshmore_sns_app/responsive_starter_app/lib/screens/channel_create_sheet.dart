// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:meshcore/meshcore.dart';

import '../gen/app_localizations.dart';
import '../meshcore/meshcore_controller.dart';
import '../theme/mm_skin.dart';
import '../ui/mm_components.dart';
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

  @override
  State<ChannelCreateSheet> createState() => _ChannelCreateSheetState();
}

class _ChannelCreateSheetState extends State<ChannelCreateSheet> {
  final TextEditingController _name = TextEditingController();

  /// Who may read it. The default is the name-derived key, because that is the
  /// choice that cannot surprise anyone: the same name in the same place gives
  /// the same channel, and nothing else joins it.
  bool _publicKey = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// The first slot nothing is using, or null when every slot is taken.
  ///
  /// Taken from the same count the channels screen shows, so the two cannot
  /// disagree about how many slots the radio has: the controller's own probe
  /// walks `maxGroupChannels`, and that is what the list renders.
  int? get _slot {
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
    if (_publicKey) return List<int>.from(kPublicChannelPsk);
    final String raw = _name.text.trim();
    if (raw.isEmpty) return null;
    return MeshcoreChannelCrypto.channelPskFromHashtag(raw);
  }

  /// The name the radio will be told, which is the canonical form of what was
  /// typed. A channel whose name reads `basecamp` while its key is
  /// sha256("#basecamp") is a channel nobody can find again by typing the name
  /// they chose, so the `#` is stored rather than implied.
  String get _storedName {
    final String raw = _name.text.trim();
    if (_publicKey) return raw;
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
    final bool canCreate = ready && slot != null && !_busy;

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
                errorText: _error,
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
                        color: skin.color.alert, fontSize: skin.type.sizeSm)),
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
          ],
        ),
      ),
    );
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
