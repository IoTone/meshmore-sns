// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../meshcore/chat_message.dart';

/// A report is not a block and not moderation: it is a bundle the user sends
/// wherever they choose (`meshmore-sns-block-spec.md` §8).
///
/// There is no server in this product, so nothing here transmits. The bundle
/// carries the message id, the sender key, the channel, the timestamp and the
/// text — nothing the user did not already have — and states that no network
/// request was made, so a reader cannot mistake the file for a submission.
class ReportBundle {
  const ReportBundle._();

  /// Schema version of the bundle file.
  static const int formatVersion = 1;

  static Map<String, Object?> build({
    required ChatMessage message,
    required String channelName,
    required String reporterObservation,
    DateTime Function()? clock,
    String? senderDisplayName,
  }) =>
      <String, Object?>{
        'format': 'meshmore.report',
        'version': formatVersion,
        'createdAtMs': (clock ?? DateTime.now)().millisecondsSinceEpoch,
        'message': <String, Object?>{
          'id': message.id,
          'atMs': message.at.millisecondsSinceEpoch,
          'channel': channelName,
          'senderKeyHex': message.peerPubKeyHex,
          if (senderDisplayName != null) 'senderName': senderDisplayName,
          'outgoing': message.outgoing,
          'text': message.text,
        },
        'observation': reporterObservation,
        // Said in the file itself, because the file travels further than the
        // sheet that produced it.
        'transmission': 'none — this file was written on the device and sent '
            'nowhere by the app',
      };

  /// Writes the bundle to a temporary file and returns its path, so a share
  /// sheet can be handed a file rather than a string.
  static Future<File> write(
    Map<String, Object?> bundle, {
    Directory? directory,
    DateTime Function()? clock,
  }) async {
    final Directory dir = directory ?? await getTemporaryDirectory();
    final int stamp = (clock ?? DateTime.now)().millisecondsSinceEpoch;
    final File file = File('${dir.path}/meshmore-report-$stamp.json');
    await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(bundle));
    return file;
  }
}
