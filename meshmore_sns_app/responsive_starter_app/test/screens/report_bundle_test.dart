// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/meshcore/chat_message.dart';
import 'package:meshmore_sns_app/screens/report_bundle.dart';

/// The report is the moderation path and the block is not; the bundle has to
/// carry exactly what the spec lists and say out loud that nothing was sent.
void main() {
  test('a bundle carries the message, the channel and nothing else', () {
    final ChatMessage m = ChatMessage(
      channelIdx: 2,
      text: 'buy this',
      outgoing: false,
      peerPubKeyHex: 'c' * 64,
      at: DateTime.fromMillisecondsSinceEpoch(1700000000000),
    );
    final Map<String, Object?> b = ReportBundle.build(
      message: m,
      channelName: 'general',
      reporterObservation: 'spam',
      clock: () => DateTime.fromMillisecondsSinceEpoch(1700000001000),
    );

    expect(b['format'], 'meshmore.report');
    expect(b['version'], 1);
    expect(b['observation'], 'spam');
    final Map<String, Object?> msg = b['message']! as Map<String, Object?>;
    expect(msg['id'], m.id);
    expect(msg['text'], 'buy this');
    expect(msg['channel'], 'general');
    expect(msg['senderKeyHex'], 'c' * 64);
    expect(msg['atMs'], 1700000000000);
    expect(b['transmission'], contains('nowhere'));
  });

  test('writing it produces a real JSON file and no network call', () async {
    final Directory dir = Directory.systemTemp.createTempSync('report_bundle');
    addTearDown(() => dir.deleteSync(recursive: true));
    final ChatMessage m = ChatMessage(channelIdx: 0, text: 'hi', outgoing: false);
    final File f = await ReportBundle.write(
      ReportBundle.build(
          message: m, channelName: 'general', reporterObservation: 'test'),
      directory: dir,
      clock: () => DateTime.fromMillisecondsSinceEpoch(1700000000000),
    );
    expect(f.existsSync(), isTrue);
    final Map<String, Object?> parsed =
        jsonDecode(await f.readAsString()) as Map<String, Object?>;
    expect(parsed['format'], 'meshmore.report');
    expect(f.path, endsWith('meshmore-report-1700000000000.json'));
  });
}
