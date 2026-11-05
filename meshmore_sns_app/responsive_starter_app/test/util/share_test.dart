// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meshmore_sns_app/util/share.dart';

/// An export that only writes a path into a snackbar is not an export: the
/// documents directory is app-private. This is the one seam every export goes
/// through, so the platform answer and the no-platform answer are both pinned.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<MethodCall> calls = <MethodCall>[];
  Object? answer;

  void install(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(Share.channel, handler);
  }

  setUp(calls.clear);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(Share.channel, null);
    answer = null;
  });

  test('a file is handed over with its mime type and subject', () async {
    install((MethodCall call) async {
      calls.add(call);
      return answer ?? true;
    });
    final bool opened = await Share.file('/data/app_flutter/ledger.csv',
        mime: 'text/csv', subject: 'Places ledger');
    expect(opened, isTrue);
    expect(calls.single.method, 'shareFile');
    expect(calls.single.arguments, <String, Object?>{
      'path': '/data/app_flutter/ledger.csv',
      'mime': 'text/csv',
      'subject': 'Places ledger',
    });
  });

  test('a host without the channel reports that nothing was shared', () async {
    // No handler installed: the call raises MissingPluginException, which is
    // what a desktop or a test host does.
    expect(await Share.file('/tmp/x.csv', mime: 'text/csv'), isFalse);
  });

  test('a platform refusal is false, not an exception in the caller', () async {
    install((MethodCall call) async =>
        throw PlatformException(code: 'share', message: 'no activity'));
    expect(await Share.file('/tmp/x.csv', mime: 'text/csv'), isFalse);
  });
}
