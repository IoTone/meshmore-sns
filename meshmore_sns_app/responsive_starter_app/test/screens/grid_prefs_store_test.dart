// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/screens/grid_prefs_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('null when nothing saved', () async {
    expect(await GridPrefsStore.load(), isNull);
  });

  test('an older save that carries an orientation still loads', () async {
    // The radar has no orientation any more; a save written before that must
    // not throw and must keep the fields that still mean something.
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('mm.gridPrefs.v1',
        '{"scale":2,"north":false,"live":true,"iv":10}');
    final GridPrefs p = (await GridPrefsStore.load())!;
    expect(p.scaleIndex, 2);
    expect(p.intervalSec, 10);
  });

  test('round-trips the grid preferences', () async {
    await GridPrefsStore.save(const GridPrefs(
      scaleIndex: 3,
      intervalSec: 30,
    ));
    final GridPrefs p = (await GridPrefsStore.load())!;
    expect(p.scaleIndex, 3);
    expect(p.intervalSec, 30);
  });
}
