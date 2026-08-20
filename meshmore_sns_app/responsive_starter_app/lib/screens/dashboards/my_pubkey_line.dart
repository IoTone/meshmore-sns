// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../gen/app_localizations.dart';

/// Your own public key, rendered the same way on every skin.
///
/// Deliberately **shared** rather than reimplemented per dashboard.
/// The six dashboards are bespoke by design — reskinning is additive —
/// but this is information, not decoration, and the copy behaviour has
/// a correctness requirement no skin should get to reinterpret: the
/// **full** key must reach the clipboard even though a truncated one is
/// displayed. A partial key pasted to another operator does not error,
/// it silently fails to resolve.
///
/// Colour and font come from the caller so each skin still owns how it
/// looks; only the truncation and the clipboard payload are fixed.
class MyPubkeyLine extends StatelessWidget {
  const MyPubkeyLine({
    super.key,
    required this.pubKeyHex,
    this.style,
    this.iconColor,
    this.shownChars = 16,
  });

  /// Null until `SelfInfo` lands. The line still renders, saying so,
  /// because the moment someone opens the app to ask "what is my key?"
  /// is exactly the moment it has not arrived yet — an absent line
  /// reads as a missing feature.
  final String? pubKeyHex;
  final TextStyle? style;
  final Color? iconColor;
  final int shownChars;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ColorScheme cs = Theme.of(context).colorScheme;
    final TextStyle effective = style ??
        TextStyle(
          color: cs.onSurfaceVariant,
          fontFamily: 'JetBrains Mono',
          fontSize: 12,
          height: 1.5,
        );
    final String? hex = pubKeyHex;

    if (hex == null || hex.isEmpty) {
      return Text(l.dashboardPubkeyAwaiting, style: effective);
    }

    final String shown =
        hex.length > shownChars ? '${hex.substring(0, shownChars)}…' : hex;

    return Tooltip(
      message: l.dashboardPubkeyHint,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () async {
          // The FULL key, never `shown`.
          await Clipboard.setData(ClipboardData(text: hex));
          if (!context.mounted) return;
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(
              content: Text(l.nodeDetailPubkeyCopied),
              duration: const Duration(seconds: 2),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Flexible(
                child: Text(
                  l.dashboardMyPubkey(shown),
                  style: effective,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.copy,
                  size: 13, color: iconColor ?? effective.color ?? cs.primary),
            ],
          ),
        ),
      ),
    );
  }
}
