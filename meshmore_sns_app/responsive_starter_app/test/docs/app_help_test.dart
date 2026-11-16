// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The in-app reference has to keep up with the app.
///
/// `assets/docs/app.md` is the Docs -> App page: the only prose a reader sees
/// inside the app about what a feature does. It was a 94-line summary while the
/// app grew to eleven themes, five grid views, six tools and a fence engine, and
/// the backlog row that asked for per-feature help ("online-help-md") sat undone
/// because nothing failed when the page fell behind.
///
/// Three things are pinned here, and all three are cheap:
///
///  * the page states its own contents, and every entry in that list is a
///    heading that exists. A section renamed in one place and not the other is
///    the ordinary way a long page stops matching itself;
///  * the feature families the app actually ships each have a section, so
///    deleting one is a test failure rather than a silent omission;
///  * the page follows the owner's copy rules, because it is read inside the
///    app and those rules are about what a reader sees, not about which file the
///    string happens to live in.
void main() {
  final File asset = File('assets/docs/app.md');

  /// The families this page is expected to cover, spelled as the headings use
  /// them. Adding a top-level feature means adding a heading.
  const List<String> requiredSections = <String>[
    'Finding and pairing a radio',
    'The six views, and moving between them',
    'Channels',
    'Direct messages, reactions, pictures, voice notes',
    'Nodes, the tree and routes',
    'The map',
    'Places',
    'Geofences',
    'The hyperlocal grid',
    'Tools',
    'Safety: check-in and the alarm',
    'Notifications and the background link',
    'Sound, haptics and speech',
    'Themes, type and reading comfort',
    'Settings, storage and what is kept where',
    'What this app cannot do, and why',
  ];

  List<String> headings(String source) => <String>[
        for (final String line in source.split('\n'))
          if (line.startsWith('## ')) line.substring(3).trim(),
      ];

  test('the page lists its own contents and every entry is a heading', () {
    final String source = asset.readAsStringSync();
    final int start = source.indexOf('## Contents');
    expect(start, greaterThan(-1), reason: 'the page states no contents');
    final int end = source.indexOf('\n## ', start + 4);
    final String contents =
        source.substring(start + '## Contents'.length, end);

    final List<String> listed = <String>[
      for (final String line in contents.split('\n'))
        if (line.trimLeft().startsWith('- '))
          line.trimLeft().substring(2).trim(),
    ];
    expect(listed, isNotEmpty,
        reason: 'the contents list holds no entries: $contents');

    final Set<String> have = headings(source).toSet();
    final List<String> missing = listed.where((String s) => !have.contains(s)).toList();
    expect(missing, isEmpty,
        reason: 'these contents entries name no heading: $missing');
  });

  test('every feature family the app ships has a section', () {
    final Set<String> have = headings(asset.readAsStringSync()).toSet();
    final List<String> missing =
        requiredSections.where((String s) => !have.contains(s)).toList();
    expect(missing, isEmpty,
        reason: 'the in-app reference does not cover: $missing');
  });

  test('the page follows the copy rules, because a reader sees it', () {
    final String source = asset.readAsStringSync();
    final List<String> offenders = <String>[];
    for (final String line in source.split('\n')) {
      // Thematic breaks and table rules are typography, not prose.
      if (line.trim() == '---') continue;
      if (line.contains('\u2014')) offenders.add('em dash: $line');
      if (line.contains(';')) offenders.add('semicolon: $line');
    }
    expect(offenders, isEmpty,
        reason: 'the copy rules apply to this page too:\n'
            '${offenders.join('\n')}');
  });
}
