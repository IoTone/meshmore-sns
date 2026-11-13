// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:meshcore/meshcore.dart';
import 'package:provider/provider.dart';

import '../bot/bot_scope.dart';
import '../bot/bot_section.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../cryptokit/dice_roll_entropy.dart';
import '../gen/app_localizations.dart';
import '../meshcore/meshcore_controller.dart';
import '../notifications/channel_notification_prefs.dart';
import '../ui/mm_scaffold.dart';
import '../theme/mm_skin.dart';
import '../ui/mm_components.dart';
import '../theme/theme_controller.dart';
import '../ui/mm_shape.dart';
import '../ui/mm_confirm.dart';

/// Channel management (R6): list the device's channel slots, set the
/// active one, and create/overwrite a slot's name + PSK. A channel is
/// a slot (index) + name + 16-byte pre-shared key; **every node must
/// use the same name & PSK in the same slot** to talk. PSK sources:
/// the well-known Public key, a `#hashtag` (deterministic), or raw
/// hex.
class ChannelsScreen extends StatelessWidget {
  const ChannelsScreen({super.key});

  /// How many slots to expose: what the radio says it has.
  ///
  /// This was a hardcoded 4, which is what the smallest boards hold — so a
  /// radio with 8 or 40 slots showed four and the rest were unreachable from
  /// the only screen that writes them. `DEVICE_INFO` reports the count
  /// (`max_group_channels`), and the controller's own probe walks exactly that
  /// many, so the screen follows the same number instead of guessing. Before
  /// the radio has answered, four is the honest floor: a board that reports
  /// fewer than that still gets its own count back from the probe.
  static const int _slotsBeforeDeviceInfo = 4;

