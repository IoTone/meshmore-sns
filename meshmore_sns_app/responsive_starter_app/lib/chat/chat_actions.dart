// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:meshcore/meshcore.dart'
    show kAdvTypeChat, MeshcoreConnectionState;

import '../bot/bot_scope.dart';
import '../gen/app_localizations.dart';
import '../meshcore/chat_message.dart';
import '../meshcore/discovered_node.dart';
import '../meshcore/meshcore_controller.dart';
import '../meshcore/message_heat.dart' show parseChannelSenderName;
import '../theme/mm_skin.dart';
import 'friendly_ack.dart';
import 'reactions.dart';
import '../screens/delivery_status_icon.dart';
// The conversation picker is a widget library rather than a screen, and a
// forward is the same question a tool asks: which conversation?
import '../screens/tools/tool_pickers.dart';
import '../ui/mm_confirm.dart';
import '../ui/mm_shape.dart';
import '../util/clock_model.dart';
import '../util/mm_format.dart';
import 'draft_store.dart';

/// R20 / U11 — per-message Reply / Copy / Delete actions (+ R76 Retry
/// on a failed outgoing row) for chat
/// rows (channel chat **and** DM thread). Long-press a row OR tap
/// the trailing affordance to open this sheet.
/// What a long-press on a row can do.
///
/// [replyMention] and [quote] are deliberately two rows, not one. Research
/// into the MeshCore ecosystem settled the convention: a channel reply is the
/// original author's name in the message, written `@[Name] text`, because a
/// channel message carries no identity the protocol can prove — the name is
/// the address. `meshcore.js` does exactly this in `Message.reply(...)` with
/// its `mention` option on by default. Our old Reply produced `> quoted text`,
/// which no MeshCore client reads as a reply, so a reply from here was just
/// prose with a `>` in front of it.
///
/// They are still separate actions because they answer different questions:
/// "reply to this person" addresses them, "quote this message" puts their
/// words in the box. A reader who wants one does not always want the other.
enum ChatAction {
  /// React with an emoji. The sheet closes with [ChatAction.react] and the
  /// caller opens the palette, because a picker inside a menu is two scrolls.
  react,
  /// Answer with this radio's own measurements of how the row arrived: the
  /// de-facto `ack: SNR …` line. Not the protocol's ACK, which is a checksum on
  /// the wire and has no chat form.
  friendlyAck,
  replyMention,
  quote,
  copy,
  forward,
  delete,
  retry,
  report,
  block,
}

/// The channel-reply prefix MeshCore clients read as a reply: `@[Name] `.
///
/// Returns null when the row names nobody, which is every outgoing message and
/// any incoming line whose sender prefix could not be parsed. A reply to
/// nobody is not a reply, so the caller offers the plain quote instead.
String? mentionPrefixFor(String? sender) {
  final String name = (sender ?? '').trim();
  if (name.isEmpty) return null;
  return '@[$name] ';
}

