// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import '../meshcore/block_filter.dart';
import '../meshcore/chat_message.dart';
import 'channel_read_store.dart';

/// Channel unread counts in one place, so the chip strip and the shell's view
/// strip cannot disagree about a badge.
///
/// The count is per channel and skips what the block filter hides: a blocked
/// key must not be able to make a badge appear. A null read store means there
/// is no unread state at all (a harness, or a device whose settings file is
/// unreadable) rather than a badge that is always on.
abstract final class UnreadCounts {
  static Map<int, int> perChannel({
    required Iterable<int> channels,
    required List<ChatMessage> Function(int channelIdx) history,
    required ChannelReadStore? reads,
    required BlockFilter filter,
  }) {
    final Map<int, int> out = <int, int>{};
    if (reads == null) return out;
    for (final int idx in channels) {
      final int n = ChannelUnread.count(
        history(idx),
        channelIdx: idx,
        lastReadMs: reads.lastReadAtMs(idx),
        filter: filter,
      );
      if (n > 0) out[idx] = n;
    }
    return out;
  }

  /// Unread across every channel: what the shell's chat cell shows.
  static int total({
    required Iterable<int> channels,
    required List<ChatMessage> Function(int channelIdx) history,
    required ChannelReadStore? reads,
    required BlockFilter filter,
  }) {
    int n = 0;
    for (final int c in perChannel(
      channels: channels,
      history: history,
      reads: reads,
      filter: filter,
    ).values) {
      n += c;
    }
    return n;
  }
}
