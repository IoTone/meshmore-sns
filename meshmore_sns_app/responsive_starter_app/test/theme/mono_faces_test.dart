// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:meshmore_sns_app/theme/mm_skin.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';

/// The monospace face is the preset's, and the preset's face is bundled.
///
/// The owner's decision (2026-11-09): the dark look is set in Fira Mono, and
/// the other presets take the face their LDMUX counterpart was designed
/// against. The face matters more than a typeface usually does here because
/// every monospace column in this app is *measured* — the radar readout, the
/// key rows, the frame log, the hop lists — so a face that comes from the
/// device instead of the bundle changes the advance of every column and
/// re-grids those screens phone by phone.
///
/// These cases pin the mapping, the files behind it, and the rule that no
/// widget may pick a face of its own.
void main() {
  /// The decided mapping, in one place. Changing a preset's face is a decision
  /// with a palette review beside it, not an edit here.
  const Map<MmThemePreset, String> expected = <MmThemePreset, String>{
    MmThemePreset.studio: 'Fira Mono',
    MmThemePreset.forest: 'Fira Mono',
    MmThemePreset.air: 'JetBrains Mono',
    MmThemePreset.daybreak: 'Source Code Pro',
    MmThemePreset.umber: 'Geist Mono',
    MmThemePreset.nerv: 'Cascadia Code',
    // David's concept skins with no LDMUX counterpart keep the bundled face
    // they shipped with: a face chosen for them here would be a restyle nobody
    // asked for.
    MmThemePreset.seele: 'JetBrains Mono',
    MmThemePreset.agHud: 'JetBrains Mono',
    MmThemePreset.hyperlocal: 'JetBrains Mono',
    MmThemePreset.drPop: 'JetBrains Mono',
    MmThemePreset.recon: 'JetBrains Mono',
  };

  /// The `family:` and `asset:` lines under the pubspec's `fonts:` key.
  ///
  /// Read as text rather than with a YAML parser: `yaml` is not a declared
  /// dependency of this app, and a test that imports one to read six lines is
  /// a dependency added to avoid six lines of reading.
  ({Map<String, List<String>> families}) declaredFaces() {
    final List<String> lines = File('pubspec.yaml').readAsLinesSync();
    final Map<String, List<String>> families = <String, List<String>>{};
    String? current;
    bool inFonts = false;
    for (final String line in lines) {
      if (line.trimRight() == '  fonts:') {
        inFonts = true;
        continue;
      }
      if (!inFonts) continue;
      // The fonts block ends at the next `key:` at the same indent or less.
      if (line.isNotEmpty && !line.startsWith('    ') && !line.startsWith('  #')) {
        break;
      }
      final RegExpMatch? family = RegExp(r'^\s*- family: (.+)$').firstMatch(line);
      if (family != null) {
        current = family.group(1)!.trim();
        families[current] = <String>[];
        continue;
      }
      final RegExpMatch? asset = RegExp(r'^\s*- asset: (.+)$').firstMatch(line);
      if (asset != null && current != null) {
        families[current]!.add(asset.group(1)!.trim());
      }
    }
    return (families: families);
  }

  test('every preset is set in its decided face', () {
    expect(expected.keys.toSet(), MmThemePreset.values.toSet(),
        reason: 'the mapping has to be total: a new preset needs a face');
    for (final MapEntry<MmThemePreset, String> e in expected.entries) {
      expect(mmSkinFor(e.key).type.monoFamily, e.value, reason: e.key.name);
    }
  });

  test('every declared family has its files on disk', () {
    final Map<String, List<String>> families = declaredFaces().families;
    expect(families.keys, containsAll(<String>['Saira', 'JetBrains Mono']));
    for (final MapEntry<String, List<String>> e in families.entries) {
      expect(e.value, isNotEmpty, reason: '${e.key} declares no cuts');
      for (final String asset in e.value) {
        expect(File(asset).existsSync(), isTrue,
            reason: '${e.key} declares $asset and it is not there');
      }
    }
  });

  test('every face a preset draws is a declared family', () {
    // A mapping that named a family nobody declared would fall back to the
    // platform's monospace, which is the thing a bundled face exists to stop.
    final Set<String> declared = declaredFaces().families.keys.toSet();
    for (final MmThemePreset p in MmThemePreset.values) {
      expect(declared, contains(mmSkinFor(p).type.monoFamily),
          reason: '${p.name} draws a face that is not bundled');
    }
  });

  test('the two cuts of each new family are different files', () {
    // A "bold" that is a copy of the regular renders bold text at the regular
    // weight: invisible in a layout test, obvious on a phone.
    const List<List<String>> pairs = <List<String>>[
      <String>[
        'assets/fonts/fira_mono_regular.ttf',
        'assets/fonts/fira_mono_bold.ttf',
      ],
      <String>[
        'assets/fonts/source_code_pro_regular.ttf',
        'assets/fonts/source_code_pro_bold.ttf',
      ],
      <String>[
        'assets/fonts/geist_mono_regular.ttf',
        'assets/fonts/geist_mono_bold.ttf',
      ],
      <String>[
        'assets/fonts/cascadia_code_regular.ttf',
        'assets/fonts/cascadia_code_bold.ttf',
      ],
    ];
    for (final List<String> pair in pairs) {
      final File regular = File(pair[0]);
      final File bold = File(pair[1]);
      expect(regular.existsSync(), isTrue, reason: pair[0]);
      expect(bold.existsSync(), isTrue, reason: pair[1]);
      expect(regular.lengthSync(), greaterThan(0), reason: pair[0]);
      expect(regular.readAsBytesSync(), isNot(equals(bold.readAsBytesSync())),
          reason: '${pair[1]} is a byte copy of ${pair[0]}, so bold is not '
              'bold');
    }
  });
}