/// Modal bottom sheet listing the three actions. Returns the chosen
/// action (or null on dismiss). The caller wires the consequences:
/// quoting into the composer (Reply), `Clipboard.setData` + snack
/// (Copy), and `deleteMessageById` with a "OTA can't be recalled"
/// confirmation (Delete).
Future<ChatAction?> showChatActions(BuildContext context, ChatMessage m) async {
  final AppLocalizations l = AppLocalizations.of(context);
  // The key a block would name, when this row proves one: a direct message
  // carries its sender's key, a channel line carries only a name in prose.
  final String? blockableKeyHex = m.outgoing
      ? null
      : (m.peerPubKeyHex != null && m.peerPubKeyHex!.length == 64
          ? m.peerPubKeyHex
          : null);
  // The addressable name, if this row has one: the parsed channel sender, or
  // null for our own messages and for a line whose prefix did not parse.
  final String? sender = m.outgoing ? null : parseChannelSenderName(m.text);
  // With no radio the composer is replaced by the connect row, so a reply or a
  // quote would be written into a box nobody can see. The actions still work —
  // the text waits in the draft — but the sheet says so rather than closing on
  // a tap that appeared to do nothing.
  final bool canCompose =
      context.read<MeshcoreController>().state == MeshcoreConnectionState.ready;
  return showModalBottomSheet<ChatAction>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext ctx) => SafeArea(
      top: false,
      // Scrollable, because this list is seven rows on a long-press that
      // offers retry, report and both reply forms, and a bottom sheet is capped
      // at 9/16 of the screen: the extra row pushed it 162 px past that cap at
      // 420 x 900. A menu that clips its own last row is a menu with a dead
      // action.
      child: SingleChildScrollView(
        child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Route and signal belong to the transmission, not to the message,
          // so they are said once here instead of on every row of the thread.
          if (_metaLine(l, m, prefs: context.formatPrefs)
              case final String meta)
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
          if (!canCompose)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                l.chatActionsNoRadio,
                key: const ValueKey<String>('chat-actions-no-radio'),
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
              title: Text(l.actionRetrySend),
              onTap: () => Navigator.pop(ctx, ChatAction.retry),
            trailing: const Icon(Icons.chevron_right, size: 18),
            ),
          // A reaction is the cheapest answer there is on a mesh: one short
          // line, and every client that speaks MeshCore One's format folds it
          // into the row it names instead of adding a message.
          ListTile(
            key: const ValueKey<String>('chat-action-react'),
            leading: const Icon(Icons.emoji_emotions_outlined),
            title: Text(l.actionReact),
            enabled: canCompose,
            onTap: canCompose
                ? () => Navigator.pop(ctx, ChatAction.react)
                : null,
            trailing: const Icon(Icons.chevron_right, size: 18),
          ),
          // A friendly ack answers the other question a signal report answers:
          // not "who are you talking to" but "how did that arrive". Offered only
          // for a received row this radio actually measured, because the line
          // states numbers and a number it does not have would be invented.
          if (canFriendlyAck(
              outgoing: m.outgoing,
              snrDb: m.snrDb,
              hopCount: m.hopCount,
              pathHashes: m.pathHashes))
            ListTile(
              key: const ValueKey<String>('chat-action-friendly-ack'),
              leading: const Icon(Icons.wifi_tethering),
              title: Text(l.actionFriendlyAck),
              enabled: canCompose,
              onTap: canCompose
                  ? () => Navigator.pop(ctx, ChatAction.friendlyAck)
                  : null,
              trailing: const Icon(Icons.chevron_right, size: 18),
            ),
          // Two answers, because they are different questions: address the
          // person (the MeshCore reply) or put their words in the box.
          ListTile(
            leading: const Icon(Icons.reply),
            title: Text(sender == null
                ? l.actionReplyNoName
                : l.actionReplyMention(sender)),
            enabled: sender != null,
            onTap: sender == null
                ? null
                : () => Navigator.pop(ctx, ChatAction.replyMention),
            trailing: const Icon(Icons.chevron_right, size: 18),
          ),
          ListTile(
            leading: const Icon(Icons.format_quote),
            title: Text(l.actionQuote),
            onTap: () => Navigator.pop(ctx, ChatAction.quote),
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
            onTap: () => Navigator.pop(ctx, ChatAction.forward),
            trailing: const Icon(Icons.chevron_right, size: 18),
          ),
          // Blocking belongs here, on the row the person just read: it is the
          // moment a reader decides not to hear from someone again, and until
          // now the app could only *unblock* — `BlockStore.block` had no caller
          // at all, so the blocked-keys screen explained a feature nobody could
          // reach.
          //
          // It needs a full key, which an inbound direct message carries and a
          // channel row does not: a channel line names its sender in text and
          // nothing else, so the offer is made only where the key is provable.
          if (!m.outgoing && blockableKeyHex != null)
            ListTile(
              key: const ValueKey<String>('chat-action-block'),
              leading: Icon(Icons.block, color: Theme.of(ctx).colorScheme.error),
              title: Text(l.actionBlock),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () => Navigator.pop(ctx, ChatAction.block),
            ),
          // A report is not a block and not moderation: it is a bundle the
          // reader sends wherever they choose, so it sits beside Copy rather
          // than beside Delete.
          if (!m.outgoing)
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: Text(l.reportAction),
              onTap: () => Navigator.pop(ctx, ChatAction.report),
            trailing: const Icon(Icons.chevron_right, size: 18),
            ),
          ListTile(
            leading: Icon(Icons.delete_outline,
                color: Theme.of(ctx).colorScheme.error),
            title: Text(l.actionDeleteLocal),
            onTap: () => Navigator.pop(ctx, ChatAction.delete),
            trailing: const Icon(Icons.chevron_right, size: 18),
          ),
          const SizedBox(height: 4),
        ],
        ),
      ),
    ),
  );
}

