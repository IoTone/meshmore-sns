// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/chat/reactions.dart';
import 'package:meshmore_sns_app/meshcore/chat_message.dart';

/// A reaction is folded into the message it names, and the hash is what does
/// the folding. This pins the two halves together: the line our composer would
/// send, matched against the hash the row computes.
void main() {
  test('a channel reaction line names the message it was built for', () {
    final ChatMessage target = ChatMessage(
      channelIdx: 2,
      text: 'Sam: good morning',
      outgoing: false,
      at: DateTime.fromMillisecondsSinceEpoch(1700000000000),
    );
    // What the sender would compute: the displayed name salts the hash.
    final String hash = Reactions.hashFor(
      timestampSeconds: target.at.millisecondsSinceEpoch ~/ 1000,
      text: target.text,
    );
    final String line =
        Reactions.encodeChannel(senderName: 'Kim', emoji: '👍', hash: hash);
    final ({String hash, String emoji, String? senderName, bool isOpen})? rx =
        Reactions.parse(line);
    expect(rx, isNotNull);
    expect(rx!.hash, hash, reason: 'the reaction points at the target');
    expect(rx.emoji, '👍');
    expect(rx.senderName, 'Kim');
  });

  test('text and time change the hash, and the sender does not', () {
    const int ts = 1700000000;
    final String a =
        Reactions.hashFor(timestampSeconds: ts, text: 'Sam: good morning');
    final String b =
        Reactions.hashFor(timestampSeconds: ts, text: 'Sam: good evening');
    final String c =
        Reactions.hashFor(timestampSeconds: ts + 1, text: 'Sam: good morning');
    expect(<String>{a, b, c}.length, 3, reason: 'text and time both count');

    // The sender is carried beside the hash, not inside it, so the same text at
    // the same second is one hash for everyone. Two reactions on it are told
    // apart by the name in the line.
    final String lineA = Reactions.encodeChannel(
        senderName: 'Sam', emoji: '👍', hash: a);
    final String lineB = Reactions.encodeChannel(
        senderName: 'Kim', emoji: '👍', hash: a);
    expect(Reactions.parse(lineA)!.hash, Reactions.parse(lineB)!.hash);
    expect(Reactions.parse(lineA)!.senderName, 'Sam');
    expect(Reactions.parse(lineB)!.senderName, 'Kim');
  });

  test('reactions survive a JSON round trip with the message', () {
    final ChatMessage m = ChatMessage(
      channelIdx: 0,
      text: 'hello',
      outgoing: false,
      reactions: <String, List<String?>>{
        '👍': <String?>['Sam', 'Kim'],
        '•': <String?>[null],
      },
    );
    final ChatMessage back = ChatMessage.fromJson(m.toJson());
    expect(back.reactions.keys.toSet(), <String>{'👍', '•'});
    expect(back.reactions['👍'], <String?>['Sam', 'Kim']);
    expect(back.reactions['•'], <String?>[null],
        reason: 'a reaction with no identity keeps its null sender');
  });
}
