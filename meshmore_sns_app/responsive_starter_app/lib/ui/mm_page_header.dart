// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';

import '../theme/mm_skin.dart';

/// The title block that sits directly under the tab strip, one per
/// top-level view.
///
/// Why this exists: the app bar used to carry the *tab* name, so the
/// one piece of text at the very top changed every time you switched
/// view — the app never said its own name, and the tab name sat where
/// an app title belongs. Now the app bar is constant and the tab name
/// lives here, in the same place on every view.
///
/// Consistency rule: same horizontal padding, same minimum height, same
/// bottom rule, same title baseline on every view, so switching tabs
/// does not make the content jump. A view may pass `actions` (a filter,
/// a picker, a mode toggle) and, only where it genuinely differs, a
/// `subtitle`. It may not move the title.
class MmPageHeader extends StatelessWidget {
  const MmPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const <Widget>[],
  });

  /// Minimum height, so the first content row starts at the same y on
  /// every view. Taller only when a view supplies a subtitle or tall
  /// actions — never to eyeball a particular screen.
  static const double minHeight = 56;

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final MmSkin skin = context.skin;
    final TextTheme tt = Theme.of(context).textTheme;
    // Deliberately NOT `skin.type.upperHeadings`. This is a page title, not
    // a section label: the app bar showed the localised string verbatim and
    // uppercasing it changes the name the user just navigated to. It is also
    // wrong for locales where uppercasing alters the word.
    final String shown = title;

    final Widget label = Text(
      shown,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: (tt.titleMedium ?? const TextStyle(fontSize: 18)).copyWith(
        color: skin.color.accent,
        letterSpacing: 1.2,
        fontWeight: FontWeight.w600,
      ),
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: minHeight),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: skin.color.line, width: 1),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: <Widget>[
              Expanded(
                child: subtitle == null
                    ? label
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          label,
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: (tt.bodySmall ??
                                    const TextStyle(fontSize: 12))
                                .copyWith(color: skin.color.fgMuted),
                          ),
                        ],
                      ),
              ),
              for (final Widget a in actions) ...<Widget>[
                const SizedBox(width: 4),
                a,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
