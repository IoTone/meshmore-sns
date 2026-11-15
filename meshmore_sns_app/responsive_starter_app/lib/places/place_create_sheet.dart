// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../gen/app_localizations.dart';
import '../theme/mm_skin.dart';
import '../meshcore/meshcore_controller.dart';
import '../ui/mm_components.dart';
import 'place.dart';
import 'place_channel_pref.dart';
import 'place_codec.dart';
import 'place_sender.dart';
import 'place_ui.dart';
import 'place_wiring.dart';

/// The sheet a long-press on the map opens
/// (`meshmore-places-spec.md` §3, §7, §9, §12).
///
/// It is a composer, not a form: the label, the nine types and the ten lives
/// are all one tap each, because the usual report is "hazard here" written
/// while standing next to it. The budget refusal is shown as a time, never as
/// a silent drop, and the precision choice defaults to **exact** for a point
/// the user aimed at — the snapped default belongs to "at my position", which
/// is the other way in (§9).
class PlaceCreateSheet extends StatefulWidget {
  const PlaceCreateSheet({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.composer,
    this.showPrecision = false,
    this.initialLabel,
    this.initialChannelIdx,
  });

  final double latitude;
  final double longitude;
  final PlaceComposer composer;

  /// Offers the precision choice. Off for a point the user aimed at on the
  /// map, where "snap it" can only lose the spot they chose.
  final bool showPrecision;

  /// A name to start from, when the place came from a message that named it
  /// rather than from a long-press. It is a starting point, not a decision:
  /// the field is focused and editable like any other.
  final String? initialLabel;

  /// The channel to start on, when the caller knows better than the reader's
  /// last choice: a place suggested by a message belongs on the channel that
  /// message arrived on. Null means the remembered slot, then the active one.
  final int? initialChannelIdx;

  /// Shows the sheet; resolves to the place when one went out.
  static Future<Place?> show(
    BuildContext context, {
    required double latitude,
    required double longitude,
    required PlaceComposer composer,
    bool showPrecision = false,
    String? initialLabel,
    int? initialChannelIdx,
  }) =>
      showModalBottomSheet<Place>(
        context: context,
        isScrollControlled: true,
        builder: (_) => PlaceCreateSheet(
          latitude: latitude,
          longitude: longitude,
          composer: composer,
          showPrecision: showPrecision,
          initialLabel: initialLabel,
          initialChannelIdx: initialChannelIdx,
        ),
      );

  @override
  State<PlaceCreateSheet> createState() => _PlaceCreateSheetState();
}

class _PlaceCreateSheetState extends State<PlaceCreateSheet> {
  late final TextEditingController _label =
      TextEditingController(text: widget.initialLabel ?? '');
  PlaceType _type = PlaceType.hazard;
  late PlaceTtl _ttl = _type.defaultTtl;
  PlacePrecision _precision = PlacePrecision.exact;
  bool _sending = false;
  PlaceLabelProblem? _labelProblem;
  DateTime? _refusedUntil;
  int _refusedAfter = 0;
  bool _noIdentity = false;

  /// The channels this radio has, and the slot the report will go to. Both are
  /// empty until the controller answers, which is also what keeps the picker
  /// out of a widget test that has no radio.
  List<MapEntry<int, String>> _channels = const <MapEntry<int, String>>[];
  int? _channelIdx;

  /// True once the reader has moved the picker. Only a real choice is
  /// remembered: writing the active channel on every send would turn "follow
  /// the channel I am on" into a setting nobody made.
  bool _channelChosen = false;

  @override
  void initState() {
    super.initState();
    _loadChannel();
  }

