// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/theme/mm_skin.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';

/// R114 — every tappable thing looks like one.
///
/// Three rules, in the style of `mm_ratchet_test.dart` and
/// `square_controls_guard_test.dart`:
///
///  * the theme gives a text button a boundary and the 48 dp floor in every
///    preset (hard rule, widget-level);
///  * a page-level `TextButton` and a picker row without a trailing affordance
///    are held to a lower-only per-file baseline, so the class cannot grow while
///    the remaining sites are converted;
///  * a tappable canvas mark carries a `Semantics` label (hard rule).
///
/// The baselines are counts of the defect, so a conversion lowers them and a
/// new one fails the test. When a file reaches zero its entry is deleted.
void main() {
  /// `TextButton`s that read as labels today. Seeded 2026-11-05 (R114).
  const Map<String, int> textButtons = <String, int>{
    // The recorded send's confirmation and the passphrase dialog both end in
    // a Cancel beside a FilledButton, which is the dialog convention the other
    // twenty-nine files already follow. Counted here so the class cannot grow
    // while those dialogs are unified behind one widget.
    'lib/chat/export_passphrase_dialog.dart': 1,
    'lib/chat/report_flow.dart': 5,
    'lib/screens/raw_record_card.dart': 0,
    'lib/bot/bot_scope_config.dart': 2,
    'lib/bot/bot_section.dart': 2,
    'lib/chat/chat_actions.dart': 0,
    // The delete-everything dialog: a Cancel beside a filled destructive
    // confirm, the same shape as the two above and the one thing a dialog's
    // action row may be.
    'lib/ui/storage_use_block.dart': 1,
    // The one confirmation dialog (R130): a Cancel beside a filled confirm, in
    // one place instead of seventeen. Every site it replaced lost its own copy,
    // which is why several of the per-file counts below went down.
    'lib/ui/mm_confirm.dart': 1,
    'lib/media/media_composer.dart': 1,
    'lib/places/place_create_sheet.dart': 1,
    // The import dialog: a Cancel beside the filled Go button that reads the
    // pasted text, the same shape as every other dialog's action row.
    'lib/places/place_import_sheet.dart': 1,
    // The two that take a pin out of the app — Directions, which hands the
    // coordinate pair to a map app, and Share, which hands the address to
    // anything that takes text — plus the photo line's own action.
    'lib/places/place_detail_sheet.dart': 3,
    'lib/screens/app_settings_screen.dart': 1,
    'lib/screens/battery_screen.dart': 0,
    'lib/screens/blocked_keys_screen.dart': 1,
    'lib/screens/channels_screen.dart': 5,
    'lib/screens/chat_screen.dart': 0,
    'lib/screens/dashboard_screen.dart': 1,
    'lib/screens/dashboards/studio_dashboard.dart': 1,
    'lib/screens/device_config_screen.dart': 1,
    'lib/screens/device_contacts_screen.dart': 2,
    'lib/screens/device_manager_sheet.dart': 2,
    'lib/screens/diagnostics_screen.dart': 3,
    'lib/screens/fabric_survey_view.dart': 0,
    // One dialog action row: the full-legend close button.
    // Two now: the existing one, and the connect action the "not connected"
    // strip carries (a state that offers no way out is a dead end).
    'lib/screens/grid_screen.dart': 2,
    'lib/screens/first_run_intro_screen.dart': 1,
    'lib/screens/maps/maps_screen.dart': 6,
    'lib/screens/meshbook_view.dart': 0,
    'lib/screens/network_detail_screen.dart': 2,
    'lib/screens/node_detail_sheet.dart': 4,
    // Two now: the existing one, and the connect action on the offline status
    // line (a line that says "not connected" and does nothing is the dead end a
    // reader meets first in the app).
    'lib/screens/nodes_screen.dart': 2,
    // The connect action on the tools' offline notice: one notice widget, so one
    // site, and a tool that says "not connected" now says where to fix it.
    'lib/screens/tools/tool_widgets.dart': 1,
    'lib/screens/pair_radio_screen.dart': 1,
    'lib/screens/sos_screen.dart': 1,
    'lib/screens/terms_screen.dart': 1,
    'lib/screens/tools/trace_screen.dart': 1,
    'lib/shell/boot_overlay.dart': 1,
    'lib/ui/radio_health_block.dart': 1,
  };

  /// Rows that open a choice or a page with nothing in the trailing slot.
  const Map<String, int> pickerRows = <String, int>{
    'lib/chat/chat_actions.dart': 0,
    'lib/screens/location_settings_screen.dart': 2,
    'lib/screens/network_detail_screen.dart': 1,
    'lib/screens/node_detail_sheet.dart': 2,
    'lib/screens/nodes_screen.dart': 2,
    'lib/screens/tools/tool_pickers.dart': 3,
  };

  List<File> dartFiles(String root) {
    final Directory dir = Directory(root);
    if (!dir.existsSync()) return <File>[];
    return <File>[
      for (final FileSystemEntity f in dir.listSync(recursive: true))
        if (f is File && f.path.endsWith('.dart')) f,
    ];
  }

  test('text buttons and picker rows never grow past their baseline', () {
    final Map<String, int> liveButtons = <String, int>{};
    final Map<String, int> liveRows = <String, int>{};
    for (final File f in dartFiles('lib')) {
      if (f.path.contains('/gen/')) continue;
      final String src = f.readAsStringSync();
      final int buttons =
          RegExp(r'\bTextButton(\.icon)?\(').allMatches(src).length;
      if (buttons > 0) liveButtons[f.path] = buttons;
      int rows = 0;
      for (final RegExpMatch m in RegExp(r'ListTile\(').allMatches(src)) {
        final int end = src.indexOf('\n        )', m.start);
        if (end < 0) continue;
        final String args = src.substring(m.start, end);
        final bool tappable = args.contains('onTap:');
        final bool afforded = args.contains('trailing:') ||
            args.contains('SwitchListTile(') ||
            args.contains('CheckboxListTile(') ||
            args.contains('RadioListTile(');
        if (tappable && !afforded) rows++;
      }
      if (rows > 0) liveRows[f.path] = rows;
    }

    final List<String> grown = <String>[
      for (final MapEntry<String, int> e in liveButtons.entries)
        if (e.value > (textButtons[e.key] ?? 0))
          '${e.key}: ${e.value} text buttons (baseline '
              '${textButtons[e.key] ?? 0})',
      for (final MapEntry<String, int> e in liveRows.entries)
        if (e.value > (pickerRows[e.key] ?? 0))
          '${e.key}: ${e.value} bare picker rows (baseline '
              '${pickerRows[e.key] ?? 0})',
    ];
    expect(grown, isEmpty,
        reason: 'a text button reads as a label and a bare picker row reads as '
            'prose. Use MmAction / MmPickerTile. Converted a file? Lower its '
            'baseline in this test.\n${grown.join('\n')}');
  });

  test('a tappable canvas mark names itself for a screen reader', () {
    // A GestureDetector draws no ink and, without a Semantics label, announces
    // nothing. These are the files that draw their own hit areas.
    const List<String> canvasFiles = <String>[
      'lib/places/place_layer.dart',
      'lib/screens/street_map_view.dart',
      'lib/screens/fabric_survey_view.dart',
      'lib/screens/mesh_tree_view.dart',
      'lib/screens/equal_grid_view.dart',
    ];
    final List<String> offenders = <String>[];
    for (final String rel in canvasFiles) {
      final File f = File(rel);
      if (!f.existsSync()) continue;
      final String src = f.readAsStringSync();
      final int gestures = RegExp(r'GestureDetector\(').allMatches(src).length;
      final int semantics = RegExp(r'Semantics\(').allMatches(src).length;
      if (gestures > semantics) {
        offenders.add('$rel: $gestures gesture areas, $semantics labels');
      }
    }
    expect(offenders, isEmpty,
        reason: 'a mark a user can tap must announce what it opens.\n'
            '${offenders.join('\n')}');
  });

  test('the text-button affordance is themed in every preset', () {
    for (final MmThemePreset p in MmThemePreset.values) {
      final MmSkin s = mmSkinFor(p);
      final ThemeData t = buildMmTheme(s.color,
          fontFamily: s.type.displayFamily, shape: s.shape);
      expect(t.textButtonTheme.style, isNotNull, reason: '$p');
      expect(t.textButtonTheme.style!.side!.resolve(<WidgetState>{}), isNotNull,
          reason: '$p carries a boundary');
      expect(
          t.textButtonTheme.style!.minimumSize!
              .resolve(<WidgetState>{})!.height,
          48,
          reason: '$p meets the floor');
    }
  });
}
