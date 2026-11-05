// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';

import '../gen/app_localizations.dart';
import '../meshcore/chat_store.dart';
import '../theme/mm_skin.dart';

/// The line that says a thread has lost older rows to the history cap.
///
/// The cap is 250 rows; when the store drops the oldest, those rows are gone
/// and nothing in the list can show they existed. A chat that quietly gets
/// shorter looks the same as one that never had the messages, so the count is
/// carried out of the store and said here, with the rule named.
class HistoryRetentionNotice extends StatelessWidget {
  const HistoryRetentionNotice({super.key, required this.dropped});

  /// Rows this thread has lost to the cap.
  final int dropped;

  @override
  Widget build(BuildContext context) {
    if (dropped <= 0) return const SizedBox.shrink();
    final ColorScheme cs = Theme.of(context).colorScheme;
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;
    // One line, no banner: the fact matters (APP-E2) and the rule does not
    // need a paragraph to be believed, so this is the smallest thing that
    // still cannot be mistaken for a thread that simply never had the rows.
    return Semantics(
      label: l.chatRetentionDropped(dropped, ChatStore.cap),
      excludeSemantics: true,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: skin.space.step(5),
          vertical: skin.space.step(1),
        ),
        child: Align(
          alignment: Alignment.centerRight,
          child: Text(
            l.chatRetentionDropped(dropped, ChatStore.cap),
            style: TextStyle(
              fontSize: skin.type.sizeMicro,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
