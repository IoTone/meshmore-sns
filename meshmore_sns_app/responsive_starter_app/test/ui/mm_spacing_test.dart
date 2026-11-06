// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/theme/mm_skin.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';
import 'package:meshmore_sns_app/ui/mm_components.dart';
import 'package:provider/provider.dart';

/// The spacing ratchet, and the invariants the contract rests on.
///
/// The ladder existed for two waves while the surfaces used hand-picked
/// numbers: three off-ladder values (10, 14, 18) accounted for 92 insets and
/// 70 gaps, so nothing lined up between screens and no group boundary was
/// visibly larger than a gap inside a group. The rule that makes a group
/// readable is written down in [MmSpace]: a between-gap is always strictly
/// larger than the within-gap it contains.
///
/// Three guards, lower-only in the style of `test/theme/mm_ratchet_test.dart`:
///
///  1. the count of off-ladder numbers in `EdgeInsets.*` and in a
///     `SizedBox(height|width:)` may not grow per file;
///  2. the shared tokens and the job getters must be ladder members, so
///     nobody "fixes" a 14 by adding 14 to the ladder;
///  3. a row's text starts at the same offset in every skin, because the card
///     and flat paint modes differ in paint and not in metrics.
void main() {
  /// The ladder plus the two values that are legitimately not steps: zero (no
  /// padding) and one (a hairline).
  const Set<int> allowed = <int>{0, 1, 2, 4, 6, 8, 12, 16, 20, 24, 32};

  /// The ladder is where literals belong; `lib/gen` is generated.
  const Set<String> exempt = <String>{'lib/theme/mm_skin.dart'};

  List<File> scanned() {
    return <File>[
      for (final FileSystemEntity e
          in Directory('lib').listSync(recursive: true))
        if (e is File && e.path.endsWith('.dart'))
          if (!e.path.replaceAll('\\', '/').startsWith('lib/gen/') &&
              !e.path.replaceAll('\\', '/').startsWith('lib/theme/') &&
              !exempt.contains(e.path.replaceAll('\\', '/')))
            e,
    ];
  }

  String rel(File f) => f.path.replaceAll('\\', '/');

  /// The integers inside a balanced argument list whose opening parenthesis is
  /// at [start].
  List<int> argumentInts(String src, int start) {
    final List<int> out = <int>[];
    int depth = 0;
    int i = start;
    while (i < src.length) {
      final String c = src[i];
      if (c == '(') {
        depth++;
      } else if (c == ')') {
        depth--;
        if (depth == 0) return out;
      } else if (c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39) {
        final Match? m =
            RegExp(r'\d+(?:\.\d+)?').matchAsPrefix(src.substring(i));
        if (m != null) {
          final String lit = m.group(0)!;
          if (!lit.contains('.')) out.add(int.parse(lit));
          i += lit.length - 1;
        }
      }
      i++;
    }
    return out;
  }

  int offLadder(String raw) {
    // `step(n)` and `pad(n)` are references to the ladder, not literals: an
    // argument of 5 there means "the fifth step", which is 12 px.
    final String src =
        raw.replaceAll(RegExp(r'\b(?:step|pad)\(\s*\d+\s*\)'), 'step()');
    int n = 0;
    for (final RegExpMatch m in RegExp(r'EdgeInsets\.\w+').allMatches(src)) {
      final int j = src.indexOf('(', m.end);
      if (j < 0 || j > m.end + 2) continue;
      for (final int v in argumentInts(src, j)) {
        if (!allowed.contains(v)) n++;
      }
    }
    final RegExp sized = RegExp(r'SizedBox\(\s*(?:height|width):\s*(\d+(?:\.\d+)?)');
    for (final RegExpMatch m in sized.allMatches(src)) {
      final String lit = m.group(1)!;
      if (!lit.contains('.') && !allowed.contains(int.parse(lit))) n++;
    }
    return n;
  }

  test('off-ladder spacing per file: no file grows past its baseline', () {
    // Seeded from the census in the rhythm audit, lowered by every screen this
    // wave migrated. A file leaves the map when it reaches zero.
    const Map<String, int> baseline = <String, int>{
      'lib/bot/bot_scope_config.dart': 1,
      'lib/bot/bot_section.dart': 1,
      'lib/bot/bot_tag.dart': 1,
      'lib/chat/studio_message_row.dart': 1,
      'lib/docs/markdown_view.dart': 4,
      'lib/maps/basemap.dart': 1,
      'lib/screens/about_screen.dart': 6,
      'lib/screens/battery_screen.dart': 4,
      'lib/screens/channels_screen.dart': 6,
      'lib/screens/chat_screen.dart': 3,
      'lib/screens/checkin_screen.dart': 1,
      'lib/screens/dashboards/aghud_dashboard.dart': 1,
      'lib/screens/dashboard_screen.dart': 4,
      'lib/screens/dashboards/recon_dashboard.dart': 3,
      'lib/screens/dashboards/studio_dashboard.dart': 1,
      'lib/screens/device_manager_sheet.dart': 5,
      'lib/screens/dm_screen.dart': 2,
      'lib/screens/doc_reader_screen.dart': 2,
      'lib/screens/docs_hub_screen.dart': 5,
      'lib/screens/elevation_profile_view.dart': 2,
      'lib/screens/equal_grid_view.dart': 1,
      'lib/screens/fabric_survey_view.dart': 1,
      'lib/screens/first_run_intro_screen.dart': 4,
      'lib/screens/globe_view.dart': 2,
      'lib/screens/location_settings_screen.dart': 1,
      'lib/screens/meshbook_view.dart': 14,
      'lib/screens/mesh_tree_view.dart': 2,
      'lib/screens/node_detail_sheet.dart': 3,
      'lib/screens/nodes_screen.dart': 4,
      'lib/screens/pair_radio_screen.dart': 10,
      'lib/screens/personalization_screen.dart': 2,
      'lib/screens/sns_cells_view.dart': 2,
      'lib/screens/sos_screen.dart': 1,
      'lib/screens/street_map_view.dart': 1,
      'lib/screens/tools/tool_widgets.dart': 4,
      'lib/screens/tools/trace_screen.dart': 3,
      'lib/screens/voice_settings_screen.dart': 1,
      'lib/screens/weather_view.dart': 12,
      'lib/shell/home_shell.dart': 3,
      'lib/splash/branded_splash_screen.dart': 1,
      'lib/ui/mm_components.dart': 5,
      'lib/ui/mm_edge_swipe.dart': 1,
    };

    // Exact equality, in both directions: a migration lowers its entry in the
    // same commit, and a new literal raises the count past it.
    final List<String> wrong = <String>[];
    for (final File f in scanned()) {
      final int count = offLadder(f.readAsStringSync());
      final int limit = baseline[rel(f)] ?? 0;
      if (count != limit) wrong.add('${rel(f)}: $count, baseline says $limit');
    }
    expect(
      wrong,
      isEmpty,
      reason: 'Off-ladder spacing. Use a job from MmSpace (insideText, '
          'labelToControl, rowGap, rowInset, screenEdge, sectionGap, '
          'emptyState) instead of a number, and set the file\'s baseline to '
          'the count you measured in the same commit.',
    );
  });

  test('the shared tokens are ladder members', () {
    final Set<double> steps = MmSpace.steps.toSet();
    expect(steps.contains(kPadPanel), isTrue,
        reason: 'kPadPanel must be a spacing step, not a value between two');
  });

  test('the jobs order the gaps the way the contract says', () {
    const MmSpace s = MmSpace();
    expect(s.insideText, lessThan(s.labelToControl));
    expect(s.labelToControl, lessThan(s.rowGap));
    expect(s.rowGap, lessThan(s.rowInset));
    expect(s.rowInset, lessThan(s.screenEdge));
    expect(s.screenEdge, lessThan(s.sectionGap));
    expect(s.sectionGap, lessThan(s.emptyState));
    for (final double v in <double>[
      s.insideText,
      s.labelToControl,
      s.rowGap,
      s.rowInset,
      s.screenEdge,
      s.sectionGap,
      s.emptyState,
    ]) {
      expect(MmSpace.steps.contains(v), isTrue, reason: 'job $v is not a step');
    }
  });

  testWidgets('a row keeps its text offset in every skin',
      (WidgetTester tester) async {
    // Card and flat paint modes differ in paint, never in metrics: the title
    // starts at the same offset in all eight presets, so a list does not shift
    // sideways when the skin changes.
    final Map<MmThemePreset, double> offsets = <MmThemePreset, double>{};
    for (final MmThemePreset preset in MmThemePreset.values) {
      final ThemeController tc = ThemeController();
      await tc.setPreset(preset);
      final MmSkin skin = mmSkinFor(preset);
      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeController>.value(
          value: tc,
          child: MaterialApp(
            theme: tc.theme,
            home: Builder(
              builder: (BuildContext context) {
                return Scaffold(
                  body: Center(
                    child: SizedBox(
                      width: 320,
                      child: MmListRow(
                        onTap: () {},
                        leading: Icon(Icons.circle, color: skin.color.fg),
                        title: Text(
                          'row title',
                          style: TextStyle(color: skin.color.fg),
                        ),
                        subtitle: Text(
                          'subtitle',
                          style: TextStyle(color: skin.color.fgMuted),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // The gap between the leading icon and the title is the row's own
      // metric: it must be the row gap in every skin and in both paint modes.
      // The absolute left inset is not asserted here because a skin's border
      // width legitimately insets the content by up to 2 px.
      final double iconRight =
          tester.getTopRight(find.byIcon(Icons.circle)).dx;
      final double titleLeft = tester.getTopLeft(find.text('row title')).dx;
      offsets[preset] = titleLeft - iconRight;
      expect(offsets[preset], closeTo(skin.space.rowGap, 0.6),
          reason: 'the leading gap must be the row gap');
    }
    expect(offsets.values.toSet(), hasLength(1),
        reason: 'the leading gap differs between skins: $offsets');
  });
}
