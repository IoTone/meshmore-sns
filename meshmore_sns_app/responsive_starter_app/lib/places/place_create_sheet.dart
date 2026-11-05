// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';

import '../gen/app_localizations.dart';
import '../theme/mm_skin.dart';
import 'place.dart';
import 'place_codec.dart';
import 'place_sender.dart';
import 'place_ui.dart';

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
  });

  final double latitude;
  final double longitude;
  final PlaceComposer composer;

  /// Shows the sheet; resolves to the place when one went out.
  static Future<Place?> show(
    BuildContext context, {
    required double latitude,
    required double longitude,
    required PlaceComposer composer,
  }) =>
      showModalBottomSheet<Place>(
        context: context,
        isScrollControlled: true,
        builder: (_) => PlaceCreateSheet(
          latitude: latitude,
          longitude: longitude,
          composer: composer,
        ),
      );

  @override
  State<PlaceCreateSheet> createState() => _PlaceCreateSheetState();
}

class _PlaceCreateSheetState extends State<PlaceCreateSheet> {
  final TextEditingController _label = TextEditingController();
  PlaceType _type = PlaceType.hazard;
  late PlaceTtl _ttl = _type.defaultTtl;
  PlacePrecision _precision = PlacePrecision.exact;
  bool _sending = false;
  PlaceLabelProblem? _labelProblem;
  DateTime? _refusedUntil;
  int _refusedAfter = 0;
  bool _noIdentity = false;

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
    final PlaceComposeResult result = await widget.composer.compose(
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
        bottom: MediaQuery.viewInsetsOf(context).bottom + skin.space.step(5),
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
                ChoiceChip(
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
          Text(l.placeTtlTitle,
              style: TextStyle(
                  color: skin.color.fgMuted, fontSize: skin.type.sizeSm)),
          Wrap(
            spacing: skin.space.step(2),
            runSpacing: skin.space.step(2),
            children: <Widget>[
              for (final PlaceTtl t in PlaceTtl.values)
                ChoiceChip(
                  key: ValueKey<String>('place-ttl-${t.token}'),
                  label: Text(t.token),
                  selected: _ttl == t,
                  onSelected: (_) => setState(() => _ttl = t),
                ),
            ],
          ),
          SizedBox(height: skin.space.step(2)),
          Text(l.placePrecisionTitle,
              style: TextStyle(
                  color: skin.color.fgMuted, fontSize: skin.type.sizeSm)),
          Wrap(
            spacing: skin.space.step(2),
            children: <Widget>[
              for (final PlacePrecision p in PlacePrecision.values)
                ChoiceChip(
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
          if (_refusedUntil != null)
            Padding(
              padding: EdgeInsets.only(top: skin.space.step(3)),
              child: Text(
                l.placeBudgetRefused(
                  _refusedAfter,
                  _clockText(context, _refusedUntil!),
                ),
                style: TextStyle(color: skin.color.alert, fontSize: skin.type.sizeSm),
              ),
            ),
          if (_noIdentity)
            Padding(
              padding: EdgeInsets.only(top: skin.space.step(3)),
              child: Text(l.placeNoIdentity,
                  style: TextStyle(
                      color: skin.color.alert, fontSize: skin.type.sizeSm)),
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

  /// The clock time the budget frees up, in the user's own locale.
  static String _clockText(BuildContext context, DateTime at) =>
      MaterialLocalizations.of(context).formatTimeOfDay(
        TimeOfDay.fromDateTime(at),
        alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
      );
}
