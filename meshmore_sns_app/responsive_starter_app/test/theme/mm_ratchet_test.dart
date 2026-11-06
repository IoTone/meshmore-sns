// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// W2 — the size and colour ratchet.
///
/// Two source scans, both **lower-only**, in the same style as
/// `test/ui/type_rule_guard_test.dart` (the mono face) and
/// `test/ui/square_controls_guard_test.dart` (control radii): the number of
/// literal type sizes and the number of literal colours a file carries may not
/// grow, so the screens that have not been migrated yet stop accumulating new
/// ones, and every migration lowers its own entry in the same commit.
///
/// What is NOT enforceable by a scan: whether a number is the *right* step.
/// That is a judgement each migration records (see `meshmore-sns-UX-spec.md`,
/// type scale) — the roles live in `MmType`, the spacings in `MmSpace`.
void main() {
  const Set<String> exempt = <String>{
    // Runs before the provider tree exists, so no skin can be read.
    'lib/shell/boot_overlay.dart',
    // Generated licence text in its own fixed style.
    'lib/licenses/asset_licenses.dart',
  };

  /// Files a scan may read: `lib/**` minus generated l10n, minus the token
  /// layer itself (that is where the literals are *supposed* to live), minus
  /// the two files that have no skin to read.
  List<File> scanned() => <File>[
        for (final FileSystemEntity e
            in Directory('lib').listSync(recursive: true))
          if (e is File && e.path.endsWith('.dart'))
            if (!e.path.replaceAll('\\', '/').startsWith('lib/gen/') &&
                !e.path.replaceAll('\\', '/').startsWith('lib/theme/') &&
                !exempt.contains(e.path.replaceAll('\\', '/')))
              e,
      ];

  String rel(File f) => f.path.replaceAll('\\', '/');

  final RegExp fontSize = RegExp(r'fontSize:\s*\d+(?:\.\d+)?');
  final RegExp colour = RegExp(r'Color\(0x|Colors\.(\w+)');

  int countColours(String source) {
    int n = <RegExpMatch>[
      for (final RegExpMatch m in colour.allMatches(source))
        if (m.group(0) == 'Color(0x' ||
            (m.group(1) != null && m.group(1) != 'transparent'))
          m
    ].length;
    return n;
  }

  test('literal type sizes per file: no file grows past its baseline', () {
    const Map<String, int> baseline = <String, int>{
      'lib/bot/bot_scope_config.dart': 2,
      'lib/bot/bot_section.dart': 4,
      'lib/bot/bot_tag.dart': 1,
      'lib/chat/studio_message_row.dart': 4,
      'lib/docs/markdown_view.dart': 5,
      'lib/maps/basemap.dart': 1,
      'lib/screens/about_screen.dart': 5,
      'lib/screens/battery_screen.dart': 10,
      'lib/screens/chat_screen.dart': 8,
      'lib/screens/device_contacts_screen.dart': 6,
      'lib/screens/device_manager_sheet.dart': 10,
      'lib/screens/dm_screen.dart': 3,
      'lib/screens/doc_reader_screen.dart': 1,
      'lib/screens/elevation_profile_view.dart': 8,
      'lib/screens/fabric_survey_view.dart': 2,
      'lib/screens/first_run_intro_screen.dart': 1,
      'lib/screens/globe_view.dart': 6,
      'lib/screens/maps/maps_screen.dart': 6,
      'lib/screens/maps/maps_self_test_screen.dart': 1,
      'lib/screens/maps/new_pack_screen.dart': 1,
      'lib/screens/mesh_tree_view.dart': 4,
      'lib/screens/meshbook_view.dart': 10,
      'lib/screens/nodes_screen.dart': 6,
      'lib/screens/personalization_screen.dart': 1,
      'lib/screens/sns_cells_view.dart': 3,
      'lib/screens/tools/tool_widgets.dart': 3,
      'lib/screens/tools/trace_screen.dart': 2,
      'lib/screens/voice_settings_screen.dart': 9,
    };
    final List<String> drifted = <String>[];
    for (final File f in scanned()) {
      final int n = fontSize.allMatches(f.readAsStringSync()).length;
      final int was = baseline[rel(f)] ?? 0;
      if (n > was) {
        drifted.add('${rel(f)}: $n literals, baseline $was — '
            'use skin.type.sizeSm / sizeBody / size(...) instead');
      } else if (n < was) {
        drifted.add('${rel(f)}: $n literals, baseline $was — lower the entry');
      }
    }
    expect(drifted, isEmpty, reason: drifted.join('\n'));
  });

  test('literal colours per file: no file grows past its baseline', () {
    const Map<String, int> baseline = <String, int>{
      'lib/maps/basemap.dart': 1,
      'lib/maps/vector_basemap.dart': 1,
      'lib/screens/battery_screen.dart': 2,
      'lib/screens/channels_screen.dart': 2,
      'lib/screens/chat_screen.dart': 7,
      'lib/screens/dashboards/drpop_dashboard.dart': 3,
      'lib/screens/fabric_survey_view.dart': 4,
      'lib/screens/personalization_screen.dart': 1,
      'lib/screens/sns_cells_view.dart': 5,
      // R115 — the peer and self markers lost their three `Colors.white`
      // rings in favour of the skin's foreground, so the count is what the
      // file actually carries.
      'lib/screens/street_map_view.dart': 2,
      'lib/ui/mm_scaffold.dart': 1,
    };
    final List<String> drifted = <String>[];
    for (final File f in scanned()) {
      final int n = countColours(f.readAsStringSync());
      final int was = baseline[rel(f)] ?? 0;
      if (n > was) {
        drifted.add('${rel(f)}: $n literals, baseline $was — '
            'use skin.color.*, or a declared encoding in viz_palette');
      } else if (n < was) {
        drifted.add('${rel(f)}: $n literals, baseline $was — lower the entry');
      }
    }
    expect(drifted, isEmpty, reason: drifted.join('\n'));
  });

  test('a corner radius is never a bare number outside the token layer', () {
    // `lib/theme` builds the theme; `mm_shape` owns the constants and the
    // helper; the two older-preset dashboards predate the guard and are the
    // same two files the >=6px rule allows.
    const Set<String> allowed = <String>{
      'lib/ui/mm_shape.dart',
      'lib/screens/dashboards/aghud_dashboard.dart',
      'lib/screens/dashboards/hyperlocal_dashboard.dart',
    };
    final RegExp literal = RegExp(r'BorderRadius\.circular\(\s*[0-9.]');
    final List<String> bad = <String>[];
    for (final File f in scanned()) {
      if (allowed.contains(rel(f))) continue;
      if (literal.hasMatch(f.readAsStringSync())) {
        bad.add('${rel(f)} — use kRadiusXs / kRadiusSm / kRadiusMd, or '
            'mmRadius(context, …) for a control surface');
      }
    }
    expect(bad, isEmpty, reason: bad.join('\n'));
  });
}
