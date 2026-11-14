// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../gen/app_localizations.dart';
import '../theme/mm_skin.dart';
import '../maps/geofence_render.dart';
import '../ui/mm_components.dart';
import '../util/mm_format.dart';
import 'geofence_controller.dart';
import 'geofence_engine.dart';

/// Draw a fence, or change one: a name, a radius, and a preview of the circle.
///
/// One sheet for both, because they are the same three fields. Editing used to
/// mean deleting a fence and drawing it again, which threw away its crossings and
/// its inside/outside state for a typo in its name.
///
/// The radius is a slider whose numbers are distances in the reader's units, not
/// a raw metre count. A fence radius in metres only is the same defect as an
/// untranslated distance anywhere else, and the app already has one formatter for
/// that (`MmFormat`), so the slider and the map's own cell-size chip cannot
/// disagree about what a distance looks like.
///
/// The preview is the same [GeofenceRender] the map draws, so what the reader
/// sizes here is what they get there.
class GeofenceCreateSheet extends StatefulWidget {
  const GeofenceCreateSheet({
    super.key,
    required this.latitude,
    required this.longitude,
    this.initialRadiusMeters = 250,
    this.initialLabel,
    this.editing = false,
    this.polygon,
  });

  final double latitude;
  final double longitude;
  final double initialRadiusMeters;

  /// The name to open with. Null for a new fence, which starts empty and shows
  /// the default name as its hint.
  final String? initialLabel;

  /// True when this sheet is changing a fence that already exists, which changes
  /// the title and nothing else: the fields are the same fields.
  final bool editing;

  /// The corners of a drawn fence, or null for a circle.
  ///
  /// A polygon has no radius to slide, so the sheet shows its shape instead and
  /// offers the name. Reshaping is not offered here: the shape is what the
  /// reader drew on the map, and a slider cannot express it.
  final List<FencePoint>? polygon;

  bool get isPolygon => polygon != null && polygon!.length >= 3;

  /// The stops the slider moves through, in metres.
  ///
  /// A ladder rather than a continuous range: a fence is a judgement about a
  /// place ("this camp", "this block"), and 1 m of precision on a 250 m circle is
  /// a number nobody can act on. The stops are the same 1/2/5 ladder the map's
  /// own cell size uses, so the two read as one system.
  static const List<double> stops = <double>[
    50,
    100,
    150,
    250,
    400,
    600,
    1000,
    1500,
    2500,
    5000,
  ];

  /// The stop nearest [metres], for a caller that wants to open on a value.
  static int indexFor(double metres) {
    int best = 0;
    for (int i = 1; i < stops.length; i++) {
      if ((stops[i] - metres).abs() < (stops[best] - metres).abs()) best = i;
    }
    return best;
  }

  @override
  State<GeofenceCreateSheet> createState() => _GeofenceCreateSheetState();
}

class _GeofenceCreateSheetState extends State<GeofenceCreateSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.initialLabel ?? '');
  late int _index = GeofenceCreateSheet.indexFor(widget.initialRadiusMeters);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save(BuildContext context) => Navigator.pop(
        context,
        (label: _name.text.trim(), radiusMeters: _currentMetres),
      );

  double get _currentMetres => GeofenceCreateSheet.stops[_index];

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;
    final FormatPrefs? prefs = context.watchFormatPrefs;
    final double metres = GeofenceCreateSheet.stops[_index];

    return SafeArea(
      top: false,
      // Scrollable, because the sheet is shown with `isScrollControlled` and a
      // 320 dp phone at 200 % text is taller than the space it gets: a Column
      // that cannot scroll clips the save button rather than letting the reader
      // reach it.
      child: SingleChildScrollView(
        child: Padding(
        padding: EdgeInsets.fromLTRB(skin.space.screenEdge,
            skin.space.rowInset, skin.space.screenEdge, skin.space.screenEdge),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              // A drawn shape is not "here" and is not a radius: the sheet's
              // title names what the reader is doing, and it was the circle
              // flow's words on a polygon's save sheet.
              widget.editing
                  ? l.geofenceEditTitle
                  : (widget.isPolygon
                      ? l.geofenceCanvasTitle
                      : l.geofenceCreateTitle),
              style: TextStyle(
                color: skin.color.fg,
                fontSize: skin.type.sizeLg,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: skin.space.rowGap),
            TextField(
              key: const ValueKey<String>('geofence-name'),
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: l.geofenceNameLabel,
                hintText: l.geofenceDefaultName(
                    context.read<GeofenceController>().fences.length + 1),
              ),
              onSubmitted: (_) => _save(context),
            ),
            SizedBox(height: skin.space.sectionGap),
            // The preview: the same fill and ring the map will draw, at the size
            // the slider is currently on. A number alone does not tell a reader
            // whether 400 m is a camp or a county.
            Row(
              children: <Widget>[
                GeofenceShapePreview(
                  key: const ValueKey<String>('geofence-shape-preview'),
                  polygon: widget.polygon,
                  inside: false,
                  size: skin.space.step(9),
                ),
                SizedBox(width: skin.space.rowInset),
                Expanded(
                  child: Text(
                    widget.isPolygon
                        ? l.geofenceCorners(widget.polygon!.length)
                        : MmFormat.distance(metres, prefs: prefs),
                    key: const ValueKey<String>('geofence-radius-value'),
                    style: TextStyle(
                      color: skin.color.fg,
                      fontFamily: skin.type.monoFamily,
                      fontSize: skin.type.sizeLg,
                    ),
                  ),
                ),
              ],
            ),
            if (widget.isPolygon)
              Padding(
                padding: EdgeInsets.only(top: skin.space.rowGap),
                child: Text(
                  l.geofencePolygonNote,
                  key: const ValueKey<String>('geofence-polygon-note'),
                  style: TextStyle(
                      color: skin.color.fgMuted,
                      fontSize: skin.type.sizeSm,
                      height: 1.4),
                ),
              )
            else
              Slider(
                key: const ValueKey<String>('geofence-radius'),
                value: _index.toDouble(),
                min: 0,
                max: (GeofenceCreateSheet.stops.length - 1).toDouble(),
                divisions: GeofenceCreateSheet.stops.length - 1,
                label: MmFormat.distance(metres, prefs: prefs),
                onChanged: (double v) => setState(() => _index = v.round()),
              ),
            SizedBox(height: skin.space.rowGap),
            // A `Wrap`, not a `Row`: at 320 dp and 200 % text the two labels
            // are wider than the sheet, and a Row clips the second one rather
            // than putting it on the next line.
            Wrap(
              alignment: WrapAlignment.end,
              spacing: skin.space.rowGap,
              runSpacing: skin.space.rowGap,
              children: <Widget>[
                MmAction(
                  key: const ValueKey<String>('geofence-cancel'),
                  icon: Icons.close,
                  label: l.actionCancel,
                  onPressed: () => Navigator.pop(context),
                ),
                MmAction(
                  key: const ValueKey<String>('geofence-save'),
                  icon: Icons.check,
                  label: l.actionSave,
                  onPressed: () => _save(context),
                ),
              ],
            ),
          ],
        ),
        ),
      ),
    );
  }
}
