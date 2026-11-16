// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:meshmore_sns_app/media/media_chunk.dart';
import 'package:meshmore_sns_app/media/media_inbox.dart';
import 'package:meshmore_sns_app/voice/voice_codec.dart';
import 'package:meshmore_sns_app/voice/voice_inbox.dart';
import 'package:meshmore_sns_app/voice/voice_payload.dart';

import '../support/fake_voice_codec.dart';

/// The notes this session holds.
///
/// A voice note has no surface claiming it the way a place sheet claims its
/// picture: it arrives on a channel the reader may not be looking at. So the
/// inbox is a bounded list, and these cases pin the three things that make it
/// safe to read — a note that cannot be decoded is refused at arrival rather
/// than at press, the list cannot grow without a bound, and a photo is not a row
/// here.

PackedVoice _packed(VoiceMode mode, int frames) => FakeVoiceCodec(
      modes: <VoiceMode>{mode},
    ).encode(pcmOf(frames, (int f) => 400 + f), mode: mode);

MediaInboxPayload _payload({
  required int payloadId,
  required Uint8List bytes,
  MediaKind kind = MediaKind.voice,
  int channelIndex = 0,
  DateTime? at,
}) =>
    MediaInboxPayload(
      payloadId: payloadId,
      kind: kind,
      channelIndex: channelIndex,
      receivedAt: at ?? DateTime(2026, 11, 10, 9),
      bytes: bytes,
    );

