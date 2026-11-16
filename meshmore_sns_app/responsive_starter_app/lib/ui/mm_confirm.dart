// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';

import '../theme/mm_skin.dart';

/// One confirmation dialog, so that a delete looks like a delete everywhere.
///
/// Seventeen sites had written the same four pieces by hand — an `AlertDialog`,
/// a title, a body, a Cancel that pops false and a confirm that pops true — and
/// the confirm's own affordance drifted while they did: the deletions in
/// `node_detail_sheet.dart` and `device_contacts_screen.dart` were filled
/// buttons, the one in `network_detail_screen.dart` was a plain `TextButton`,
/// and the region-pack delete in `maps_screen.dart` had no title at all. The
/// act was the same class in every one of them, so a reader had no way to tell
/// from the dialog what it was about to destroy.
///
/// [destructive] is that signal: a destructive confirm inverts to the error
/// tone the app already uses for a delete (`chat_actions.dart`,
/// `channels_screen.dart`), and a non-destructive one stays a plain filled
/// action. Nothing else about the calling screen changes — the title, the body
/// and both labels are passed in, because they are ARB strings and this widget
/// is not a place to rewrite copy.
///
/// [title] is nullable because the region-pack delete never had one; inventing
/// a title for it here would have changed what that dialog says.
///
/// A barrier tap and the system back gesture both return false: setting a
/// checkbox is not a decision, and a dialog whose only true comes from the
/// button cannot be dismissed into one by accident.
Future<bool> mmConfirm(
  BuildContext context, {
  String? title,
  String? body,
  required String cancelLabel,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      title: title == null ? null : Text(title),
      content: body == null ? null : Text(body),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(cancelLabel),
        ),
        if (destructive)
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, true),
            // Filled with the alert *ink*, not the raw alert: the ink is the
            // value that was lifted to be legible, so the ground written on it
            // clears 4.5:1 in every preset. Three skins keep a saturated
            // crimson for the fill, and a label on that fill had no legible
            // option at all (D11.7).
            style: FilledButton.styleFrom(
              backgroundColor: context.skin.color.alertInk,
              foregroundColor: context.skin.color.base,
            ),
            child: Text(confirmLabel),
          )
        else
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
      ],
    ),
  );
  return confirmed ?? false;
}
