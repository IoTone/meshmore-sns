// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/util/prefs.dart';

/// B9 — a preference whose type changed across releases must not throw inside
/// a load path, where nothing catches it and the screen never paints.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    Prefs.reset();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('an int is readable as a double and as an int', () async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    await p.setInt('n', 7);
    expect(Prefs.readInt(p, 'n'), 7);
    expect(Prefs.readDouble(p, 'n'), 7.0);
  });

  test('a double is readable as an int', () async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    await p.setDouble('n', 7.8);
    expect(Prefs.readInt(p, 'n'), 8);
    expect(Prefs.readDouble(p, 'n'), 7.8);
  });

  test('a numeric string is parsed, a word is not', () async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    await p.setString('a', '1.5');
    await p.setString('b', 'later');
    expect(Prefs.readDouble(p, 'a'), 1.5);
    expect(Prefs.readDouble(p, 'b'), 0.0);
    expect(Prefs.dropped.value, 1,
        reason: 'a value that could not be coerced is counted, not thrown');
  });

  test('a bool written as text still reads as a bool', () async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    await p.setString('on', 'true');
    await p.setInt('no', 0);
    expect(Prefs.readBool(p, 'on'), isTrue);
    expect(Prefs.readBool(p, 'no', fallback: true), isTrue);
  });

  test('a string key holding a number is null, and counted', () async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    await p.setInt('s', 3);
    expect(Prefs.readString(p, 's'), isNull);
    expect(Prefs.dropped.value, 1);
  });

  test('a write that does not land is sticky for the session', () async {
    expect(Prefs.writeFailed.value, isFalse);
    expect(await Prefs.probeWrite(Future<bool>.value(false)), isFalse);
    expect(Prefs.writeFailed.value, isTrue,
        reason: 'the dashboard reads this as the storage-full state');
    // A later success does not clear it: the device is out of room, and a
    // banner that flickers would be worse than one that stays.
    expect(await Prefs.probeWrite(Future<bool>.value(true)), isTrue);
    expect(Prefs.writeFailed.value, isTrue);
    Prefs.reset();
    expect(Prefs.writeFailed.value, isFalse);
  });

  test('a write that throws counts as a failed write, not a crash', () async {
    expect(
        await Prefs.probeWrite(
            Future<bool>.error(const FileSystemException('no space'))),
        isFalse);
    expect(Prefs.writeFailed.value, isTrue);
  });

  test('an absent key is the fallback, not a drop', () async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    expect(Prefs.readInt(p, 'missing', fallback: 4), 4);
    expect(Prefs.readBool(p, 'missing', fallback: true), isTrue);
    expect(Prefs.readString(p, 'missing'), isNull);
    expect(Prefs.dropped.value, 0);
  });
}