  @override
  Widget build(BuildContext context) {
    final MeshcoreController mc = context.watch<MeshcoreController>();
    final ColorScheme cs = Theme.of(context).colorScheme;
    final AppLocalizations l = AppLocalizations.of(context);
    final bool ready = mc.state == MeshcoreConnectionState.ready;
    final Map<int, String> known = <int, String>{
      for (final MapEntry<int, String> e in mc.channels) e.key: e.value,
    };
    // The radio's own slot count, falling back to the smallest board's four
    // until it has answered. Never fewer than the channels already known: a
    // channel that exists must stay reachable even if the count disagrees.
    final int reportedSlots =
        mc.deviceInfo?.maxGroupChannels ?? _slotsBeforeDeviceInfo;
    // The highest slot the radio has named, plus one: a channel that exists
    // must stay reachable even when the reported count is smaller than the
    // index it lives at.
    final int knownExtent = known.isEmpty
        ? 0
        : known.keys.reduce((int a, int b) => a > b ? a : b) + 1;
    final int slots = reportedSlots < knownExtent ? knownExtent : reportedSlots;

    Future<void> edit(int idx) async {
      final _ChannelEdit? r = await showDialog<_ChannelEdit>(
        context: context,
        builder: (BuildContext _) => _EditChannelDialog(
            idx: idx,
            initialName: known[idx] ?? '',
            currentPsk: mc.channelPsk(idx)),
      );
      if (r == null) return;
      if (!context.mounted) return;
      // Clear-slot sentinel — the dialog already showed its own
      // confirm; we just need to call the controller + snack.
      if (r.name == '__clear__') {
        await mc.clearChannel(idx);
        if (context.mounted) {
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(SnackBar(content: Text(l.channelsClearSnack(idx))));
        }
        return;
      }
      // Slot-0 overwrite warning. Writing a non-Public PSK to slot 0
      // means we lose the shared Public channel — surface that as an
      // explicit confirm rather than letting it happen silently.
      if (idx == 0 && !_pskMatchesPublic(r.psk)) {
        final bool proceed = await mmConfirm(
          context,
          title: l.channelsSlot0WarnTitle,
          body: l.channelsSlot0WarnBody,
          cancelLabel: l.channelsSlot0WarnCancel,
          confirmLabel: l.channelsSlot0WarnContinue,
          // Overwriting slot 0 changes what every node on the public channel
          // hears, and the old key is not recoverable from the radio.
          destructive: true,
        );
        if (!proceed) return;
      }
      await mc.setChannel(idx: r.idx, name: r.name, psk: r.psk);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(l.channelsSetSnack(idx))));
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l.channelsTitle),
        actions: <Widget>[
          IconButton(
            key: const ValueKey<String>('channels-info'),
            tooltip: l.channelsInfoTooltip,
            icon: const Icon(Icons.help_outline),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (BuildContext ctx) => AlertDialog(
                title: Text(l.channelsTitle),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(l.channelsHelp,
                        style: TextStyle(
                            fontSize: context.skin.type.sizeBody,
                            height: 1.35)),
                    const SizedBox(height: 8),
                    Text(l.channelsHelpEncryption,
                        style: TextStyle(
                            fontSize: context.skin.type.sizeBody,
                            height: 1.35)),
                  ],
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(l.actionCancel),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: MmScaffold(
        child: ListView(
          children: <Widget>[
            if (!ready)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(l.channelsOfflineHint,
                    style: TextStyle(color: cs.error)),
              ),
            const Divider(height: 1),
            for (int idx = 0; idx < slots; idx++)
              ListTile(
                leading: Icon(
                  idx == mc.activeChannel
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: idx == mc.activeChannel
                      ? cs.primary
                      : cs.onSurfaceVariant,
                ),
                title: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(known[idx] ?? l.channelsEmpty,
                          style: TextStyle(
                              color: known.containsKey(idx)
                                  ? cs.onSurface
                                  : cs.onSurfaceVariant)),
                    ),
                    if (mc.isDefaultChannel(idx))
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          // A badge's border is a shape, so it is drawn at
                          // full strength: at 55 % it is 1.9:1 on paper and the
                          // badge loses its edge exactly where the ground is
                          // lightest.
                          color: cs.tertiary.withValues(alpha: .15),
                          borderRadius: BorderRadius.circular(kRadiusMd),
                          border: Border.all(color: cs.tertiary),
                        ),
                        child: Text(l.channelsDefaultBadge,
                            style: TextStyle(
                                color: cs.tertiary,
                                fontSize: context.skin.type.sizeMicro,
                                letterSpacing: 1.5)),
                      ),
                  ],
                ),
                subtitle: Text(idx == mc.activeChannel
                    ? l.channelsSlotActive(idx)
                    : l.channelsSlotLabel(idx)),
                onTap: known.containsKey(idx)
                    ? () => mc.setActiveChannel(idx)
                    : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (known.containsKey(idx))
                      IconButton(
                        tooltip: mc.isDefaultChannel(idx)
                            ? l.channelsClearDefaultTooltip
                            : l.channelsSetDefaultTooltip,
                        icon: Icon(
                            mc.isDefaultChannel(idx)
                                ? Icons.star
                                : Icons.star_border,
                            size: 20,
                            color: mc.isDefaultChannel(idx)
                                ? cs.tertiary
                                : cs.onSurfaceVariant),
                        onPressed: () async {
                          if (mc.isDefaultChannel(idx)) {
                            await mc.setDefaultChannelIdx(null);
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context)
                              ..clearSnackBars()
                              ..showSnackBar(SnackBar(
                                  content:
                                      Text(l.channelsClearedDefaultSnack)));
                          } else {
                            await mc.setDefaultChannelIdx(idx);
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context)
                              ..clearSnackBars()
                              ..showSnackBar(SnackBar(
                                  content:
                                      Text(l.channelsSetDefaultSnack(idx))));
                          }
                        },
                      ),
                    if (known.containsKey(idx))
                      IconButton(
                        key: ValueKey<String>('channel-options-$idx'),
                        tooltip: l.channelsOptionsTooltip,
                        icon: const Icon(Icons.tune, size: 20),
                        onPressed: () => showModalBottomSheet<void>(
                          context: context,
                          showDragHandle: true,
                          isScrollControlled: true,
                          builder: (BuildContext _) => _ChannelOptionsSheet(
                              idx: idx, name: known[idx] ?? l.channelsEmpty),
                        ),
                      ),
                    MmAction(
                      dense: true,
                      onPressed: ready ? () => edit(idx) : null,
                      label: known.containsKey(idx)
                          ? l.channelsEdit
                          : l.channelsSet,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Byte-equality check vs the well-known Public PSK. We use the
/// `kPublicChannelPsk` constant exported by the meshcore codec —
/// matching it means "this slot is still effectively Public."
bool _pskMatchesPublic(List<int> psk) {
  if (psk.length != kPublicChannelPsk.length) return false;
  for (int i = 0; i < psk.length; i++) {
    if (psk[i] != kPublicChannelPsk[i]) return false;
  }
  return true;
}

/// Result of the edit dialog.
class _ChannelEdit {
  const _ChannelEdit(this.idx, this.name, this.psk);
  final int idx;
  final String name;
  final List<int> psk;
}

enum _PskSource { public, hashtag, hex, shake }

class _EditChannelDialog extends StatefulWidget {
  const _EditChannelDialog({
    required this.idx,
    required this.initialName,
    this.currentPsk,
  });
  final int idx;
  final String initialName;

  /// The 16-byte PSK the controller has cached for this slot, if
  /// any. Null when we've never observed a `ChannelInfoFrame` for
  /// this slot (e.g. the user is creating it fresh) — in that case
  /// the reveal section is suppressed.
  final List<int>? currentPsk;

  @override
  State<_EditChannelDialog> createState() => _EditChannelDialogState();
}

class _EditChannelDialogState extends State<_EditChannelDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.initialName);
  final TextEditingController _tag = TextEditingController();
  late final TextEditingController _hex = TextEditingController(
    // Pre-fill Hex mode with the existing key (if the slot is
    // already set and the key isn't the well-known Public PSK).
    // Lets the user see what's there and tweak it instead of
    // re-typing 32 hex chars from scratch.
    text: widget.currentPsk != null && !_pskMatchesPublic(widget.currentPsk!)
        ? widget.currentPsk!
            .map((int b) => b.toRadixString(16).padLeft(2, '0'))
            .join()
        : '',
  );
  // Default the key-source segmented button by inspecting the
  // current PSK: Public if it matches the well-known key (or no
  // slot data), Hex otherwise. We can't distinguish hashtag-derived
  // from random-hex keys after the fact (both are opaque bytes), so
  // any non-Public slot reads as Hex on re-open. The user can
  // switch modes manually if they prefer to re-derive from a tag.
  late _PskSource _src =
      widget.currentPsk == null || _pskMatchesPublic(widget.currentPsk!)
          ? _PskSource.public
          : _PskSource.hex;
  String? _error;

  /// "Show current key" reveal state. Latched per-dialog session;
  /// dismissing & reopening the dialog requires another tap.
  bool _revealCurrent = false;

  /// R32 — dice-roll entropy collector. Lazily constructed when
  /// the user picks the Shake mode so we don't subscribe to the
  /// accelerometer in the common cases. Disposed on dialog close.
  DiceRollEntropy? _dice;

  @override
  void dispose() {
    _name.dispose();
    _tag.dispose();
    _hex.dispose();
    _dice?.dispose();
    super.dispose();
  }

  /// Common-word denylist for the #tag strength hint. Tags in this
  /// list (or their `#`-prefixed forms) are easy to grind from the
  /// surface attacker's side; we warn but don't block. The list is
  /// English / katakana-pop on purpose since #tag derivation is
  /// SHA-256 of the literal string — a tag that looks weak in EN
  /// is just as weak in JA.
  static const Set<String> _weakTagDeny = <String>{
    'public',
    'private',
    'group',
    'channel',
    'mesh',
    'meshcore',
    'meshmore',
    'chat',
    'test',
    'hello',
    'home',
    'work',
    'family',
    'friends',
    'main',
    'general',
    'team',
    'crew',
    'fleet',
    'パブリック',
    'プライベート',
    'グループ',
    'チャンネル',
    'メッシュ',
    'チャット',
    'テスト',
    '家',
    '家族',
    '仲間',
    'チーム',
  };

  String? _tagWeakHint(AppLocalizations l) {
    // The denylist matches the bare word, but the form it is stripped from
    // is the canonical one — the same normaliser the key derivation uses, so
    // the warning and the key can never disagree about what the tag is.
    final String canonical =
        MeshcoreChannelCrypto.canonicalHashtag(_tag.text).toLowerCase();
    final String raw = canonical.substring(1);
    if (raw.isEmpty) return null;
    if (raw.length < 8) return l.channelsTagWeakShort;
    if (_weakTagDeny.contains(raw)) return l.channelsTagWeakCommon;
    return null;
  }

  /// Cryptographically-random 16-byte PSK, rendered as 32 hex chars
  /// into the field. Uses `Random.secure()` (platform OS-RNG).
  void _generateRandomPsk() {
    final math.Random r = math.Random.secure();
    final List<int> bytes = <int>[
      for (int i = 0; i < 16; i++) r.nextInt(256),
    ];
    setState(() {
      _hex.text =
          bytes.map((int b) => b.toRadixString(16).padLeft(2, '0')).join();
    });
  }

  List<int>? _resolvePsk(AppLocalizations l) {
    switch (_src) {
      case _PskSource.public:
        return kPublicChannelPsk;
      case _PskSource.hashtag:
        final String t = _tag.text.trim();
        if (t.isEmpty) {
          _error = l.channelsErrorTag;
          return null;
        }
        return MeshcoreChannelCrypto.channelPskFromHashtag(t);
      case _PskSource.hex:
        final String h = _hex.text.trim().replaceAll(RegExp(r'\s'), '');
        if (h.length != 32 || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(h)) {
          _error = l.channelsErrorHex;
          return null;
        }
        return <int>[
          for (int i = 0; i < 32; i += 2)
            int.parse(h.substring(i, i + 2), radix: 16),
        ];
      case _PskSource.shake:
        // The dice-roll widget hands the user a derived key once
        // entropy reaches `complete`. The Save button is disabled
        // while incomplete (see build), so this branch only ever
        // sees a finished digest.
        final DiceRollEntropy? d = _dice;
        if (d == null || !d.complete) {
          _error = l.channelsErrorHex; // generic — UI gates this
          return null;
        }
        return d.psk;
    }
  }

  void _save(AppLocalizations l) {
    setState(() => _error = null);
    final List<int>? psk = _resolvePsk(l);
    if (psk == null) {
      setState(() {});
      return;
    }
    String name = _name.text.trim();
    if (name.isEmpty && _src == _PskSource.public) name = 'Public';
    if (name.isEmpty && _src == _PskSource.hashtag) {
      // Store the canonical name too: the radio echoes this string back as
      // the channel's name, and a slot whose name reads `emergency` while
      // its key is sha256("#emergency") is a channel nobody can find again.
      name = MeshcoreChannelCrypto.canonicalHashtag(_tag.text);
    }
    if (name.isEmpty) {
      setState(() => _error = l.channelsErrorName);
      return;
    }
    Navigator.pop(context, _ChannelEdit(widget.idx, name, psk));
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.channelsDialogTitle(widget.idx)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              controller: _name,
              decoration:
                  InputDecoration(labelText: l.channelsName, isDense: true),
            ),
            SizedBox(height: context.skin.space.rowInset),
            SegmentedButton<_PskSource>(
              segments: <ButtonSegment<_PskSource>>[
                ButtonSegment<_PskSource>(
                    value: _PskSource.public, label: Text(l.channelsKeyPublic)),
                ButtonSegment<_PskSource>(
                    value: _PskSource.hashtag,
                    label: Text(l.channelsKeyHashtag)),
                ButtonSegment<_PskSource>(
                    value: _PskSource.hex, label: Text(l.channelsKeyHex)),
                ButtonSegment<_PskSource>(
                    value: _PskSource.shake, label: Text(l.channelsKeyShake)),
              ],
              selected: <_PskSource>{_src},
              onSelectionChanged: (Set<_PskSource> s) {
                final _PskSource next = s.first;
                setState(() {
                  // Tearing down the entropy collector when the user
                  // leaves Shake mode avoids surprise background
                  // accelerometer sampling.
                  if (_src == _PskSource.shake && next != _PskSource.shake) {
                    _dice?.freeze();
                  }
                  _src = next;
                });
              },
            ),
            SizedBox(height: context.skin.space.rowGap),
            if (_src == _PskSource.public)
              Text(l.channelsKeyPublicBody,
                  style: TextStyle(fontSize: context.skin.type.sizeBody))
            else if (_src == _PskSource.hashtag) ...<Widget>[
              TextField(
                controller: _tag,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                    labelText: l.channelsKeyHashtagHint,
                    suffixIcon: Tooltip(
                      message: l.channelsKeyHashtagHelper,
                      child: const Icon(Icons.info_outline, size: 18),
                    ),
                    isDense: true),
              ),
              if (_tagWeakHint(l) != null) ...<Widget>[
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(Icons.warning_amber_rounded,
                        size: 14,
                        color: Theme.of(context).colorScheme.tertiary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(_tagWeakHint(l)!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.tertiary,
                              fontSize: context.skin.type.sizeSm)),
                    ),
                  ],
                ),
              ],
            ] else if (_src == _PskSource.hex) ...<Widget>[
              TextField(
                controller: _hex,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F]')),
                ],
                decoration: InputDecoration(
                    labelText: l.channelsKeyHexHint, isDense: true),
              ),
              const SizedBox(height: 6),
              // Buttons in a Wrap so they break to a second line on
              // narrow dialogs / dense locales. The JA labels
              // ("PSK をランダム生成" + "コピー") overflow the 283-wide
              // dialog content area as a single Row.
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: <Widget>[
                  OutlinedButton.icon(
                    icon: const Icon(Icons.casino, size: 16),
                    label: Text(l.channelsHexGenerate),
                    onPressed: _generateRandomPsk,
                  ),
                  if (_hex.text.trim().length == 32)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.copy, size: 16),
                      label: Text(l.channelsHexCopy),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(
                            text: _hex.text.trim().toLowerCase()));
                        if (!context.mounted) return;
                        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                            SnackBar(
                                content: Text(l.channelsHexCopied),
                                duration: const Duration(seconds: 2)));
                      },
                    ),
                ],
              ),
            ] else if (_src == _PskSource.shake)
              _DiceRollPanel(
                getOrInit: () {
                  // Lazy-init the entropy collector + start
                  // sampling. Latched: subsequent rebuilds reuse
                  // the same instance.
                  if (_dice == null) {
                    _dice = DiceRollEntropy();
                    // If the user has reduceMotion on, prime the
                    // digest from Random.secure once instead of
                    // listening to the accelerometer. We still
                    // present a Reroll button, which re-seeds.
                    final ThemeController tc = context.read<ThemeController>();
                    if (tc.reduceMotion) {
                      _dice!.seedFromSecureRandom();
                    } else {
                      _dice!.start();
                    }
                  }
                  return _dice!;
                },
                reroll: () {
                  _dice?.reset();
                  final ThemeController tc = context.read<ThemeController>();
                  if (tc.reduceMotion) {
                    _dice!.seedFromSecureRandom();
                  } else {
                    _dice!.start();
                  }
                },
              ),
            // Reveal-current-key block (R6 follow-on). Only shown
            // when the controller has actually cached a PSK for
            // this slot. Latched behind a Reveal tap so the key
            // doesn't appear on every dialog-open. Slot 0's
            // "current key" is the well-known kPublicChannelPsk —
            // we still surface it for symmetry.
            if (widget.currentPsk != null) ...<Widget>[
              const Divider(height: 24),
              Row(
                children: <Widget>[
                  Icon(Icons.vpn_key,
                      size: 16, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 6),
                  Text(l.channelsCurrentKey,
                      style: TextStyle(
                          fontSize: context.skin.type.sizeBody,
                          letterSpacing: 1)),
                  const Spacer(),
                  TextButton.icon(
                    icon: Icon(
                        _revealCurrent
                            ? Icons.visibility_off
                            : Icons.visibility,
                        size: 16),
                    label: Text(_revealCurrent
                        ? l.channelsHideKey
                        : l.channelsRevealKey),
                    onPressed: () =>
                        setState(() => _revealCurrent = !_revealCurrent),
                  ),
                ],
              ),
              if (_revealCurrent)
                SelectableText(
                  widget.currentPsk!
                      .map((int b) => b.toRadixString(16).padLeft(2, '0'))
                      .join(),
                  style: TextStyle(
                      fontFamily: context.skin.type.monoFamily,
                      fontSize: context.skin.type.sizeSm),
                ),
              // QR-share — only meaningful for non-Public slots
              // (Public's key is world-known, no point sharing).
              if (!_pskMatchesPublic(widget.currentPsk!)) ...<Widget>[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.qr_code_2, size: 16),
                    label: Text(l.channelsShareQr),
                    onPressed: () => _showQrShare(context, widget.idx,
                        widget.initialName, widget.currentPsk!),
                  ),
                ),
              ],
            ],
            if (_error != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(_error!,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: context.skin.type.sizeBody)),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        // Clear slot: only offered when the slot has actually been
        // configured (currentPsk known). Slot 0 is also clearable —
        // clearChannel(0) is a no-op (already Public).
        if (widget.currentPsk != null)
          TextButton.icon(
            icon: const Icon(Icons.delete_outline, size: 16),
            label: Text(l.channelsClear),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () async {
              final bool ok = await mmConfirm(
                context,
                title: l.channelsClearConfirmTitle(widget.idx),
                body: l.channelsClearConfirmBody,
                cancelLabel: l.channelsCancel,
                confirmLabel: l.channelsClearConfirmAction,
                destructive: true,
              );
              if (!ok) return;
              if (!context.mounted) return;
              // Pop with a special marker the outer screen reads
              // as "the user wants to clear this slot." We could
              // call mc.clearChannel here directly, but the outer
              // screen owns the snack + provider lookup, so it's
              // cleaner to delegate.
              Navigator.pop(context,
                  _ChannelEdit(widget.idx, '__clear__', const <int>[]));
            },
          ),
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.channelsCancel)),
        FilledButton(onPressed: () => _save(l), child: Text(l.channelsSave)),
      ],
    );
  }
}

