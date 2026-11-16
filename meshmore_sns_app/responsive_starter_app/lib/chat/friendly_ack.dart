// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:meshcore/meshcore.dart' show ChannelTextLimits;

import 'chat_actions.dart' show mentionPrefixFor;

/// A friendly acknowledgement: one channel line saying how a message arrived.
///
/// This is not the protocol's ACK. MeshCore's ACK is a four-byte checksum on the
/// wire (`[0x03]`, a uint32 of `timestamp + text + sender pubkey`) and there is
/// no chat message form of it; a direct message's delivery is proved by that
/// checksum and a channel message has no acknowledgement at all. What people do
/// in a channel is send a plain text line back with their own receiver's
/// measurements, and the shape that the clients reading it agree on is
///
///     ack: SNR 12.2 dB, RSSI -41 dBm, 9 hops via F8F9, D4D4
///
/// which is what the Colorado Mesh client parses as a signal report and renders
/// as a chip. Three things about it are worth stating in the code:
///
/// - The **measurements are the receiver's**, of the packet that carried the
///   message being answered: SNR and RSSI at this radio, and the path the packet
///   took. They describe the last hop into this radio, not the whole route's
///   quality.
/// - Everything in it is **unverified**: a channel line's sender name is a
///   plain-text prefix in the payload, so anyone holding the channel key can
///   write any name. The line is a courtesy, which is why it is called a
///   friendly ack rather than an ack.
/// - The body is **English on the wire**, like the reaction grammar. It is a
///   format other clients parse, so localising it would make this app the one
///   client whose reports nobody can read. Only the menu label is translated.
///
/// The route is dropped as a whole when it does not fit, then RSSI, then SNR:
/// a report that names the signal but not the route is still useful, and a
/// report the radio silently truncated is worse than a shorter one.
String friendlyAckLine({
  required String? sender,
  required double? snrDb,
  required int? rssiDbm,
  required int? hopCount,
  required List<String> pathHashes,
  required bool isFlood,
  required int maxBytes,
}) {
  final String prefix = mentionPrefixFor(sender) ?? '';

  String body({
    required bool snr,
    required bool rssi,
    required bool route,
  }) {
    final List<String> parts = <String>[];
    if (snr && snrDb != null) parts.add('SNR ${snrDb.toStringAsFixed(1)} dB');
    if (rssi && rssiDbm != null) parts.add('RSSI $rssiDbm dBm');
    // `3 hops via 4490, DF7C` is one phrase, not two: the route hangs off the
    // count in the format the other clients parse, so it takes no comma between
    // them.
    final String? routeClause =
        route && pathHashes.isNotEmpty ? 'via ${pathHashes.join(', ')}' : null;
    final int? hops = hopCount;
    if (hops != null && hops > 0) {
      final String count = '$hops ${hops == 1 ? 'hop' : 'hops'}';
      parts.add(routeClause == null ? count : '$count $routeClause');
    } else if (isFlood) {
      parts.add(routeClause == null ? 'flood' : 'flood $routeClause');
    } else if (routeClause != null) {
      parts.add(routeClause);
    }
    return parts.isEmpty ? 'ack: received' : 'ack: ${parts.join(', ')}';
  }

  // Full report first, then the same report with the least essential part
  // dropped, one at a time.
  final List<String> candidates = <String>[
    prefix + body(snr: true, rssi: true, route: true),
    prefix + body(snr: true, rssi: true, route: false),
    prefix + body(snr: true, rssi: false, route: false),
    prefix + body(snr: false, rssi: false, route: false),
    '${prefix}ack: received',
  ];
  for (final String line in candidates) {
    if (ChannelTextLimits.bytesOf(line) <= maxBytes) return line;
  }
  // Even the receipt does not fit, which means the addressable name alone is
  // most of the budget. The shortest honest form wins over a line the radio
  // would cut mid-word.
  return 'ack';
}

/// Whether a row can be answered with a friendly ack.
///
/// Only what this radio actually measured: a row with no SNR and no hop count
/// has nothing to report, and "ack: received" for a message whose reception was
/// never captured would be an assertion about the air that the app cannot make.
bool canFriendlyAck({
  required bool outgoing,
  required double? snrDb,
  required int? hopCount,
  required List<String> pathHashes,
}) =>
    !outgoing &&
    (snrDb != null || (hopCount != null && hopCount > 0) || pathHashes.isNotEmpty);
