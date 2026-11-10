// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../media/media_chunk.dart';
import '../media/media_inbox.dart';
import 'voice_capture.dart';
import '../util/safe_notifier.dart';
import 'voice_codec.dart';
import 'voice_payload.dart';

/// One voice note that arrived whole.
///
/// The payload is kept as the bytes that travelled, not as PCM: decoding costs
/// a codec call and 320 KB of memory for a 20-second note, and a receiver who
/// plays one note in ten would pay that for all ten. [duration] comes from the
/// header and the length, so a row can state how long a note is before anything
/// decodes it.
final class ReceivedVoice {
  const ReceivedVoice({
    required this.payloadId,
    required this.channelIndex,
    required this.receivedAt,
    required this.payload,
    required this.mode,
    required this.frames,
    required this.samples,
  });

  final int payloadId;
  final int channelIndex;
  final DateTime receivedAt;

  /// The wire payload: [VoicePayloadCodec]'s header and the packed frames.
  final Uint8List payload;
  final VoiceMode mode;
  final int frames;
  final int samples;

  Duration get duration =>
      Duration(microseconds: samples * 1000000 ~/ kVoiceSampleRate);

  /// What the note cost on air, payload bytes.
  int get bytes => payload.length;

  @override
  String toString() =>
      'ReceivedVoice($payloadId, ${mode.label}, $duration, $bytes B)';
}

/// The notes this session has taken off the channel.
///
/// A photo is claimed by the surface that is waiting for it, but a voice note
/// has no such surface: it arrives on a channel the reader may not be looking
/// at, and the person who sent it is not asking anything. So the inbox is a
/// bounded list rather than a set of claims — the newest [capacity] notes, the
/// oldest dropped — and a note is refused at arrival if its header cannot be
/// read, so no row ever fails when it is pressed.
///
/// Nothing here is persisted. A note is as durable as the process, which the
/// surface says: the alternative is 320 KB per note in the sealed store for a
/// message that is already spent.
final class VoiceInbox extends ChangeNotifier with SafeNotifier {
  VoiceInbox({
    required Stream<MediaInboxPayload> completed,
    this.capacity = 12,
  }) : _completed = completed;

  /// How many notes the session keeps. Twelve is a channel's worth of a walk
  /// and bounds the memory at about 200 KB of payload across modes.
  final int capacity;

  final Stream<MediaInboxPayload> _completed;
  final List<ReceivedVoice> _notes = <ReceivedVoice>[];
  StreamSubscription<MediaInboxPayload>? _subscription;
  int _refused = 0;

  /// Notes whose header this build cannot read. A count, not a row: a payload
  /// from another mode is not a note with a problem, it is a note for a build
  /// with that mode.
  int get refused => _refused;

  /// Newest first.
  List<ReceivedVoice> get notes => List<ReceivedVoice>.unmodifiable(_notes);

  List<ReceivedVoice> notesFor(int channelIndex) => <ReceivedVoice>[
        for (final ReceivedVoice n in _notes)
          if (n.channelIndex == channelIndex) n,
      ];

  int countFor(int channelIndex) {
    int n = 0;
    for (final ReceivedVoice note in _notes) {
      if (note.channelIndex == channelIndex) n++;
    }
    return n;
  }

  ReceivedVoice? note(int payloadId) {
    for (final ReceivedVoice n in _notes) {
      if (n.payloadId == payloadId) return n;
    }
    return null;
  }

  /// Starts reading completed payloads. Idempotent, so a rebuild cannot listen
  /// twice and file every note twice with it.
  void start() {
    _subscription ??= _completed.listen(_onPayload);
  }

  void _onPayload(MediaInboxPayload payload) {
    // One inbox serves every media kind; a photo is somebody else's row.
    if (payload.kind != MediaKind.voice) return;
    if (note(payload.payloadId) != null) return;
    final PackedVoice info;
    try {
      info = VoicePayloadCodec.inspect(payload.bytes);
    } on VoiceException {
      _refused++;
      notifyListeners();
      return;
    }
    _notes.insert(
      0,
      ReceivedVoice(
        payloadId: payload.payloadId,
        channelIndex: payload.channelIndex,
        receivedAt: payload.receivedAt,
        payload: payload.bytes,
        mode: info.mode,
        frames: info.frames,
        samples: info.samples,
      ),
    );
    while (_notes.length > capacity) {
      _notes.removeLast();
    }
    notifyListeners();
  }

  /// Drops every note. The storage block's "delete everything" calls this, so
  /// a clear that says it removed the media inbox removes what is on screen
  /// as well as what is on disk.
  void clear() {
    if (_notes.isEmpty) return;
    _notes.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    final StreamSubscription<MediaInboxPayload>? sub = _subscription;
    _subscription = null;
    if (sub != null) unawaited(sub.cancel());
    super.dispose();
  }
}
