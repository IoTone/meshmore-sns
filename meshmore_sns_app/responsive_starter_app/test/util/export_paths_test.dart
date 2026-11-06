// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// An export is only an export if something outside the app can open it.
///
/// The share channel turns a file into a `content://` URI through the
/// FileProvider, and the provider can only serve files under the roots its
/// `file_paths.xml` declares. `getApplicationDocumentsDirectory()` is not one
/// of them (on Android it resolves under `app_flutter`), so a file written
/// there cannot be shared at all: `FileProvider.getUriForFile` throws and the
/// user is handed an app-private path instead.
///
/// This guards the mapping rather than one call site: the roots, the directory
/// each export writes to, and the absence of the uncovered directory.
void main() {
  final File xml =
      File('android/app/src/main/res/xml/file_paths.xml');
  final List<File> sources = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((File f) => f.path.endsWith('.dart'))
      .toList();

  /// The directories the provider serves: `<files-path>` is `filesDir`
  /// (`getApplicationSupportDirectory`), `<cache-path>` is `cacheDir`
  /// (`getTemporaryDirectory`).
  const Map<String, String> roots = <String, String>{
    'files-path': 'getApplicationSupportDirectory',
    'cache-path': 'getTemporaryDirectory',
  };

  test('the provider declares the roots the exports write to', () {
    final String declared = xml.readAsStringSync();
    for (final String root in roots.keys) {
      expect(declared.contains('<$root '), isTrue,
          reason: '$root is where one kind of export lives; without it the '
              'file has no shareable URI');
    }
  });

  test('no code writes an export where the provider cannot serve it', () {
    final List<String> offenders = <String>[
      for (final File f in sources)
        if (f.readAsStringSync().contains('getApplicationDocumentsDirectory'))
          f.path,
    ];
    expect(offenders, isEmpty,
        reason: 'the documents directory is not under any FileProvider root: '
            'use getApplicationSupportDirectory (persistent) or '
            'getTemporaryDirectory (transient)');
  });

  // Who shares, and where that file was written. A new export has to be
  // declared here, which is the point: the declaration is where a reviewer
  // sees which directory it lives in.
  const Map<String, List<String>> exports = <String, List<String>>{
    'lib/places/place_history_sheet.dart': <String>[],
    // The chat history export and the report bundle both left the screen for
    // their own files when the chat strip was reorganised, so the declaration
    // names where the share now lives rather than the screen that opens it.
    'lib/chat/history_export_action.dart': <String>[],
    // The bundle is written by the builder, which owns the directory and
    // the temporary-file decision; this site only hands the file on.
    'lib/chat/report_flow.dart': <String>['lib/screens/report_bundle.dart'],
    // One thread, from the conversation itself. Distinct from
    // `lib/chat/history_export_action.dart`, which writes the whole
    // history from Settings: handing over one conversation must not
    // hand over the rest.
    'lib/screens/chat_screen.dart': <String>[],
    'lib/field/field_export_action.dart': <String>[
      'lib/field/operational_export.dart',
    ],
    'lib/field/gpx_export_action.dart': <String>[
      'lib/field/gpx.dart',
    ],
  };

  test('every share site is declared, and declared writers use a served root',
      () {
    final List<String> sites = <String>[
      for (final File f in sources)
        if (f.readAsStringSync().contains('Share.file(')) f.path,
    ];
    expect(sites.toSet(), exports.keys.toSet(),
        reason: 'a new export must say which directory it writes to');

    for (final MapEntry<String, List<String>> e in exports.entries) {
      // A site that writes in place must name the getter itself; a site that
      // delegates must name the writer, and the writer must name the getter.
      final List<String> bodies = <String>[
        if (e.value.isEmpty) e.key,
        ...e.value,
      ].map((String path) => File(path).readAsStringSync()).toList();
      final bool served = bodies.any(
          (String body) => roots.values.any((String g) => body.contains(g)));
      if (!served) {
        fail('${e.key} shares a file but writes it somewhere the provider '
            'does not serve; use one of ${roots.values.join(', ')}');
      }
    }
  });
}