void main() {
  group('a whole note becomes a row', () {
    test('its duration comes from the header, with nothing decoded', () async {
      final StreamController<MediaInboxPayload> completed =
          StreamController<MediaInboxPayload>.broadcast();
      final VoiceInbox inbox = VoiceInbox(completed: completed.stream)..start();
      final PackedVoice packed = _packed(VoiceMode.narrowband, 50); // 2 s
      completed.add(_payload(
        payloadId: 7,
        bytes: VoicePayloadCodec.encode(packed),
      ));
      await Future<void>.delayed(Duration.zero);
      expect(inbox.notes.length, 1);
      final ReceivedVoice note = inbox.notes.single;
      expect(note.payloadId, 7);
      expect(note.mode, VoiceMode.narrowband);
      expect(note.duration, const Duration(seconds: 2));
      expect(note.samples, 16000);
      expect(note.bytes, 1 + packed.bytes.length);
      inbox.dispose();
      await completed.close();
    });

    test('newest first, and a repeat of one id is not a second row', () async {
      final StreamController<MediaInboxPayload> completed =
          StreamController<MediaInboxPayload>.broadcast();
      final VoiceInbox inbox = VoiceInbox(completed: completed.stream)..start();
      final Uint8List bytes =
          VoicePayloadCodec.encode(_packed(VoiceMode.narrowband, 25));
      completed.add(_payload(payloadId: 1, bytes: bytes));
      completed.add(_payload(payloadId: 2, bytes: bytes));
      // A replayed completion: the reassembler remembers completed ids, so this
      // is defensive, and a duplicated row would be the visible symptom.
      completed.add(_payload(payloadId: 1, bytes: bytes));
      await Future<void>.delayed(Duration.zero);
      expect(inbox.notes.map((ReceivedVoice n) => n.payloadId), <int>[2, 1]);
      inbox.dispose();
      await completed.close();
    });

    test('a channel asks for its own notes and its own count', () async {
      final StreamController<MediaInboxPayload> completed =
          StreamController<MediaInboxPayload>.broadcast();
      final VoiceInbox inbox = VoiceInbox(completed: completed.stream)..start();
      final Uint8List bytes =
          VoicePayloadCodec.encode(_packed(VoiceMode.standard, 25));
      completed.add(_payload(payloadId: 1, bytes: bytes, channelIndex: 0));
      completed.add(_payload(payloadId: 2, bytes: bytes, channelIndex: 3));
      completed.add(_payload(payloadId: 3, bytes: bytes, channelIndex: 0));
      await Future<void>.delayed(Duration.zero);
      expect(inbox.countFor(0), 2);
      expect(inbox.countFor(3), 1);
      expect(inbox.countFor(9), 0);
      expect(inbox.notesFor(3).single.payloadId, 2);
      inbox.dispose();
      await completed.close();
    });
  });

  group('what is not a note is not a row', () {
    test('a photo payload is somebody else\'s row, silently', () async {
      final StreamController<MediaInboxPayload> completed =
          StreamController<MediaInboxPayload>.broadcast();
      final VoiceInbox inbox = VoiceInbox(completed: completed.stream)..start();
      completed.add(_payload(
        payloadId: 1,
        bytes: Uint8List.fromList(<int>[1, 2, 3]),
        kind: MediaKind.image,
      ));
      await Future<void>.delayed(Duration.zero);
      expect(inbox.notes, isEmpty);
      expect(inbox.refused, 0, reason: 'a photo is not a refusal');
      inbox.dispose();
      await completed.close();
    });

    test('a voice payload this build cannot read is counted, not shown',
        () async {
      final StreamController<MediaInboxPayload> completed =
          StreamController<MediaInboxPayload>.broadcast();
      final VoiceInbox inbox = VoiceInbox(completed: completed.stream)..start();
      // A layout from a newer build, and a mode this one does not carry.
      completed.add(_payload(payloadId: 1, bytes: Uint8List.fromList(<int>[0x20, 1])));
      completed.add(_payload(payloadId: 2, bytes: Uint8List.fromList(<int>[0x14, 1])));
      await Future<void>.delayed(Duration.zero);
      expect(inbox.notes, isEmpty);
      expect(inbox.refused, 2);
      inbox.dispose();
      await completed.close();
    });
  });

  group('the list is bounded and clearable', () {
    test('the oldest note is dropped past the capacity', () async {
      final StreamController<MediaInboxPayload> completed =
          StreamController<MediaInboxPayload>.broadcast();
      final VoiceInbox inbox =
          VoiceInbox(completed: completed.stream, capacity: 3)..start();
      final Uint8List bytes =
          VoicePayloadCodec.encode(_packed(VoiceMode.narrowband, 25));
      for (int id = 1; id <= 5; id++) {
        completed.add(_payload(payloadId: id, bytes: bytes));
      }
      await Future<void>.delayed(Duration.zero);
      expect(inbox.notes.map((ReceivedVoice n) => n.payloadId), <int>[5, 4, 3]);
      inbox.dispose();
      await completed.close();
    });

    test('clear empties it, and a note after a clear is still taken', () async {
      final StreamController<MediaInboxPayload> completed =
          StreamController<MediaInboxPayload>.broadcast();
      final VoiceInbox inbox = VoiceInbox(completed: completed.stream)..start();
      final Uint8List bytes =
          VoicePayloadCodec.encode(_packed(VoiceMode.narrowband, 25));
      completed.add(_payload(payloadId: 1, bytes: bytes));
      await Future<void>.delayed(Duration.zero);
      int notifications = 0;
      inbox.addListener(() => notifications++);
      inbox.clear();
      expect(inbox.notes, isEmpty);
      expect(notifications, 1);
      completed.add(_payload(payloadId: 2, bytes: bytes));
      await Future<void>.delayed(Duration.zero);
      expect(inbox.notes.single.payloadId, 2);
      inbox.dispose();
      await completed.close();
    });

    test('a completion after dispose does not notify a dead notifier', () async {
      final StreamController<MediaInboxPayload> completed =
          StreamController<MediaInboxPayload>.broadcast();
      final VoiceInbox inbox = VoiceInbox(completed: completed.stream)..start();
      inbox.dispose();
      final Uint8List bytes =
          VoicePayloadCodec.encode(_packed(VoiceMode.narrowband, 25));
      // The subscription is cancelled on dispose, so nothing arrives; the point
      // is that the notifier cannot be touched afterwards.
      completed.add(_payload(payloadId: 1, bytes: bytes));
      await Future<void>.delayed(Duration.zero);
      expect(inbox.notes, isEmpty);
      await completed.close();
    });
  });
}