/// R32 — UI surface for the dice-roll PSK derivation.
///
/// Hands the parent dialog a [DiceRollEntropy] via `getOrInit`
/// and re-renders as that collector accumulates motion samples.
/// Shows a circular progress ring + a 32-char hex preview that
/// fills in as the underlying SHA-256 digest stabilises + a
/// "Reroll" affordance that wipes the buffer and re-starts.
/// Encode a channel slot + name + 16-byte PSK as a compact URI
/// the matching `decodeChannelShareUri` can parse back. Format:
/// `meshmore://channel?idx=N&name=URL-ENC&psk=HEX`. Kept small
/// on purpose (fits inside NTAG213 user memory for R34 NFC).
String encodeChannelShareUri(int idx, String name, List<int> psk) {
  final String hex =
      psk.map((int b) => b.toRadixString(16).padLeft(2, '0')).join();
  return 'meshmore://channel?idx=$idx'
      '&name=${Uri.encodeQueryComponent(name)}'
      '&psk=$hex';
}

void _showQrShare(BuildContext outer, int idx, String name, List<int> psk) {
  final AppLocalizations l = AppLocalizations.of(outer);
  final String payload = encodeChannelShareUri(idx, name, psk);
  showDialog<void>(
    context: outer,
    builder: (BuildContext ctx) {
      final ColorScheme cs = Theme.of(ctx).colorScheme;
      return AlertDialog(
        title: Text(l.channelsQrTitle(idx)),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(l.channelsQrBody,
                    style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: ctx.skin.type.sizeBody)),
                SizedBox(height: ctx.skin.space.rowInset),
                Center(
                  child: Container(
                    padding: EdgeInsets.all(ctx.skin.space.rowInset),
                    decoration: BoxDecoration(
                      // White is the QR format's own requirement — a camera
                      // expects dark modules on a light field — so this one
                      // surface does not follow the skin's ground. Its shape
                      // does: the corner comes from the skin's radius family
                      // rather than a decorative 8.
                      color: Colors.white,
                      borderRadius: mmRadius(ctx, kRadiusSm),
                    ),
                    child: QrImageView(
                      data: payload,
                      version: QrVersions.auto,
                      size: 240,
                      backgroundColor: Colors.white,
                    ),
                  ),
                ),
                SizedBox(height: ctx.skin.space.rowInset),
                Text(l.channelsQrPayload,
                    style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: ctx.skin.type.sizeSm,
                        letterSpacing: 1)),
                const SizedBox(height: 4),
                SelectableText(
                  payload,
                  style: TextStyle(
                      fontFamily: ctx.skin.type.monoFamily,
                      fontSize: ctx.skin.type.sizeSm,
                      height: 1.4),
                ),
              ],
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l.channelsQrClose),
          ),
        ],
      );
    },
  );
}

