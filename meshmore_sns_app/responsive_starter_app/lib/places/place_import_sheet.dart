// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../gen/app_localizations.dart';
import '../theme/mm_skin.dart';
import 'place_import.dart';

/// Reads a place out of text somebody shared.
///
/// The other half of [placeShareText]: a place that arrives in a message, a
/// note or another app's share sheet used to have to be retyped by hand. The
/// sheet takes the text, says what it read, and hands the result back to the
/// caller, which opens the ordinary create sheet on it — an import is a
/// starting point for a report, not a report, because the reader still chooses
/// the type and the life.
class PlaceImportSheet extends StatefulWidget {
  const PlaceImportSheet({super.key, this.initialText});

  /// Text to start from, when the caller already has it (a share intent, a
  /// clipboard read). Null leaves the field empty.
  final String? initialText;

  static Future<ImportedPlace?> show(
    BuildContext context, {
    String? initialText,
  }) =>
      showModalBottomSheet<ImportedPlace>(
        context: context,
        isScrollControlled: true,
        builder: (_) => PlaceImportSheet(initialText: initialText),
      );

  @override
  State<PlaceImportSheet> createState() => _PlaceImportSheetState();
}

class _PlaceImportSheetState extends State<PlaceImportSheet> {
  late final TextEditingController _text =
      TextEditingController(text: widget.initialText ?? '');
  PlaceImportRefusal? _refusal;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _read() {
    final PlaceImportResult result = parsePlaceShareText(_text.text);
    if (result.place case final ImportedPlace place) {
      Navigator.of(context).pop(place);
      return;
    }
    setState(() => _refusal = result.refusal);
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
        // The keyboard is taller than the navigation area, and the sheet has to
        // clear whichever is present.
        bottom: math.max(MediaQuery.viewInsetsOf(context).bottom,
                MediaQuery.paddingOf(context).bottom) +
            skin.space.step(5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l.placeImportTitle,
            style: TextStyle(
              color: skin.color.fg,
              fontSize: skin.type.sizeLg,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: skin.space.step(2)),
          Text(
            l.placeImportExplainer,
            style: TextStyle(color: skin.color.fgMuted, fontSize: skin.type.sizeSm),
          ),
          SizedBox(height: skin.space.step(3)),
          TextField(
            key: const ValueKey<String>('place-import-text'),
            controller: _text,
            autofocus: true,
            minLines: 3,
            maxLines: 6,
            keyboardType: TextInputType.multiline,
            decoration: InputDecoration(
              labelText: l.placeImportField,
              hintText: l.placeImportHint,
              errorText: switch (_refusal) {
                PlaceImportRefusal.empty => l.placeImportEmpty,
                PlaceImportRefusal.noCoordinates => l.placeImportNoCoordinates,
                PlaceImportRefusal.outOfRange => l.placeImportOutOfRange,
                null => null,
              },
            ),
            style: TextStyle(color: skin.color.fg, fontSize: skin.type.sizeBody),
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
                key: const ValueKey<String>('place-import-go'),
                onPressed: _read,
                child: Text(l.placeImportGo),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
