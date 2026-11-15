// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../gen/app_localizations.dart';
import '../../theme/mm_skin.dart';
import '../../tools/tool_history.dart';
import '../../tools/tools_controller.dart';
import '../../ui/mm_components.dart';
import '../../util/relative_time.dart';
import '../../ui/mm_confirm.dart';
import '../../ui/mm_scaffold.dart';
import 'tool_widgets.dart';
import 'tools_hub_screen.dart';

/// Settings → Tools → History: every finished run, newest first.
///
/// The tools kept nothing before this. A range test's rows lived in memory and
/// left the app as a CSV the reader had to paste somewhere before closing the
/// screen, so "was this repeater working last Tuesday" had no answer the app
/// could give. A run now keeps its one-line summary and its own CSV, and this
/// is where they are read.
///
/// Two bounds are stated on screen rather than implied: how many runs are kept
/// and how much CSV. A run whose table was dropped to stay inside the budget
/// says so on its own row, because a table that silently disappeared is worse
/// than one that was never kept.
class ToolHistoryScreen extends StatelessWidget {
  const ToolHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;
    final ToolHistoryStore store = context.watch<ToolsController>().history;
    final List<ToolRun> runs = store.runs;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.toolHistoryTitle),
        actions: <Widget>[
          if (runs.isNotEmpty)
            IconButton(
              tooltip: l.toolHistoryClear,
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final bool ok = await mmConfirm(
                  context,
                  body: l.toolHistoryClearBody,
                  cancelLabel: l.actionCancel,
                  confirmLabel: l.toolHistoryClear,
                  destructive: true,
                );
                if (ok) await store.clear();
              },
            ),
        ],
      ),
      body: MmScaffold(
        child: ListView(
          padding: skin.space.padScreen,
          children: <Widget>[
            if (store.sealedUnreadable)
              Padding(
                padding: EdgeInsets.only(bottom: skin.space.rowGap),
                child: ToolNotice(
                  text: l.toolHistoryUnreadable,
                  icon: Icons.lock_outline,
                ),
              ),
            if (runs.isEmpty)
              ToolNotice(text: l.toolHistoryEmpty, icon: Icons.history)
            else ...<Widget>[
              ToolLine(
                l.toolHistoryBounds(
                    store.maxRuns, _kb(store.maxCsvBytes)),
                muted: true,
              ),
              const SizedBox(height: 8),
              for (final ToolRun r in runs)
                Padding(
                  padding: EdgeInsets.only(bottom: skin.space.rowGap),
                  child: _RunRow(run: r, l: l, skin: skin),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The CSV budget in the unit a reader thinks in. The store's own number is
/// bytes, and a byte count on a settings row is a number nobody can size.
String _kb(int bytes) => '${(bytes / 1024).round()} KB';

class _RunRow extends StatelessWidget {
  const _RunRow({required this.run, required this.l, required this.skin});

  final ToolRun run;
  final AppLocalizations l;
  final MmSkin skin;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, String name, String _) =
        ToolsHubScreen.entry(l, run.kind);
    final String when = compactAgo(DateTime.now().difference(run.endedAt));
    final String? csv = run.csv;
    return MmListRow(
      leading: Icon(icon, color: skin.color.accent),
      title: Text(name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(run.summary,
              style: TextStyle(
                  color: skin.color.fg, fontSize: skin.type.sizeBody)),
          Text(
            // The failure is named, not implied: a run that ended early says
            // why, in the same words the tool's own screen uses.
            run.failure == null
                ? when
                : '$when · ${toolFailureText(l, run.failure!)}',
            style: TextStyle(
                color: skin.color.fgMuted, fontSize: skin.type.sizeMicro),
          ),
          if (csv == null)
            Text(l.toolHistoryTableDropped,
                style: TextStyle(
                    color: skin.color.fgMuted,
                    fontSize: skin.type.sizeMicro)),
        ],
      ),
      trailing: csv == null
          ? null
          : IconButton(
              tooltip: l.toolsCopyReport,
              icon: const Icon(Icons.copy, size: 18),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: csv));
                ScaffoldMessenger.of(context)
                  ..clearSnackBars()
                  ..showSnackBar(SnackBar(content: Text(l.toolsCopied)));
              },
            ),
    );
  }
}