class _DiceRollPanel extends StatelessWidget {
  const _DiceRollPanel({
    required this.getOrInit,
    required this.reroll,
  });

  final DiceRollEntropy Function() getOrInit;
  final VoidCallback reroll;

  @override
  Widget build(BuildContext context) {
    final DiceRollEntropy d = getOrInit();
    final AppLocalizations l = AppLocalizations.of(context);
    final ColorScheme cs = Theme.of(context).colorScheme;
    final ThemeController tc = context.watch<ThemeController>();
    return AnimatedBuilder(
      animation: d,
      builder: (BuildContext _, Widget? __) {
        final String hex =
            d.psk.map((int b) => b.toRadixString(16).padLeft(2, '0')).join();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(l.channelsShakeTitle,
                style: Theme.of(context).textTheme.titleSmall),
            SizedBox(height: context.skin.space.labelToControl),
            Text(
              tc.reduceMotion
                  ? l.channelsShakeTapFallback
                  : l.channelsShakeBody,
              style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: context.skin.type.sizeBody),
            ),
            SizedBox(height: context.skin.space.rowInset),
            Row(
              children: <Widget>[
                SizedBox.square(
                  dimension: context.skin.space.step(9),
                  child: CircularProgressIndicator(
                    value: d.progress,
                    strokeWidth: 4,
                    color: d.complete ? cs.tertiary : cs.primary,
                  ),
                ),
                SizedBox(width: context.skin.space.rowInset),
                Expanded(
                  child: SelectableText(
                    hex,
                    style: TextStyle(
                        color: d.complete ? cs.onSurface : cs.onSurfaceVariant,
                        fontFamily: context.skin.type.monoFamily,
                        fontSize: context.skin.type.sizeBody,
                        height: 1.4),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              l.channelsShakeProgress(
                d.acceptedSamples,
                (d.targetBits / d.bitsPerSample).round(),
                (d.progress * 100).round(),
              ),
              style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: context.skin.type.sizeSm),
            ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(l.channelsShakeReroll),
              onPressed: reroll,
            ),
          ],
        );
      },
    );
  }
}

