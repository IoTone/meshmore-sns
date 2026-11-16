// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';

import 'package:meshmore_sns_app/app/issue_report.dart';

/// R10 — the pre-filled issue is what stands in for a crash reporter, so what
/// it carries and what it refuses to carry are both requirements.
void main() {
  const IssueReport bare = IssueReport(
    appVersion: '1.0.197+13',
    platform: 'android 15',
  );

  test('the title names the version and the radio, or says there is none', () {
    expect(bare.toUri().queryParameters['title'],
        'MeshMore 1.0.197+13 — no radio');

    const IssueReport withRadio = IssueReport(
      appVersion: '1.0.197+13',
      platform: 'android 15',
      radioName: 'Ridge',
    );
    expect(withRadio.toUri().queryParameters['title'],
        'MeshMore 1.0.197+13 — radio: Ridge');
  });

  test('the body carries the facts a maintainer cannot ask for', () {
    const IssueReport full = IssueReport(
      appVersion: '1.0.197+13',
      platform: 'android 15',
      radioName: 'Ridge',
      radioModel: 'Heltec',
      radioFirmware: 'v1.15.0',
      mtu: 185,
    );
    final String body = full.toBody();

    expect(body, contains('- App: 1.0.197+13'));
    expect(body, contains('- Platform: android 15'));
    expect(body, contains('- Radio: Ridge'));
    expect(body, contains('- Radio model: Heltec'));
    expect(body, contains('- Radio firmware: v1.15.0'));
    expect(body, contains('- Link MTU: 185'),
        reason: 'a short MTU explains frame losses that no screenshot shows');
    expect(body, contains('What happened'),
        reason: 'the user is asked for the one thing only they know');
    expect(body, isNot(contains('**Diagnostics**')),
        reason: 'no capture pasted means no empty diagnostics section');
  });

  test('a pasted diagnostics capture is redacted before it reaches the URL',
      () {
    const IssueReport withCapture = IssueReport(
      appVersion: '1.0.197+13',
      platform: 'android 15',
      diagnostics:
          '{"psk_hex":"00112233445566778899aabbccddeeff","lat":38.9234,'
          '"frame":"8f01aa"}',
    );
    final String body = withCapture.toBody();

    expect(body, isNot(contains('00112233445566778899aabbccddeeff')),
        reason: 'a channel PSK in a public issue reads the whole channel');
    expect(body, isNot(contains('38.9234')),
        reason: 'a pasted capture must not carry the user\'s position');
    expect(body, contains('8f01aa'),
        reason: 'the encrypted frame is the evidence and is kept');
    expect(body, contains('nothing was sent automatically'));
  });

  test('nothing leaves the phone: the report is a local URL, not a request',
      () {
    final Uri uri = bare.toUri();
    expect(uri.host, 'github.com');
    expect(uri.path, '/IoTone/meshmore-sns/issues/new');
    expect(uri.queryParameters.keys,
        containsAll(<String>['title', 'body']),
        reason: 'the issue is opened in the tracker, where the user presses '
            'send; the app itself has no reporter');
  });
}
