// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';

import '../gen/app_localizations.dart';
import '../meshcore/chat_store.dart';
import '../theme/mm_skin.dart';

/// The line that says the saved history exists but cannot be opened here.
///
/// A sealed store whose key left the device (a restore onto a new phone, a
/// credential reset) reads as no rows. Showing an empty thread over intact
/// data is the one lie this store can still tell, so the state is carried out
/// of `ChatStore` and said above the list, with the way back named.
class HistoryUnreadableNotice extends StatelessWidget {
  const HistoryUnreadableNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ChatStore.unreadable,
      builder: (BuildContext context, bool lost, Widget? _) {
        if (!lost) return const SizedBox.shrink();
        final ColorScheme cs = Theme.of(context).colorScheme;
        final AppLocalizations l = AppLocalizations.of(context);
        final MmSkin skin = context.skin;
        return Container(
          width: double.infinity,
          color: cs.surfaceContainerHighest,
          padding: EdgeInsets.symmetric(
            horizontal: skin.space.step(5),
            vertical: skin.space.step(3),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.lock_outline,
                      size: skin.type.sizeBody, color: cs.onSurfaceVariant),
                  SizedBox(width: skin.space.step(2)),
                  Expanded(
                    child: Text(
                      l.chatHistoryUnreadableTitle,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: skin.type.sizeBody,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: skin.space.step(2)),
              Text(
                l.chatHistoryUnreadableBody,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: skin.type.sizeSm,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
