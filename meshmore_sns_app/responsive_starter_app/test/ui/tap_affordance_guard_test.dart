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

/// The index of the `)` that closes the `(` at [open], or -1.
///
/// Known limit: a `//` inside a row's arguments is not skipped, so a comment
/// containing a `)` would end the row early. The failure direction is a row
/// that looks shorter than it is, which over-counts and fails loudly.
int _closeParen(String src, int open) {
  int depth = 0;
  String? quote;
  for (int i = open; i < src.length; i++) {
    final String c = src[i];
    if (quote != null) {
      if (c == r'\\') {
        i++;
      } else if (c == quote) {
        quote = null;
      }
      continue;
    }
    if (c == "'" || c == '"') {
      quote = c;
      continue;
    }
    if (c == '(') {
      depth++;
    } else if (c == ')') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

void main() {
  /// `TextButton`s that read as labels today.
  ///
  /// What is left is one shape and one only: a **dialog's action row**, where a
  /// Cancel (or a Close, or a destructive Clear) sits beside the filled confirm
  /// that ends the dialog. That is the convention the other thirty files
  /// already follow, and a dialog is not a page: its buttons are the last thing
  /// in a modal, not an offer in a scroll view. Every page-level button has been
  /// converted to `MmAction`, which is why the counts below are all dialog rows.
  const Map<String, int> textButtons = <String, int>{
    // The rulepack editor: Restore, Cancel, Save.
    'lib/bot/bot_scope_config.dart': 2,
    // The passphrase prompt: Cancel beside the filled Unlock.
    'lib/chat/export_passphrase_dialog.dart': 1,
    // The report bundle dialog (Copy, Share, Close) and the observation prompt
    // (Cancel beside the filled Report).
    'lib/chat/report_flow.dart': 5,
    // The composer's Close beside the filled Send.
    'lib/media/media_composer.dart': 1,
    // The place sheet's Cancel beside the filled Send.
    'lib/places/place_create_sheet.dart': 1,
    // The import dialog's Cancel beside the filled Go.
    'lib/places/place_import_sheet.dart': 1,
    // The channel editor: Clear (destructive), Cancel, Save; and the two
    // single-button dialogs (the key prompt's Cancel, the QR sheet's Close).
    'lib/screens/channels_screen.dart': 4,
    // The region disclaimer's Close.
    'lib/screens/device_config_screen.dart': 1,
    // Two single-button dialogs: the contact add and the contact remove.
    'lib/screens/device_contacts_screen.dart': 2,
    // The layer, source and pack dialogs: Cancel beside the filled Add.
    'lib/screens/maps/maps_screen.dart': 3,
    // The tag dialog's Cancel beside the filled Apply.
    'lib/screens/node_detail_sheet.dart': 1,
    // The alarm's Cancel beside the filled Stop.
    'lib/screens/sos_screen.dart': 1,
    // The terms gate: Exit beside the filled Accept.
    'lib/screens/terms_screen.dart': 1,
    // The one confirmation dialog (R130): a Cancel beside a filled confirm, in
    // one place instead of seventeen.
    'lib/ui/mm_confirm.dart': 1,
    // The delete-everything dialog: a Cancel beside a filled destructive
    // confirm.
    'lib/ui/storage_use_block.dart': 1,
  };

  /// Rows that open a choice or a page with nothing in the trailing slot.
  ///
  /// Empty as of this pass. The scan used to end a row at the next
  /// `\n        )`, which ran past a short row and swallowed the widget after
  /// it, so it both missed real bare rows and counted a `SwitchListTile` as one.
  /// With the row's own parentheses matched, the eleven rows it had been
  /// missing were fixed: a chevron where the row opens something, the radio
  /// moved to the trailing slot where the row is a choice, and the one action
  /// row converted to `MmAction`.
  const Map<String, int> pickerRows = <String, int>{};

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
        // The row's own argument list, found by matching its parentheses.
        // It used to be "up to the next `\n        )`", which ran past the end
        // of a short row and swallowed the widget after it: a `SwitchListTile`
        // followed by an action row was counted as one bare picker row, and the
        // count could not be lowered by fixing either of them.
        final int end = _closeParen(src, m.end - 1);
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
