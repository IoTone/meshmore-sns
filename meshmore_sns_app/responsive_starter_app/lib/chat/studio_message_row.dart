// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';

import '../bot/bot_guards.dart';
import '../bot/bot_tag.dart';
import '../gen/app_localizations.dart';
import '../meshcore/chat_message.dart';
import '../screens/delivery_status_icon.dart';
import '../theme/mm_skin.dart';
import '../util/clock_model.dart';

/// R71 — one chat / DM row under a skin whose [MmType.sansLabels] is on
/// (Studio). The older terminal "log" rows set every part in mono, which
/// reads as a wall: this row follows the type rule *words sans, machine
/// data mono*.
///
/// ```
/// 22:43 | Sender                      (sans, 12, w600, muted)
///       | Message body, sans, 15/1.35  (the reading weight)
///       | flood · SNR 6.5             (mono, 11, muted: machine data)
/// ```
///
/// - **Timestamp** and the **meta line** (route mode, SNR) are mono: they
///   are data and align as a column.
/// - **Sender** and **body** are sans; the sender is smaller, bolder and
///   dimmer, so the body is the primary weight.
/// - **Direction.** The log rows' `«` / `»` glyph (incoming / outgoing,
///   `chat_screen.dart` `_log`) is dropped here: it was an unexplained
///   mark. Outgoing rows instead carry a 2dp accent rule on their left
///   edge and an accent timestamp (a shape cue as well as a colour cue).
class StudioMessageRow extends StatelessWidget {
  const StudioMessageRow({
    super.key,
    required this.message,
    required this.body,
    required this.onAction,
    this.sender,
    this.extraMeta = const <String>[],
    this.echo,
  });

  final ChatMessage message;

  /// Message text with any `name: ` prefix already split off.
  final String body;

  /// Incoming channel sender handle; null for DMs and our own messages.
  final String? sender;

  /// Machine-data fragments after the time (`flood`, `SNR 6.5`).
  final List<String> extraMeta;

  /// An optional line rendered under the body. The place echo uses it, so a
  /// report in the thread says what it means without the row growing a second
  /// layout.
  final Widget? echo;
  final VoidCallback onAction;

  /// APP-N3 — absolute only while the sender's clock agrees with this phone;
  /// see `clockStamp`.
  String _time(AppLocalizations l) => clockStamp(l, message.at);

  @override
  Widget build(BuildContext context) {
    final MmSkin skin = context.skin;
    final AppLocalizations l = AppLocalizations.of(context);
    final String mono = skin.type.monoFamily;
    final bool out = message.outgoing;
    final bool delivery = out && message.delivery != null;
    return InkWell(
      onLongPress: onAction,
      child: Container(
        decoration: out
            ? BoxDecoration(
                border: Border(
                    left: BorderSide(color: skin.color.accent, width: 2)))
            : null,
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // R102 — the gutter follows the text scale. At 1.3x a 56 dp
            // box was too narrow for "16:07" in mono and the time wrapped
            // one character per line ("16:0" / "7") beside the sender.
            SizedBox(
              width: 56 * MediaQuery.textScalerOf(context).scale(1),
              child: Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Text(_time(l),
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                        color: out ? skin.color.accent : skin.color.fgMuted,
                        fontFamily: mono,
                        fontSize: 12)),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (sender != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(sender!,
                          key: const ValueKey<String>('studio-msg-sender'),
                          style: TextStyle(
                              color: skin.color.fgMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ),
                  if (looksLikeBot(body))
                    const Padding(
                      padding: EdgeInsets.only(bottom: 2),
                      child: BotTag(),
                    ),
                  Text(stripBotMarker(body),
                      key: const ValueKey<String>('studio-msg-body'),
                      style: TextStyle(
                          color: skin.color.fg, fontSize: 15, height: 1.35)),
                  if (echo != null) echo!,
                  if (extraMeta.isNotEmpty || delivery)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: <Widget>[
                          if (delivery) ...<Widget>[
                            DeliveryStatusIcon(message.delivery!),
                            const SizedBox(width: 5),
                          ],
                          if (extraMeta.isNotEmpty)
                            Text(extraMeta.join(' · '),
                                key: const ValueKey<String>('studio-msg-meta'),
                                style: TextStyle(
                                    color: skin.color.fgMuted,
                                    fontFamily: mono,
                                    fontSize: 11)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: AppLocalizations.of(context).chatMessageActions,
              iconSize: 18,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: onAction,
              icon: Icon(Icons.more_vert, color: skin.color.fgMuted),
            ),
          ],
        ),
      ),
    );
  }
}
