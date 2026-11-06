// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../gen/app_localizations.dart';
import '../meshcore/chat_message.dart';
import '../meshcore/history_export.dart';
import '../meshcore/meshcore_controller.dart';
import '../meshcore/secure/store_export.dart';
import '../util/mesh_log.dart';
import '../util/share.dart';
import 'export_passphrase_dialog.dart';

/// The whole history, in one sealed file, from Settings.
///
/// The conversation screen exports one thread because handing over this
/// conversation must not hand over the rest. Settings is the opposite promise:
/// a backup is meant to be everything, and restore already reads a file with
/// several threads in it. Before this the app could restore a whole history and
/// had no way to write one.
Future<void> exportAllHistory(
  BuildContext context,
  MeshcoreController mc,
) async {
  final AppLocalizations l = AppLocalizations.of(context);
  final List<ChatMessage> rows = mc.allMessages;
  final String? passphrase = await showDialog<String>(
    context: context,
    builder: (BuildContext ctx) => ExportPassphraseDialog(
      l: l,
      title: l.settingsHistoryExportTitle,
      confirmLabel: l.settingsHistoryExportConfirm,
    ),
  );
  if (passphrase == null || !context.mounted) return;
  try {
    final Uint8List bytes = await HistoryExport.encodeHistoryAsync(
      messages: rows,
      passphrase: passphrase,
    );
    // App-support, for the same reason every other export uses it: the
    // FileProvider roots cover `files-path` and `cache-path`, and the
    // documents directory is neither.
    final Directory dir = await getApplicationSupportDirectory();
    final File file = File('${dir.path}/meshmore-history.mmex');
    await file.writeAsBytes(bytes);
    final bool shared = await Share.file(file.path,
        mime: 'application/octet-stream', subject: l.settingsHistoryExportRow);
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        content: Text(shared
            ? l.settingsHistoryExportShared
            : l.settingsHistoryExportDone(file.path))));
  } on ExportRefused catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        content: Text(
            rows.isEmpty ? l.settingsHistoryExportEmpty : l.chatExportFailed)));
    // The refusal's own words are for the field log, not the user.
    meshLog('history', 'export refused: ${e.reason}');
  }
}
