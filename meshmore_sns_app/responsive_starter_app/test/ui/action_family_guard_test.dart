// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// One action shape per screen, and the class may only shrink.
///
/// The audit of 2026-11-14 counted six action families across the screens
/// (`FilledButton`, `FilledButton.icon`, `OutlinedButton`, `OutlinedButton.icon`,
/// `TextButton`, `MmAction`) plus `IconButton`, and found the same commit act
/// hosted eight different ways. The worst screens carried five families at once
/// (`node_detail_sheet`, `channels_screen`), and the screen the owner named —
/// Device configuration — carried four, which is why its two save actions read
/// as unrelated objects.
///
/// `MmAction` is the app's action primitive (R99: a text-shaped action that
/// still reads as a control) and `MmAction.primary` is its emphasis, so a group
/// never needs a second family. This ratchet holds the count of Material action
/// families per screen file, in the style of `mm_ratchet_test.dart` and
/// `tap_affordance_guard_test.dart`: a conversion lowers the number, a new one
/// fails, and a stale baseline fails too, so an entry cannot outlive its file's
/// defect. When a file reaches zero its entry is deleted.
///
/// `TextButton` is not counted: a dialog's Cancel is a text button by the
/// convention every dialog in this app follows, and `tap_affordance_guard_test`
/// already ratchets the page-level ones. `IconButton` is not counted either:
/// an app-bar action or a list row's trailing control is an icon on purpose,
/// and the rule there is a label in `Semantics` (same test).
void main() {
  /// Seeded 2026-11-14 from the tree after Device configuration was converted.
  /// Counts are constructor invocations, so a comment naming a family does not
  /// count (no `(` directly after the name).
  const Map<String, int> baseline = <String, int>{
    // Save / reset / generate / copy / share, most of them inside dialogs.
    'lib/screens/channels_screen.dart': 3,
    // Disconnect / reconnect / forget in one row.
    // Copy fixture and export fixtures: file-shaped verbs.
    'lib/screens/diagnostics_screen.dart': 2,
    // The first-run intro's Grant / Continue / Skip steps.
    // The map-pack dialogs (delete, download) and the tile budget.
    'lib/screens/maps/maps_screen.dart': 6,
    'lib/screens/maps/maps_self_test_screen.dart': 2,
    'lib/screens/maps/new_pack_screen.dart': 1,
    // A view's own zoom / centre controls.
    'lib/screens/mesh_tree_view.dart': 1,
    // Apply to this MeshCore radio, and the member editor's save.
    'lib/screens/network_detail_screen.dart': 2,
    // A new network (the app's one FAB) and the editor's save.
    'lib/screens/networks_screen.dart': 2,
    // Message / favourite / device contact / show on map / copy / link / remove.
    'lib/screens/node_detail_sheet.dart': 7,
    // Scan area, advertise, and the sync affordance.
    'lib/screens/nodes_screen.dart': 3,
    // The pairing sheet's connect / scan / forget.
    'lib/screens/pair_radio_screen.dart': 6,
    // The grid's own cell actions.
    'lib/screens/sns_cells_view.dart': 2,
    'lib/screens/sos_screen.dart': 1,
    'lib/screens/terms_screen.dart': 1,
    'lib/screens/tools/radio_stats_screen.dart': 1,
    'lib/screens/tools/tool_widgets.dart': 4,
    'lib/screens/voice_settings_screen.dart': 1,
  };

  final RegExp family = RegExp(
      r'\b(FilledButton|OutlinedButton|ElevatedButton|FloatingActionButton)'
      r'(\.icon|\.tonalIcon|\.extended)?\(');

  int countIn(File f) => family.allMatches(f.readAsStringSync()).length;

  test('no screen file grows its Material action families', () {
    final List<String> failures = <String>[];
    for (final MapEntry<String, int> e in baseline.entries) {
      final File f = File(e.key);
      if (!f.existsSync()) {
        failures.add('${e.key}: baseline for a file that does not exist');
        continue;
      }
      final int now = countIn(f);
      if (now > e.value) {
        failures.add('${e.key}: $now > ${e.value} — a new Material action family '
            'was added; use MmAction (primary: for the group\'s own write) '
            'inside an MmActionRow');
      } else if (now < e.value) {
        failures.add('${e.key}: $now < ${e.value} — the defect went away, so '
            'lower the baseline to $now (or delete the entry at zero)');
      }
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  test('a screen that is not in the baseline has none', () {
    final List<String> failures = <String>[];
    for (final FileSystemEntity e
        in Directory('lib/screens').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      final String path = e.path.replaceAll(r'\', '/');
      if (baseline.containsKey(path)) continue;
      final int now = countIn(e);
      if (now > 0) {
        failures.add('$path: $now Material action families — either convert '
            'them to MmAction/MmActionRow or add a justified baseline entry');
      }
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  test('Device configuration has none, and its writes are MmAction.primary',
      () {
    // The screen the owner named. It is the proof the rule is reachable, so it
    // is the one file that may not fall back.
    expect(countIn(File('lib/screens/device_config_screen.dart')), 0);
    expect(baseline.containsKey('lib/screens/device_config_screen.dart'), isFalse,
        reason: 'a file at zero has no baseline entry');
  });
}
