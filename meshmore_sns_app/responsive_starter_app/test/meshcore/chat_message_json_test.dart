// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:meshmore_sns_app/meshcore/chat_message.dart';
import 'package:meshmore_sns_app/meshcore/failure.dart';

/// A persisted row has to survive its own round trip, including a failed send.
///
/// The field a failure cause was written into was the *channel index*: the map
/// literal wrote `'c'` twice and the later key won, so a row that failed
/// persisted no channel at all and a String where a number belongs. On the next
/// launch the decode threw, and the store's catch threw the whole history away.
/// One failed send plus one restart was enough to lose every message the app had.
void main() {
  ChatMessage failedRow() => ChatMessage(
        channelIdx: 3,
        text: 'the ford is out',
        outgoing: true,
        at: DateTime.fromMillisecondsSinceEpoch(1762000000000),
        delivery: MessageDelivery.failed,
        failReason: 'the radio refused',
        failCause: FailureCause.airtimeBudget,
      );

  test('a failed row keeps its channel and its cause', () {
    final ChatMessage m = failedRow();
    final Map<String, Object?> json = m.toJson();
    expect(json['c'], 3, reason: 'the channel index lives in c and only in c');
    expect(json['x'], 'airtimeBudget');

    final ChatMessage back =
        ChatMessage.fromJson(jsonDecode(jsonEncode(json)) as Map<String, Object?>);
    expect(back.channelIdx, 3);
    expect(back.failCause, FailureCause.airtimeBudget);
    expect(back.failReason, 'the radio refused');
    expect(back.delivery, MessageDelivery.failed);
  });

  test('a legacy row with the cause in c is still readable', () {
    // Exactly what the shipped build wrote: a String in `c` and no channel.
    final ChatMessage back = ChatMessage.fromJson(<String, Object?>{
      'i': 'legacy1',
      'c': 'airtimeBudget',
      't': 'hello',
      'o': true,
      'a': 1762000000000,
      'd': MessageDelivery.failed.index,
    });
    expect(back.channelIdx, 0,
        reason: 'the public channel is where that shape came from');
    expect(back.failCause, FailureCause.airtimeBudget);
    expect(back.text, 'hello');
  });

  test('a plain row is unchanged', () {
    final ChatMessage m = ChatMessage(
      channelIdx: 1,
      text: 'clear',
      outgoing: false,
      at: DateTime.fromMillisecondsSinceEpoch(1762000000000),
    );
    final ChatMessage back = ChatMessage.fromJson(m.toJson());
    expect(back.channelIdx, 1);
    expect(back.failCause, isNull);
    expect(back.text, 'clear');
  });
}