  Future<void> _loadChannel() async {
    final MeshcoreController? mc = context.read<MeshcoreController?>();
    if (mc == null) return;
    final List<MapEntry<int, String>> channels = mc.channels;
    final int? remembered = await PlaceChannelPref.read();
    if (!mounted) return;
    final int fallback = widget.initialChannelIdx ?? mc.activeChannel;
    final int chosen = remembered != null &&
            channels.any((MapEntry<int, String> e) => e.key == remembered)
        ? remembered
        : fallback;
    setState(() {
      _channels = channels;
      _channelIdx = chosen;
    });
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final AppLocalizations l = AppLocalizations.of(context);
    final PlaceLabelProblem? problem = placeLabelProblem(_label.text);
    if (problem != null) {
      setState(() => _labelProblem = problem);
      return;
    }
    setState(() {
      _sending = true;
      _labelProblem = null;
      _refusedUntil = null;
      _noIdentity = false;
    });
    // The report goes to the slot the picker shows, not to whichever channel
    // happens to be active: the two differ as soon as the reader picks one.
    final int? chosen = _channelIdx;
    PlaceComposer composer = widget.composer;
    if (chosen != null && chosen != widget.composer.destinationChannelIdx) {
      composer = placeComposerOf(context, channelIdx: chosen);
    }
    if (chosen != null && _channelChosen) await PlaceChannelPref.write(chosen);
    final PlaceComposeResult result = await composer.compose(
      latitude: widget.latitude,
      longitude: widget.longitude,
      label: _label.text,
      type: _type,
      ttl: _ttl,
      precision: _precision,
    );
    if (!mounted) return;
    setState(() => _sending = false);
    switch (result.refusal) {
      case null:
        Navigator.of(context).pop(result.place);
      case PlaceComposeRefusal.label:
        setState(() => _labelProblem = result.labelProblem);
      case PlaceComposeRefusal.budget:
        setState(() {
          _refusedUntil = result.allowedAt;
          _refusedAfter = 6;
        });
      case PlaceComposeRefusal.identity:
        setState(() => _noIdentity = true);
      case PlaceComposeRefusal.coordinates:
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(l.placeCoordinatesRefused)),
        );
      case PlaceComposeRefusal.radio:
        // The radio did not take the line. Saying "Place tagged" here was the
        // sheet claiming a send that never happened.
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(l.placeRadioRefused)),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;
    return Padding(
      padding: EdgeInsets.only(
        left: skin.space.step(5),
        right: skin.space.step(5),
        top: skin.space.step(4),
        // `viewInsets` is the keyboard; `padding` is the navigation area. The
        // sheet handled the keyboard and called it done, so with the keyboard
        // closed its last row sat 12 dp from the glass — inside the handle. The
        // taller of the two is what has to be cleared.
        bottom: math.max(MediaQuery.viewInsetsOf(context).bottom,
                MediaQuery.paddingOf(context).bottom) +
            skin.space.step(5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l.placeCreateTitle,
            style: TextStyle(
              color: skin.color.fg,
              fontSize: skin.type.sizeLg,
              fontWeight: FontWeight.w700,
            ),
          ),
          // Where it goes. A place is ordinary channel text, so it lands on
          // one slot and every MeshCore client on that slot can read it. The
          // sheet used to say none of that, so a report dropped while #cos was
          // open went to #cos and the reader had no way to know. It is a
          // picker now, because knowing where a report goes and being able to
          // change it are the same question.
          if (_channels.isNotEmpty && _channelIdx != null)
            Padding(
              padding: EdgeInsets.only(top: skin.space.step(2)),
              child: Row(
                children: <Widget>[
                  Text(l.placeChannelTitle,
                      style: TextStyle(
                          color: skin.color.fgMuted,
                          fontSize: skin.type.sizeSm)),
                  SizedBox(width: skin.space.step(3)),
                  DropdownButton<int>(
                    key: const ValueKey<String>('place-channel-picker'),
                    value: _channelIdx,
                    isDense: true,
                    dropdownColor: skin.color.surface,
                    style: TextStyle(
                        color: skin.color.fg, fontSize: skin.type.sizeBody),
                    underline: Container(height: 1, color: skin.color.line),
                    items: <DropdownMenuItem<int>>[
                      for (final MapEntry<int, String> c in _channels)
                        DropdownMenuItem<int>(
                          key: ValueKey<String>('place-channel-${c.key}'),
                          value: c.key,
                          child: Text(c.value),
                        ),
                    ],
                    onChanged: (int? idx) {
                      if (idx == null) return;
                      setState(() {
                        _channelIdx = idx;
                        _channelChosen = true;
                      });
                    },
                  ),
                ],
              ),
            ),
          SizedBox(height: skin.space.step(3)),
          TextField(
            key: const ValueKey<String>('place-label'),
            controller: _label,
            autofocus: true,
            maxLength: placeMaxLabelRunes,
            decoration: InputDecoration(
              labelText: l.placeLabelField,
              hintText: l.placeLabelHint,
              errorText: switch (_labelProblem) {
                PlaceLabelProblem.empty => l.placeLabelEmpty,
                PlaceLabelProblem.tooLong => l.placeLabelTooLong,
                PlaceLabelProblem.carriesTtl => l.placeLabelCarriesTtl,
                null => null,
              },
            ),
            style: TextStyle(color: skin.color.fg, fontSize: skin.type.sizeBody),
          ),
          SizedBox(height: skin.space.step(2)),
          Text(l.placeTypeTitle,
              style: TextStyle(
                  color: skin.color.fgMuted, fontSize: skin.type.sizeSm)),
          Wrap(
            spacing: skin.space.step(2),
            runSpacing: skin.space.step(2),
            children: <Widget>[
              for (final PlaceType t in PlaceType.values)
                MmChoiceChip(
                  key: ValueKey<String>('place-type-${t.token}'),
                  label: Text(placeTypeLabel(l, t)),
                  avatar: Icon(placeIcon(t), size: 16),
                  selected: _type == t,
                  onSelected: (_) => setState(() {
                    _type = t;
                    _ttl = t.defaultTtl;
                  }),
                ),
            ],
          ),
          SizedBox(height: skin.space.step(2)),
          // One picker instead of ten chips, labelled with what the choice
          // means rather than its wire spelling (UX audit C5).
          Row(
            children: <Widget>[
              Text(l.placeTtlTitle,
                  style: TextStyle(
                      color: skin.color.fgMuted, fontSize: skin.type.sizeSm)),
              SizedBox(width: skin.space.step(3)),
              DropdownButton<PlaceTtl>(
                key: const ValueKey<String>('place-ttl-picker'),
                value: _ttl,
                isDense: true,
                dropdownColor: skin.color.surface,
                style: TextStyle(
                    color: skin.color.fg, fontSize: skin.type.sizeBody),
                underline: Container(height: 1, color: skin.color.line),
                items: <DropdownMenuItem<PlaceTtl>>[
                  for (final PlaceTtl t in PlaceTtl.values)
                    DropdownMenuItem<PlaceTtl>(
                      key: ValueKey<String>('place-ttl-${t.token}'),
                      value: t,
                      child: Text(_ttlLabel(l, t)),
                    ),
                ],
                onChanged: (PlaceTtl? t) {
                  if (t != null) setState(() => _ttl = t);
                },
              ),
            ],
          ),
          // Precision is only a choice when the point is not the one the user
          // aimed at; every caller today passes an aimed point, so the row is
          // not shown and the report carries the exact spot (spec §9).
          if (widget.showPrecision) ...<Widget>[
            SizedBox(height: skin.space.step(2)),
            Text(l.placePrecisionTitle,
                style: TextStyle(
                    color: skin.color.fgMuted, fontSize: skin.type.sizeSm)),
            Wrap(
              spacing: skin.space.step(2),
              children: <Widget>[
                for (final PlacePrecision p in PlacePrecision.values)
                  MmChoiceChip(
                    key: ValueKey<String>('place-precision-${p.decimals}'),
                    label: Text(switch (p) {
                      PlacePrecision.exact => l.placePrecisionExact,
                      PlacePrecision.snapped100m => l.placePrecision100,
                      PlacePrecision.snapped1km => l.placePrecision1000,
                    }),
                    selected: _precision == p,
                    onSelected: (_) => setState(() => _precision = p),
                  ),
              ],
            ),
          ],
          if (_refusedUntil != null)
            Padding(
              padding: EdgeInsets.only(top: skin.space.step(3)),
              child: Text(
                l.placeBudgetRefused(
                  _refusedAfter,
                  _clockText(context, _refusedUntil!),
                ),
                style: TextStyle(
                    color: skin.color.alertInk,
                    fontSize: skin.type.sizeSm),
              ),
            ),
          if (_noIdentity)
            Padding(
              padding: EdgeInsets.only(top: skin.space.step(3)),
              child: Text(l.placeNoIdentity,
                  style: TextStyle(
                      color: skin.color.alertInk,
                      fontSize: skin.type.sizeSm)),
            ),
          SizedBox(height: skin.space.step(3)),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
              ),
              SizedBox(width: skin.space.step(2)),
              FilledButton(
                key: const ValueKey<String>('place-send'),
                onPressed: _sending ? null : _send,
                child: Text(l.placeCreateAction),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// What a TTL stop means, in words: the wire token is a spelling, not a
  /// label (UX audit C5).
  static String _ttlLabel(AppLocalizations l, PlaceTtl t) {
    final Duration d = t.life;
    if (d.inMinutes < 60) return l.placeTtlMinutes(d.inMinutes);
    if (d.inHours < 24) return l.placeTtlHours(d.inHours);
    return l.placeTtlDays(d.inDays);
  }

  /// The clock time the budget frees up, in the user's own locale.
  static String _clockText(BuildContext context, DateTime at) =>
      MaterialLocalizations.of(context).formatTimeOfDay(
        TimeOfDay.fromDateTime(at),
        alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
      );
}
