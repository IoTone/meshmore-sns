// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT

/// What kind of event a `MeshEvent` represents. The Dashboard's
/// RECENT feed translates `(kind, args)` into a localised string at
/// render time via `AppLocalizations`. Adding a new kind needs:
///   1. An entry here.
///   2. An arb key + JA translation.
///   3. A case in the Dashboard's `_eventText` switch.
enum MeshEventKind {
  advert,
  channelMsg,
  dm,
  contact,

  /// A run of contacts, collapsed into one line.
  ///
  /// The radio streams its whole table on connect, one frame per contact, so a
  /// 350-entry table wrote 350 rows into the feed in the same second and buried
  /// every message. The table loading is one event.
  contactBatch,
  battery,
  deviceError,
  deviceClockSynced,
  deviceClockSkew,
  msgSent,
  deviceInfo,
  selfInfo,
  queuedWaiting,
  oneKeyRejected,
  radioRefused,
}

/// A single line in the Dashboard's recent-activity feed, derived
/// from a decoded inbound frame.
///
/// We **don't** carry pre-formatted English text any more — the
/// controller emits a discriminated `kind` + a small map of named
/// placeholders, and the Dashboard formats the row via the locale-
/// specific arb key at display time.
class MeshEvent {
  MeshEvent({
    required this.kind,
    this.args = const <String, String>{},
    DateTime? at,
  }) : at = at ?? DateTime.now();

  final MeshEventKind kind;
  final Map<String, String> args;
  final DateTime at;
}
