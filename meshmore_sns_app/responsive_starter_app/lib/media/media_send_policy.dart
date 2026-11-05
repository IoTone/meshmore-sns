// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:meshcore/meshcore.dart';

/// Why a media send was refused before it reached the radio.
enum MediaSendRefusal {
  /// The channel is the well-known Public channel and media on Public is off.
  /// This is the default, and it is enforced here rather than in the composer
  /// so no future surface can bypass it by forgetting a checkbox.
  mediaOffOnPublic,

  /// The payload is empty or larger than one transfer may carry.
  payloadUnusable,

  /// The channel is not known, so nothing can be said about who would see it.
  channelUnknown,
}

/// The send-path gate for media on a channel.
///
/// Register §6: media is **off by default on Public** and the enforcement
/// belongs at the send path. The channel is identified by its secret, not by
/// its name — a channel named "Public" with a different key is a private
/// channel, and the well-known secret under another name is still public.
final class MediaSendPolicy {
  const MediaSendPolicy({this.mediaOnPublic = false});

  /// The user's explicit opt-in. Default false: the decision is to be off.
  final bool mediaOnPublic;

  static bool isPublicChannel(List<int> psk) {
    if (psk.length != kPublicChannelPsk.length) return false;
    for (int i = 0; i < psk.length; i++) {
      if (psk[i] != kPublicChannelPsk[i]) return false;
    }
    return true;
  }

  /// Null when the send may proceed; the refusal otherwise, so the caller has
  /// one thing to switch on and the copy can say which rule refused it.
  MediaSendRefusal? refusalFor({
    required List<int>? channelPsk,
    required int payloadBytes,
  }) {
    if (payloadBytes <= 0) return MediaSendRefusal.payloadUnusable;
    if (channelPsk == null) return MediaSendRefusal.channelUnknown;
    if (isPublicChannel(channelPsk) && !mediaOnPublic) {
      return MediaSendRefusal.mediaOffOnPublic;
    }
    return null;
  }
}
