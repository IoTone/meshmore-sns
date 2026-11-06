// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../gen/app_localizations.dart';
import '../meshcore/chat_message.dart';
import '../screens/report_bundle.dart';
import '../util/share.dart';

/// APP-F3's sibling: a report is not a block and not moderation.
///
/// There is no server, so nothing is transmitted. The flow asks what the
/// reader saw, writes the bundle to a file on this device, and then offers the
/// things a person can actually do with it: copy it, hand the file to an app
/// that can carry it, or go find it. The copy says no request was made,
/// because a bundle that looks like a submission would be a lie — and the
/// share sheet is the reader choosing a destination, which is the one path the
/// app cannot take for them.
Future<void> reportMessage(
  BuildContext context,
  ChatMessage m, {
  required String threadName,
  String? senderDisplayName,
  Future<File> Function(Map<String, Object?> bundle)? write,
}) async {
  final AppLocalizations l = AppLocalizations.of(context);
  final String? observation = await showDialog<String>(
    context: context,
    builder: (BuildContext ctx) => _ObservationDialog(l: l),
  );
  if (observation == null || !context.mounted) return;

  final Map<String, Object?> bundle = ReportBundle.build(
    message: m,
    channelName: threadName,
    reporterObservation: observation,
    senderDisplayName: senderDisplayName,
  );
  final File file = await (write ?? ReportBundle.write)(bundle);
  if (!context.mounted) return;

  final _ReportChoice? choice = await showDialog<_ReportChoice>(
        context: context,
        builder: (BuildContext ctx) {
      final AppLocalizations lt = AppLocalizations.of(ctx);
      return AlertDialog(
        title: Text(lt.reportSheetTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(lt.reportNothingSent),
            const SizedBox(height: 8),
            SelectableText(lt.reportBundleWritten(file.path)),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(
                text: const JsonEncoder.withIndent('  ').convert(bundle),
              ));
              if (!ctx.mounted) return;
              Navigator.pop(ctx, _ReportChoice.copied);
            },
            child: Text(lt.reportCopyBundle),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _ReportChoice.share),
            child: Text(lt.reportShareBundle),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _ReportChoice.close),
            child: Text(lt.mediaClose),
          ),
        ],
      );
        },
      );
  if (choice == null || choice == _ReportChoice.close || !context.mounted) {
    return;
  }
  // The confirmation is shown by the screen that opened the flow: the
  // dialog's own context is gone by the time the clipboard call returns.
  if (choice == _ReportChoice.copied) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(l.reportCopied)),
    );
    return;
  }
  // The reader picks the destination. If no share handler answers, the path
  // the dialog already showed is repeated rather than a claim that it went.
  final bool shared = await Share.file(file.path,
      mime: 'application/json', subject: l.reportSheetTitle);
  if (!shared && context.mounted) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(l.reportBundleWritten(file.path))),
    );
  }
}

/// What the reader chose after the bundle was written. Three outcomes rather
/// than a bool: "close" must never be read as "copied".
enum _ReportChoice { copied, share, close }

/// The optional sentence the reader adds. Empty is a valid answer: the bundle
/// already carries the message, its sender and its time.
class _ObservationDialog extends StatefulWidget {
  const _ObservationDialog({required this.l});

  final AppLocalizations l;

  @override
  State<_ObservationDialog> createState() => _ObservationDialogState();
}

class _ObservationDialogState extends State<_ObservationDialog> {
  final TextEditingController _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.l.reportSheetTitle),
      content: TextField(
        controller: _text,
        autofocus: true,
        maxLines: 3,
        decoration: InputDecoration(
          labelText: widget.l.reportObservationLabel,
          border: const OutlineInputBorder(),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(widget.l.actionCancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _text.text.trim()),
          child: Text(widget.l.reportAction),
        ),
      ],
    );
  }
}