/// R54, D8.13, R59 — everything about a channel that is not its name or its
/// key. These used to live inside the edit dialog, which then did six jobs at
/// once: naming, key choice, key reveal, sharing, inference and the
/// notification bundle. They apply immediately and independently of a save, so
/// they belong to the channel, not to the act of editing it.
class _ChannelOptionsSheet extends StatelessWidget {
  const _ChannelOptionsSheet({required this.idx, required this.name});

  final int idx;
  final String name;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return SafeArea(
      top: false,
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        children: <Widget>[
          Text(name, style: Theme.of(context).textTheme.titleMedium),
          // R54 — per-channel place inference. Applied immediately
          // (independent of the name/PSK save), default on for the
          // public channel.
          const Divider(height: 20),
          Builder(builder: (BuildContext ctx) {
            final MeshcoreController mc = ctx.watch<MeshcoreController>();
            return SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(l.channelsInferPlaces),
              subtitle: Text(l.channelsInferPlacesSub),
              value: mc.placeInferenceEnabled(idx),
              onChanged: (bool v) => mc.setPlaceInferenceEnabled(idx, v),
            );
          }),
          // D8.13 — the per-channel notification bundle. Every toggle is
          // per slot: silencing the busy channel must not silence the
          // emergency one, and mentions-only is off unless asked for.
          const Divider(height: 20),
          Builder(builder: (BuildContext ctx) {
            final NotificationPrefs? np = ctx.watch<NotificationPrefs?>();
            if (np == null) return const SizedBox.shrink();
            final ChannelNotificationPrefs p = np.prefsFor(idx);
            void save(ChannelNotificationPrefs next) => np.setFor(idx, next);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(l.notifSectionTitle,
                    style: Theme.of(ctx).textTheme.titleSmall),
                // Silence, on the channel's own sheet. It used to be a single
                // row in App settings for the *public* channel only, so channels
                // 1..n could not be silenced at all — and the notice here pointed
                // at a switch three screens away that would not have silenced
                // this channel even if found.
                SwitchListTile(
                  key: ValueKey<String>('notif-muted-$idx'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(l.notifMuted),
                  subtitle: Text(l.notifMutedSub),
                  value: p.muted,
                  onChanged: (bool v) => save(p.copyWith(muted: v)),
                ),
                // A silenced channel's remaining switches do nothing, so say so
                // where they are rather than leaving a user toggling them and
                // hearing nothing.
                if (p.muted)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      l.notifMutedNoticeHere,
                      key: const ValueKey<String>('notif-muted-notice'),
                      style: Theme.of(ctx)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Theme.of(ctx).colorScheme.error),
                    ),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(l.notifOs),
                  value: p.os,
                  onChanged: (bool v) => save(p.copyWith(os: v)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(l.notifAudio),
                  value: p.audio,
                  onChanged: (bool v) => save(p.copyWith(audio: v)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(l.notifHaptic),
                  value: p.haptic,
                  onChanged: (bool v) => save(p.copyWith(haptic: v)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(l.notifTts),
                  value: p.tts,
                  onChanged: (bool v) => save(p.copyWith(tts: v)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(l.notifMentionsOnly),
                  subtitle: Text(l.notifMentionsOnlySub),
                  value: p.mentionsOnly,
                  onChanged: (bool v) => save(p.copyWith(mentionsOnly: v)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(l.notifKeySuffix),
                  subtitle: Text(l.notifKeySuffixSub),
                  value: p.keySuffixMentions,
                  onChanged: (bool v) => save(p.copyWith(keySuffixMentions: v)),
                ),
              ],
            );
          }),
          // R59 — the bot binds per channel. The section renders on
          // every slot, including Public, because a refusal that
          // explains itself teaches more than a missing control.
          const Divider(height: 20),
          BotSection(scope: ChannelScope(idx)),
        ],
      ),
    );
  }
}
