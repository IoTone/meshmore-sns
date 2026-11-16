// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT

/// One DM conversation, as the chat strip lists it.
///
/// A DM row carries the peer's key and nothing else that names it, so the
/// strip needs this small summary to draw a chip: who, when it last spoke, and
/// how much of it is unread.
class DmThread {
  const DmThread({
    required this.peerPubKeyHex,
    required this.name,
    required this.lastAt,
    required this.unread,
  });

  /// The peer's public key, lower-case hex. This is the thread's identity and
  /// the `/dm/:pubkey` route's argument.
  final String peerPubKeyHex;

  /// The node's own name when it has been heard, else the key prefix.
  final String name;

  /// The newest message in the thread, either direction.
  final DateTime lastAt;

  /// Inbound messages newer than the thread's read mark.
  final int unread;
}
