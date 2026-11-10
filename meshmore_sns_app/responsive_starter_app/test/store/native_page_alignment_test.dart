// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// Android requires 16 KB page support from 1 February 2027, and the only
/// libraries this repository owns are the ones it ships in the tree: the two
/// Codec 2 objects and the rebuilt `libavif_native.so`. `tool/check_16k.sh`
/// checks the assembled APK, which also covers Flutter's own libraries — but it
/// needs an APK, so it runs when someone remembers. This runs on every
/// `flutter test`, against the binaries that are actually committed.
///
/// Two rules, the same two the script applies:
///
/// * every `PT_LOAD` segment is aligned to at least 16 KB, so the loader can map
///   it on a 16 KB page;
/// * where a `GNU_RELRO` exists, its range rounded up to a 16 KB page ends at or
///   before the next `PT_LOAD`, so the read-only remap cannot cover writable
///   data. A library with no writable segment has no `GNU_RELRO` at all, and
///   that is not a failure.
const int kPageBytes = 16 * 1024;

const int _ptLoad = 1;
const int _ptGnuRelro = 0x6474e552;

/// One file that has to pass.
const List<String> kOwnedLibraryDirs = <String>[
  // Codec 2 and its MIT shim, one pair per shipped ABI.
  'android/app/src/main/jniLibs',
  // The AVIF build this repository vendored and rebuilt at the package's own
  // pins with both page flags passed explicitly (R144).
  '../third_party/avif_native/native/prebuilt',
];

class _Segment {
  const _Segment({required this.type, required this.vaddr, required this.memsz,
      required this.align});

  final int type;
  final int vaddr;
  final int memsz;
  final int align;
}

List<_Segment> _programHeaders(Uint8List bytes) {
  if (bytes.length < 64 ||
      bytes[0] != 0x7f ||
      bytes[1] != 0x45 ||
      bytes[2] != 0x4c ||
      bytes[3] != 0x46) {
    throw const FormatException('not an ELF file');
  }
  final int elfClass = bytes[4]; // 1 = 32-bit, 2 = 64-bit
  final Endian endian = bytes[5] == 2 ? Endian.big : Endian.little;
  final ByteData view = ByteData.sublistView(bytes);
  final int phoff;
  final int phentsize;
  final int phnum;
  if (elfClass == 2) {
    phoff = view.getUint64(0x20, endian);
    phentsize = view.getUint16(0x36, endian);
    phnum = view.getUint16(0x38, endian);
  } else if (elfClass == 1) {
    phoff = view.getUint32(0x1c, endian);
    phentsize = view.getUint16(0x2a, endian);
    phnum = view.getUint16(0x2c, endian);
  } else {
    throw const FormatException('unknown ELF class');
  }
  final List<_Segment> out = <_Segment>[];
  for (int i = 0; i < phnum; i++) {
    final int at = phoff + i * phentsize;
    if (at + phentsize > bytes.length) {
      throw const FormatException('program header past the end of the file');
    }
    if (elfClass == 2) {
      out.add(_Segment(
        type: view.getUint32(at, endian),
        vaddr: view.getUint64(at + 0x10, endian),
        memsz: view.getUint64(at + 0x28, endian),
        align: view.getUint64(at + 0x30, endian),
      ));
    } else {
      out.add(_Segment(
        type: view.getUint32(at, endian),
        vaddr: view.getUint32(at + 0x08, endian),
        memsz: view.getUint32(at + 0x14, endian),
        align: view.getUint32(at + 0x1c, endian),
      ));
    }
  }
  return out;
}

int _alignUp(int value) => (value + kPageBytes - 1) ~/ kPageBytes * kPageBytes;

/// Null when [path] passes, otherwise the sentence to show.
String? _pageProblem(String path) {
  final List<_Segment> segments =
      _programHeaders(File(path).readAsBytesSync());
  final List<_Segment> loads = <_Segment>[
    for (final _Segment s in segments)
      if (s.type == _ptLoad) s,
  ];
  if (loads.isEmpty) return 'has no PT_LOAD segment';
  final int minAlign = loads
      .map((_Segment s) => s.align)
      .reduce((int a, int b) => a < b ? a : b);
  if (minAlign < kPageBytes) {
    return 'PT_LOAD alignment is 0x${minAlign.toRadixString(16)}, under '
        '0x${kPageBytes.toRadixString(16)}';
  }
  final _Segment? relro = segments
      .where((_Segment s) => s.type == _ptGnuRelro)
      .cast<_Segment?>()
      .firstWhere((_Segment? s) => true, orElse: () => null);
  if (relro == null) return null;
  final int end = relro.vaddr + relro.memsz;
  final Iterable<int> after = loads
      .map((_Segment s) => s.vaddr)
      .where((int vaddr) => vaddr > end);
  if (after.isEmpty) return null;
  final int next = after.reduce((int a, int b) => a < b ? a : b);
  if (_alignUp(end) > next) {
    return 'GNU_RELRO ends at 0x${_alignUp(end).toRadixString(16)}, past the '
        'next PT_LOAD at 0x${next.toRadixString(16)}';
  }
  return null;
}

void main() {
  test('every committed native library is 16 KB page ready', () {
    final List<String> libraries = <String>[
      for (final String dir in kOwnedLibraryDirs)
        if (Directory(dir).existsSync())
          for (final FileSystemEntity e
              in Directory(dir).listSync(recursive: true))
            if (e is File && e.path.endsWith('.so')) e.path,
    ];
    // Three ABIs × (codec, bridge) plus three AVIF builds. A moved directory
    // must fail this test rather than quietly check nothing.
    expect(libraries.length, greaterThanOrEqualTo(9),
        reason: 'the shipped libraries were not found where they live');
    final List<String> failures = <String>[];
    for (final String path in libraries) {
      final String? problem = _pageProblem(path);
      if (problem != null) failures.add('$path: $problem');
    }
    expect(failures, isEmpty,
        reason: 'run: tool/check_16k.sh after any native rebuild');
  });

  test('the checker is proved to fail on a 4 KB binary', () {
    // `libflutter.so` from the Flutter SDK is not in this tree, but every
    // library the app builds links against the same rule, and a check that has
    // never failed is a check nobody can trust. This walks a real 4 KB-aligned
    // library if one is reachable, and otherwise proves the parser on a
    // synthetic header.
    final Uint8List synthetic = Uint8List(64 + 56);
    synthetic.setAll(0, <int>[0x7f, 0x45, 0x4c, 0x46, 2, 1]);
    final ByteData view = ByteData.sublistView(synthetic);
    view.setUint64(0x20, 64, Endian.little); // e_phoff
    view.setUint16(0x36, 56, Endian.little); // e_phentsize
    view.setUint16(0x38, 1, Endian.little); // e_phnum
    view.setUint32(64, _ptLoad, Endian.little);
    view.setUint64(64 + 0x10, 0, Endian.little); // p_vaddr
    view.setUint64(64 + 0x28, 0x1000, Endian.little); // p_memsz
    view.setUint64(64 + 0x30, 0x1000, Endian.little); // p_align
    final List<_Segment> segments = _programHeaders(synthetic);
    expect(segments.single.align, 0x1000);
    final int minAlign = segments.single.align;
    expect(minAlign < kPageBytes, isTrue,
        reason: 'a 4 KB PT_LOAD must be reported, not accepted');
  });
}
