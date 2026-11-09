// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'package:meshcore/meshcore.dart' show kAdvTypeChat;

import '../bot/bot_scope.dart';
import '../gen/app_localizations.dart';
import '../meshcore/chat_message.dart';
import '../meshcore/discovered_node.dart';
import '../meshcore/failure.dart';
import '../meshcore/meshcore_controller.dart';
import '../screens/delivery_status_icon.dart';
// The conversation picker is a widget library rather than a screen, and a
// forward is the same question a tool asks: which conversation?
import '../screens/tools/tool_pickers.dart';
import '../ui/mm_confirm.dart';
import 'draft_store.dart';

/// R20 / U11 — per-message Reply / Copy / Delete actions (+ R76 Retry
/// on a failed outgoing row) for chat
/// rows (channel chat **and** DM thread). Long-press a row OR tap
/// the trailing affordance to open this sheet.
enum ChatAction { reply, copy, forward, delete, retry, report }

/// Modal bottom sheet listing the three actions. Returns the chosen
/// action (or null on dismiss). The caller wires the consequences:
/// quoting into the composer (Reply), `Clipboard.setData` + snack
/// (Copy), and `deleteMessageById` with a "OTA can't be recalled"
/// confirmation (Delete).
Future<ChatAction?> showChatActions(BuildContext context, ChatMessage m) async {
  final AppLocalizations l = AppLocalizations.of(context);
  return showModalBottomSheet<ChatAction>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext ctx) => SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Route and signal belong to the transmission, not to the message,
          // so they are said once here instead of on every row of the thread.
          if (_metaLine(l, m) case final String meta)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                meta,
                style: TextStyle(
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  fontSize: Theme.of(ctx).textTheme.labelSmall?.fontSize,
                ),
              ),
            ),
          // `unknown` is offered a retry as well: a send the app could not
          // vouch for is the row a user most wants to try again.
          if (m.outgoing &&
              (m.delivery == MessageDelivery.failed ||
                  m.delivery == MessageDelivery.unknown))
            ListTile(
              leading: const Icon(Icons.refresh),
              title: Text(l.actionRetry),
              subtitle: Text(_retrySubtitle(l, m)),
              onTap: () => Navigator.pop(ctx, ChatAction.retry),
            trailing: const Icon(Icons.chevron_right, size: 18),
            ),
          ListTile(
            leading: const Icon(Icons.reply),
            title: Text(l.actionReply),
            onTap: () => Navigator.pop(ctx, ChatAction.reply),
            trailing: const Icon(Icons.chevron_right, size: 18),
          ),
          ListTile(
            leading: const Icon(Icons.copy_outlined),
            title: Text(l.actionCopy),
            onTap: () => Navigator.pop(ctx, ChatAction.copy),
            trailing: const Icon(Icons.chevron_right, size: 18),
          ),
          // Forward moves the words into another thread's composer rather than
          // sending them for the user: a forward is an ordinary send they can
          // edit or cancel, which is also what makes it safe on a shared mesh.
          ListTile(
            leading: const Icon(Icons.forward_to_inbox_outlined),
            title: Text(l.actionForward),
            subtitle: Text(l.actionForwardSub),
            onTap: () => Navigator.pop(ctx, ChatAction.forward),
            trailing: const Icon(Icons.chevron_right, size: 18),
          ),
          // A report is not a block and not moderation: it is a bundle the
          // reader sends wherever they choose, so it sits beside Copy rather
          // than beside Delete.
          if (!m.outgoing)
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: Text(l.reportAction),
              subtitle: Text(l.reportActionSub),
              onTap: () => Navigator.pop(ctx, ChatAction.report),
            trailing: const Icon(Icons.chevron_right, size: 18),
            ),
          ListTile(
            leading: Icon(Icons.delete_outline,
                color: Theme.of(ctx).colorScheme.error),
            title: Text(l.actionDeleteLocal),
            subtitle: Text(l.actionDeleteLocalSub),
            onTap: () => Navigator.pop(ctx, ChatAction.delete),
            trailing: const Icon(Icons.chevron_right, size: 18),
          ),
          const SizedBox(height: 4),
        ],
      ),
    ),
  );
}

/// APP-N2 — what the transmission itself can say about this row: how it went
/// out, how strong it arrived, and, for our own rows, what the app can vouch
/// for. Null when there is nothing to say, so the sheet stays short.
String? _metaLine(AppLocalizations l, ChatMessage m) {
  final List<String> parts = <String>[
    if (m.isFlood) l.chatMetaFlood,
    if (m.snrDb != null) l.chatMetaSnr(m.snrDb!.toStringAsFixed(1)),
    if (m.outgoing && m.delivery != null) deliveryLabel(l, m.delivery!),
  ];
  if (parts.isEmpty) return null;
  return '${l.chatActionsMeta}: ${parts.join(' · ')}';
}

