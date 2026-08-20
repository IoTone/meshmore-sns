// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../gen/app_localizations.dart';
import 'bot_controller.dart';
import 'bot_scope.dart';

/// Edit one scope's rulepack (R59).
///
/// A plain text editor rather than a rule builder, on purpose: the
/// rulepack *is* the artefact you diff between soak runs, and a
/// structured editor would put a layer between the operator and the
/// thing they are comparing.
///
/// Parse errors are shown live and are **not** blocking — the engine
/// carries bad lines rather than refusing the pack, so the editor
/// tells the same truth.
class RulepackEditor extends StatefulWidget {
  const RulepackEditor({super.key, required this.scope});

  final BotScope scope;

  @override
  State<RulepackEditor> createState() => _RulepackEditorState();
}

class _RulepackEditorState extends State<RulepackEditor> {
  late final BotController _bot = context.read<BotController>();
  late final TextEditingController _c =
      TextEditingController(text: _bot.rulepackSourceFor(widget.scope));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ColorScheme cs = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Text(l.botRulesTitle),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              controller: _c,
              maxLines: 12,
              minLines: 6,
              style: const TextStyle(
                  fontFamily: 'JetBrains Mono', fontSize: 12),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 6),
            Builder(builder: (BuildContext _) {
              final int errors = _errorCount();
              if (errors == 0) return const SizedBox.shrink();
              return Text(
                l.botRulesErrors(errors),
                style: TextStyle(fontSize: 11, color: cs.error),
              );
            }),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () {
            _bot.setRulepack(widget.scope, null);
            Navigator.pop(context);
          },
          child: Text(l.botRulesRestore),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: () {
            _bot.setRulepack(widget.scope, _c.text);
            Navigator.pop(context);
          },
          child: Text(l.botRulesSave),
        ),
      ],
    );
  }

  // Parse the *draft*, not the saved pack, so the count tracks what is
  // on screen rather than what was last committed.
  int _errorCount() => BotController.errorsIn(_c.text).length;
}
