// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';

import '../gen/app_localizations.dart';

/// Asks for the passphrase that seals an exported history file, or opens one.
///
/// One dialog for both directions: the words differ, the control does not. It
/// lives outside the chat screen because Settings offers the whole-history
/// export while a conversation offers its own, and two copies of a passphrase
/// prompt would drift — the one thing that must stay the same is that an empty
/// answer reaches the export and is refused there.
class ExportPassphraseDialog extends StatefulWidget {
  const ExportPassphraseDialog({
    super.key,
    required this.l,
    this.title,
    this.fieldLabel,
    this.confirmLabel,
  });

  final AppLocalizations l;
  final String? title;
  final String? fieldLabel;
  final String? confirmLabel;

  @override
  State<ExportPassphraseDialog> createState() => _ExportPassphraseDialogState();
}

class _ExportPassphraseDialogState extends State<ExportPassphraseDialog> {
  final TextEditingController _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title ?? widget.l.chatExportTitle),
      content: TextField(
        key: const ValueKey<String>('chat-export-passphrase'),
        controller: _input,
        obscureText: true,
        autofocus: true,
        decoration: InputDecoration(
            labelText: widget.fieldLabel ?? widget.l.chatExportPassphrase),
        onSubmitted: (String v) => Navigator.of(context).pop(v),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.l.cancel),
        ),
        FilledButton(
          key: const ValueKey<String>('chat-export-confirm'),
          onPressed: () => Navigator.of(context).pop(_input.text),
          child: Text(widget.confirmLabel ?? widget.l.chatExportConfirm),
        ),
      ],
    );
  }
}