/// APP-N2 — what the transmission itself can say about this row: how it went
/// out, how strong it arrived, and, for our own rows, what the app can vouch
/// for. Null when there is nothing to say, so the sheet stays short.
String? _metaLine(AppLocalizations l, ChatMessage m, {FormatPrefs? prefs}) {
  // The time leads, because it is the fact a row deliberately does not print:
  // a thread of stamps reads as a log file, so the sheet is where you go to ask
  // and this is the first thing it answers.
  final List<String> parts = <String>[
    clockStamp(l, m.at, clock24: prefs?.clock24 ?? true),
    if (m.isFlood) l.chatMetaFlood,
    if (m.snrDb != null) l.chatMetaSnr(m.snrDb!.toStringAsFixed(1)),
    if (m.outgoing && m.delivery != null) deliveryLabel(l, m.delivery!),
  ];
  if (parts.isEmpty) return null;
  return parts.join(' · ');
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

/// Asks for one emoji from the fixed palette.
///
/// A grid of eight rather than a full emoji picker: a reaction on a mesh is a
/// gesture, the whole line has a byte budget, and eight is what fits a sheet on
/// a 320 dp phone without a scroll. The same eight in both threads, so a reader
/// learns them once.
Future<String?> pickReaction(
  BuildContext context, {
  Set<String> alreadySent = const <String>{},
}) async {
  final AppLocalizations l = AppLocalizations.of(context);
  final MmSkin skin = context.skin;
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.fromLTRB(skin.space.screenEdge, 0,
                skin.space.screenEdge, skin.space.rowGap),
            child: Text(l.actionReact,
                style: TextStyle(
                    color: skin.color.fg,
                    fontSize: skin.type.sizeBodyLg,
                    fontWeight: FontWeight.w600)),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
                skin.space.rowInset, 0, skin.space.rowInset, skin.space.rowInset),
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: <Widget>[
                for (final String emoji in Reactions.palette)
                  InkWell(
                    key: ValueKey<String>('react-$emoji'),
                    onTap: () => Navigator.pop(ctx, emoji),
                    borderRadius: mmRadius(context, 8),
                    // An emoji this message already carries from this app is
                    // marked, so the sheet says what a second tap would do
                    // instead of offering it as though it were new. The tap is
                    // not a no-op that does nothing visible: it is the same
                    // reaction, and sending it again would count the reactor
                    // twice on every other client.
                    child: Container(
                      // The tap floor, not a smaller target: a reaction is a
                      // one-thumb gesture.
                      width: kMinInteractiveDimension,
                      height: kMinInteractiveDimension,
                      // Decorated only when this app has already sent it, so an
                      // unused emoji is a bare glyph rather than a boxed one.
                      decoration: alreadySent.contains(emoji)
                          ? ShapeDecoration(
                              color: skin.color.surfaceAlt,
                              shape: mmShapeBorder(skin.shape,
                                  side: BorderSide(color: skin.color.line)),
                            )
                          : null,
                      child: Center(
                        child: Text(emoji,
                            style: TextStyle(fontSize: skin.type.size(24))),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
