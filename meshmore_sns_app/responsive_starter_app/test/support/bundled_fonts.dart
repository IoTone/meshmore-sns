// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:flutter/services.dart';

/// Load every font the app bundles, for tests that measure text.
///
/// A widget test does not use the app's real font files: until a family is
/// loaded through [FontLoader] the engine falls back to a default face, and a
/// fallback has different advances. That is harmless for a test that taps a
/// button and wrong for one that measures a row's width or asserts an overflow
/// boundary at 320 dp — the numbers belong to whatever face was rendered.
///
/// Four suites had written this as a hand-written map of two families
/// (`Saira`, `JetBrains Mono`). The app now sets each preset in its own
/// monospace face, so a map of two is a test that silently measures the wrong
/// face as soon as it renders a preset whose face is not in it. This reads the
/// families out of `pubspec.yaml` instead, so it cannot fall behind — the same
/// reason `test/theme/mono_faces_test.dart` reads them rather than listing
/// them.
Future<void> loadBundledFonts() async {
  for (final MapEntry<String, String> e in bundledFontFiles().entries) {
    final FontLoader loader = FontLoader(e.key)
      ..addFont(Future<ByteData>.value(
          ByteData.sublistView(File(e.value).readAsBytesSync())));
    await loader.load();
  }
}

/// Family name to font file, in the order `pubspec.yaml` declares them.
///
/// Read as text rather than through a YAML parser: `yaml` is not a declared
/// dependency, and a test helper that pulls one in to read six lines is a
/// dependency added to avoid reading six lines.
Map<String, String> bundledFontFiles() {
  final List<String> lines = File('pubspec.yaml').readAsLinesSync();
  final Map<String, String> out = <String, String>{};
  String? family;
  bool inFonts = false;
  for (final String line in lines) {
    if (line.trimRight() == '  fonts:') {
      inFonts = true;
      continue;
    }
    if (!inFonts) continue;
    if (line.isNotEmpty && !line.startsWith('    ') && !line.startsWith('  #')) {
      break;
    }
    final RegExpMatch? f = RegExp(r'^\s*- family: (.+)$').firstMatch(line);
    if (f != null) {
      family = f.group(1)!.trim();
      continue;
    }
    final RegExpMatch? a = RegExp(r'^\s*- asset: (.+)$').firstMatch(line);
    if (a != null && family != null) {
      // One file per family is enough to register the face; the weight cuts
      // are matched from the pubspec by the engine, not by this loader.
      out.putIfAbsent(family, () => a.group(1)!.trim());
    }
  }
  return out;
}
