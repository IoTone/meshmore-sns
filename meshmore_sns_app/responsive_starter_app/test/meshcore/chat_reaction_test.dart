// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/chat/reactions.dart';
import 'package:meshmore_sns_app/meshcore/chat_message.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_transport.dart';

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
    // The line names the message's author, which is what the other clients
    // write and what the reader needs to pick the right message.
    final String line =
        Reactions.encodeChannel(senderName: 'Sam', emoji: '👍', hash: hash);
    final ({String hash, String emoji, String? author, bool isOpen})? rx =
        Reactions.parse(line);
    expect(rx, isNotNull);
    expect(rx!.hash, hash, reason: 'the reaction points at the target');
    expect(rx.emoji, '👍');
    expect(rx.author, 'Sam',
        reason: "the line names the target's author, not the reactor");
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
    expect(Reactions.parse(lineA)!.author, 'Sam');
    expect(Reactions.parse(lineB)!.author, 'Kim');
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

  test('reacting folds the emoji in and adds no line to the thread', () async {
    // A reaction goes out as a text line, so sending one wrote an ordinary row
    // holding `@[name]🙂\n<hash>`: the reactor's own thread showed the wire
    // format as chat. The row still exists for the ledger, but it is not a line
    // a reader sees.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    addTearDown(mc.dispose);
    await mc.connect();
    fake.emit(selfInfoFrame());
    fake.emit(channelMsgFrame(text: 'Sam: good morning'));
    await Future<void>.delayed(Duration.zero);

    final List<ChatMessage> before = mc.messagesFor(0);
    expect(before, hasLength(1));
    final ChatMessage target = before.single;

    expect(await mc.reactTo(target, '👍'), isTrue);
    await Future<void>.delayed(Duration.zero);

    final List<ChatMessage> after = mc.messagesFor(0);
    expect(after, hasLength(1),
        reason: 'the reaction is not a second line in the thread');
    expect(after.single.reactions['👍'], isNotNull,
        reason: 'it is folded into the message it names');
    // The row is still in the store, so the radio's acknowledgement has
    // something to be credited to.
    expect(mc.allMessages.where((ChatMessage m) => m.hidden), hasLength(1));
    final String wire = mc.allMessages.firstWhere((ChatMessage m) => m.hidden).text;
    expect(Reactions.parse(wire)?.emoji, '👍',
        reason: 'the hidden row is the wire line, in the format other clients read');
  });

  test('a reaction row written before this build is hidden on the way in', () {
    // The row in the thread read `@[Half Live]✅\nch3z0stx`: a reaction sent by a
    // build that stored it as ordinary chat. Reading it back normalises it, so
    // the history stops showing the wire format.
    final ChatMessage old = ChatMessage.fromJson(<String, Object?>{
      'i': 'x1',
      'c': 0,
      't': '@[Half Live]✅\nch3z0stx',
      'o': true,
      'a': 1700000000000,
    });
    expect(old.hidden, isTrue);
    // An ordinary message is untouched, including one that mentions a hash.
    final ChatMessage plain = ChatMessage.fromJson(<String, Object?>{
      'i': 'x2',
      'c': 0,
      't': 'look at ch3z0stx',
      'o': false,
      'a': 1700000000000,
    });
    expect(plain.hidden, isFalse);
  });

  test('the same emoji on the same message sends once', () async {
    // A reaction is a gesture, not a message: tapping the same emoji twice is
    // the same act. It went out twice regardless, so every other client counted
    // the reactor once per tap, and a chip showed a count nobody had voted for.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    addTearDown(mc.dispose);
    await mc.connect();
    fake.emit(selfInfoFrame());
    fake.emit(channelMsgFrame(text: 'Sam: good morning'));
    await Future<void>.delayed(Duration.zero);
    final ChatMessage target = mc.messagesFor(0).single;

    int reactionLines() => mc.allMessages
        .where((ChatMessage m) =>
            m.hidden && Reactions.parse(m.text.trim()) != null)
        .length;

    expect(await mc.reactTo(target, '👍'), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(reactionLines(), 1);
    expect(target.ownReactions, <String>{'👍'});

    // The same emoji again: nothing goes out.
    expect(await mc.reactTo(target, '👍'), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(reactionLines(), 1,
        reason: 'the second tap on the same emoji is the same reaction');
    expect(target.reactions['👍'], hasLength(1),
        reason: 'and it did not count the reactor twice');

    // A different emoji is a different act, and does send.
    expect(await mc.reactTo(target, '🔥'), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(reactionLines(), 2);
    expect(target.ownReactions, <String>{'👍', '🔥'});
  });

  test('what this app reacted with is remembered across a restart', () async {
    // Idempotency that lives only in memory would let a restart send the same
    // reaction again, which is exactly the duplicate this replaces.
    final ChatMessage m = ChatMessage(
      channelIdx: 0,
      text: 'hello',
      outgoing: false,
      ownReactions: <String>{'✅'},
    );
    final ChatMessage back = ChatMessage.fromJson(m.toJson());
    expect(back.ownReactions, <String>{'✅'});
    // A row written by a build without the field reads as no reactions, not as
    // every reaction.
    expect(
        ChatMessage.fromJson(<String, Object?>{'i': 'x', 'c': 0, 't': 'hi'})
            .ownReactions,
        isEmpty);
  });
}