/// Apply a Copy action: write [m]'s text to the clipboard and show
/// a brief confirmation snack on [scaffoldKey].
Future<void> copyMessageToClipboard(BuildContext context, ChatMessage m) async {
  final AppLocalizations l = AppLocalizations.of(context);
  await Clipboard.setData(ClipboardData(text: m.text));
  if (!context.mounted) return;
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(
      content: Text(l.actionCopied),
      duration: const Duration(seconds: 2),
    ),
  );
}

/// Build a `> quoted text` prefix for a Reply, trimmed to ~80 chars
/// so the composer doesn't get swamped. The caller prepends this to
/// the existing input.
String buildReplyQuote(ChatMessage m) {
  String t = m.text.replaceAll('\n', ' ').trim();
  if (t.length > 80) t = '${t.substring(0, 80)}…';
  return '> $t\n\n';
}

/// Move a message's words into another conversation's composer.
///
/// Forwarding is a *draft*, not a send: the target thread opens with the text
/// in its composer, where the user can edit it, add a line of their own or
/// throw it away. That is also the safe shape on a shared mesh — nothing leaves
/// the phone because a menu row was tapped.
///
/// Returns true when the draft was written and the thread was opened.
Future<bool> forwardMessage(
    BuildContext context, MeshcoreController mc, ChatMessage m) async {
  final AppLocalizations l = AppLocalizations.of(context);
  final ScaffoldMessengerState? sm = ScaffoldMessenger.maybeOf(context);
  final bool anyChannel = mc.channels.isNotEmpty;
  final String? own = mc.ownPubKeyHex;
  final bool anyPeer = mc.nodes.any((DiscoveredNode n) =>
      n.pubKeyHex != own &&
      n.type == kAdvTypeChat &&
      mc.isSyncedContact(n.pubKeyHex));
  if (!anyChannel && !anyPeer) {
    sm
      ?..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(l.forwardNoTarget)));
    return false;
  }
  final (BotScope, String)? dest = await pickConversation(context, mc);
  if (dest == null || !context.mounted) return false;
  final BotScope scope = dest.$1;
  final String key = switch (scope) {
    ChannelScope(:final int idx) => DraftStore.keyFor(
        DraftStore.radioScope(mc.selfInfo?.publicKey),
        channelIdx: idx),
    DmScope(:final String pubKeyHex) => DraftStore.keyFor(
        DraftStore.radioScope(mc.selfInfo?.publicKey),
        peerHex: pubKeyHex),
  };
  try {
    // Append rather than replace, so forwarding into a thread that already has
    // half a sentence does not throw that sentence away.
    final String existing = await DraftStore.read(key);
    final String text =
        existing.trim().isEmpty ? m.text : '$existing\n${m.text}';
    await DraftStore.save(key, text);
  } catch (_) {
    sm
      ?..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(l.forwardFailed)));
    return false;
  }
  if (!context.mounted) return false;
  switch (scope) {
    case ChannelScope(:final int idx):
      mc.setActiveChannel(idx);
    case DmScope(:final String pubKeyHex):
      await context.push('/dm/$pubKeyHex');
  }
  if (!context.mounted) return true;
  sm
    ?..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(l.forwardDone)));
  return true;
}

/// Confirm + delete dialog. Caller passes a deletion closure (so
/// this helper stays platform-agnostic). Returns true if the user
/// confirmed.
Future<bool> confirmDeleteMessage(BuildContext context, ChatMessage m) {
  final AppLocalizations l = AppLocalizations.of(context);
  return mmConfirm(
    context,
    title: l.actionDeleteConfirmTitle,
    body: l.actionDeleteConfirmBody,
    cancelLabel: l.actionCancel,
    confirmLabel: l.actionDelete,
    destructive: true,
  );
}

/// The reason shown under Retry: the catalogue's translated sentence when the
/// row carries a cause, the older stored sentence otherwise (APP-N2).
String _retrySubtitle(AppLocalizations l, ChatMessage m) {
  final FailureCause? cause = m.failCause;
  if (cause != null) {
    return '${l.actionRetrySub} (${failureText(l, Failure(cause))})';
  }
  return m.failReason == null
      ? l.actionRetrySub
      : '${l.actionRetrySub} (${m.failReason})';
}
