// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';

import '../gen/app_localizations.dart';
import '../meshcore/chat_message.dart';

/// The translated name of a delivery state.
///
/// One spelling of the fact for two readers: the glyph's tooltip, and the line
/// in the row's actions sheet where the state is written out for anyone who
/// cannot read the icon.
String deliveryLabel(AppLocalizations l, MessageDelivery delivery) =>
    switch (delivery) {
      MessageDelivery.sending => l.deliverySending,
      MessageDelivery.sent => l.deliverySent,
      MessageDelivery.delivered => l.deliveryDelivered,
      MessageDelivery.failed => l.deliveryFailed,
      MessageDelivery.unknown => l.deliveryUnknown,
    };

/// Per-message delivery glyph for outgoing chat/DM rows.
///
/// - sending   → clock (in flight to the radio)
/// - sent      → single check (accepted + transmitted into the mesh;
///               terminal for channel/broadcast)
/// - delivered → double check (DM recipient ack matched)
/// - failed    → alert (send error, or DM with no ack / no path)
/// - unknown   → question (the app stopped mid-send; nothing on the phone
///               can say whether the radio transmitted it)
class DeliveryStatusIcon extends StatelessWidget {
  const DeliveryStatusIcon(this.delivery, {super.key, this.size = 13});

  final MessageDelivery delivery;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final AppLocalizations l = AppLocalizations.of(context);
    final (IconData, Color) g = switch (delivery) {
      MessageDelivery.sending => (Icons.schedule, cs.onSurfaceVariant),
      MessageDelivery.sent => (Icons.check, cs.onSurfaceVariant),
      MessageDelivery.delivered => (Icons.done_all, cs.primary),
      MessageDelivery.failed => (Icons.error_outline, cs.error),
      MessageDelivery.unknown => (Icons.help_outline, cs.onSurfaceVariant),
    };
    return Tooltip(
      message: deliveryLabel(l, delivery),
      child: Icon(g.$1, size: size, color: g.$2),
    );
  }
}
