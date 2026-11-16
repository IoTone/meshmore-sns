// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../chat/block_actions.dart';
import '../chat/chat_actions.dart';
import '../chat/report_flow.dart';
import '../chat/composer_budget.dart';
import '../chat/composer_counter.dart';
import '../chat/composer_field.dart';
import '../chat/composer_offline.dart';
import '../chat/draft_store.dart';
import '../chat/place_suggestion_line.dart';
import '../chat/studio_message_row.dart';
import '../cue/cue_service.dart';
import '../gen/app_localizations.dart';
import '../bot/bot_guards.dart';
import '../bot/bot_tag.dart';
import '../meshcore/chat_message.dart';
import '../sns/place_inference.dart';
import 'delivery_status_icon.dart';
import '../meshcore/discovered_node.dart';
import '../meshcore/meshcore_controller.dart';
import '../chat/history_retention_notice.dart';
import '../notifications/notification_focus.dart';
import '../theme/mm_skin.dart';
import '../util/clock_model.dart';
import '../tts/tts_controller.dart';
import '../ui/mm_components.dart';
import '../ui/mm_scaffold.dart';
import 'node_detail_sheet.dart';
import 'package:meshcore/meshcore.dart';


/// The time column's width at 1x text, in pixels, before the text scale is
/// applied. It holds a five-character stamp, so it is geometry rather than a
/// rhythm value.
const double _timeGutter = 56;

/// 1:1 direct-message thread with a peer (P2P). The MeshCore
/// companion protocol carries DMs over `CMD_SEND_TXT_MSG` (0x02)
/// addressed by the first 6 bytes of the peer's pubkey, and
/// `RESP_CODE_CONTACT_MSG_RECV` (0x07 / V3 0x10) on receive. We
/// thread by the peer's full pubkey when we can resolve it from the
/// fabric, else by the 12-hex prefix.
class DmScreen extends StatefulWidget {
  const DmScreen({super.key, required this.peerPubKeyHex});

  /// Full pubkey hex (64) or 12-hex prefix.
  final String peerPubKeyHex;

  @override
  State<DmScreen> createState() => _DmScreenState();
}

class _DmScreenState extends State<DmScreen> {
  final TextEditingController _input = TextEditingController();

  /// APP-D1 — DM text is bounded by the same radio buffer as a channel
  /// message, so the same model counts it. The prefix is the sender's name,
  /// which the radio writes, not the body.
  ComposerBudget _budget = ComposerBudget.forSender(null);
  String _budgetName = '<unknown>';

  void _syncBudget(MeshcoreController mc) {
    final String name = mc.selfInfo?.name ?? '';
    if (name == _budgetName) return;
    _budgetName = name;
    final ComposerBudget next = ComposerBudget.forSender(name);
    if (next.prefixBytes == _budget.prefixBytes &&
        next.prefixKnown == _budget.prefixKnown) {
      return;
    }
    setState(() => _budget = next);
  }

  final ScrollController _scroll = ScrollController();
  StreamSubscription<ChatMessage>? _sub;
  NotificationFocus? _focus;
  int _lastCount = 0;

  /// APP-E7 — the draft key for this thread, and its pending debounced write.
  /// A thread draft is keyed by the radio and the peer, so the same peer on a
  /// second radio is a second conversation with its own unsent text.
  String? _draftKey;

  /// The controller this screen is listening to, so `dispose` can detach.
  MeshcoreController? _owner;
  Timer? _draftTimer;

  /// The message the last send created, so a failure can put the text back.
  String? _sentId;
  String _sentText = '';

  /// The route this thread is drawn in, so the focus follows the route stack:
  /// a thread pushed over this one hides it, and popping back shows it again.
  ModalRoute<void>? _route;
  bool _syncScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ModalRoute<void>? route = ModalRoute.of(context);
    if (route == _route) return;
    _route?.animation?.removeListener(_scheduleSync);
    _route?.secondaryAnimation?.removeListener(_scheduleSync);
    _route = route;
    route?.animation?.addListener(_scheduleSync);
    route?.secondaryAnimation?.addListener(_scheduleSync);
    _scheduleSync();
  }

  /// Whether this thread is on screen is a fact about the route stack, and the
  /// stack settles at the end of a transition rather than at the start: a
  /// pushed route is built before it is current, and a covered one becomes
  /// current only after the route above is gone. Both animations therefore end
  /// with a re-read, once, on the next frame.
  void _scheduleSync() {
    if (_syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (!mounted) return;
      final bool current = ModalRoute.of(context)?.isCurrent ?? true;
      _focus?.openPeer = current ? widget.peerPubKeyHex : null;
    });
  }

  @override
  void initState() {
    super.initState();
    final MeshcoreController mc = context.read<MeshcoreController>();
    _draftKey = _keyFor(mc);
    _input.addListener(_onComposerChanged);
    unawaited(_recall());
    mc.addListener(_onControllerChanged);
    _owner = mc;
    // No special live action needed — the controller's _ingestDm
    // already adds inbound DMs to the store and notifies. The
    // stream subscription is here only as a hook for future per-DM
    // TTS / haptic (R5/R12) without rebuilding the chat-screen
    // pattern.
    _sub = mc.incomingDirectMessages.listen((ChatMessage m) {
      // Stay caught up: any new inbound DM that lands while the
      // user is on this thread is read by definition.
      if (m.peerPubKeyHex != null) {
        mc.markDmRead(widget.peerPubKeyHex);
      }
    });
    // Opening the thread marks everything currently in it as read.
    mc.markDmRead(widget.peerPubKeyHex);
    // D8.20 — a message on the thread already on screen is not announced.
    _focus = context.read<NotificationFocus?>();
    _focus?.openPeer = widget.peerPubKeyHex;
  }

  @override
  void dispose() {
    _route?.animation?.removeListener(_scheduleSync);
    _route?.secondaryAnimation?.removeListener(_scheduleSync);
    // Only the visible thread clears the record: a covered one is disposed by
    // a pop that already handed the focus back to the thread underneath.
    if (_focus?.openPeer == widget.peerPubKeyHex) _focus?.openPeer = null;
    _sub?.cancel();
    // A listener left on a process-lifetime notifier keeps the dead State (and
    // its disposed controllers) alive and runs on every notification — several
    // per second during a drain. One per visited thread, forever.
    _owner?.removeListener(_onControllerChanged);
    _input.removeListener(_onComposerChanged);
    // Flush before cancelling: a debounce that dies with the screen loses the
    // last thing typed, so backing out inside 700 ms cut the draft short.
    if (_draftTimer != null && _draftTimer!.isActive) {
      final String? key = _draftKey;
      final String text = _input.text;
      if (key != null && text.trim().isNotEmpty) {
        unawaited(DraftStore.save(key, text));
      }
    }
    _draftTimer?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String _keyFor(MeshcoreController mc) => DraftStore.keyFor(
        DraftStore.radioScope(mc.selfInfo?.publicKey),
        peerHex: widget.peerPubKeyHex,
      );

  /// The radio can answer its self-info after this screen opened, which moves
  /// the draft out of the `noradio` namespace and into the real one.
  void _onControllerChanged() {
    if (!mounted) return;
    final MeshcoreController mc = context.read<MeshcoreController>();
    final String key = _keyFor(mc);
    if (key != _draftKey) {
      final String? previous = _draftKey;
      final String typed = _input.text;
      _draftKey = key;
      _draftTimer?.cancel();
      _draftTimer = null;
      if (previous != null) unawaited(DraftStore.save(previous, typed));
      unawaited(_recall());
    }
    _restoreIfFailed(mc);
  }

  Future<void> _recall() async {
    final String? key = _draftKey;
    if (key == null) return;
    final String draft = await DraftStore.read(key);
    if (!mounted || key != _draftKey || draft.isEmpty) return;
    if (_input.text.isNotEmpty) return;
    setState(() => _input.text = draft);
    _input.selection = TextSelection.collapsed(offset: draft.length);
  }

  /// One write per pause, keyed to the draft it belongs to.
  void _onComposerChanged() {
    // The send control's enabled state is a function of the text, so every
    // keystroke rebuilds the composer.
    setState(() {});
    final String? key = _draftKey;
    if (key == null) return;
    final String text = _input.text;
    _draftTimer?.cancel();
    _draftTimer = Timer(DraftStore.debounce, () {
      unawaited(DraftStore.save(key, text));
    });
  }

  /// A failed direct message gives the text back rather than leaving an empty
  /// composer under a red row.
  void _restoreIfFailed(MeshcoreController mc) {
    final String? id = _sentId;
    if (id == null || _sentText.isEmpty) return;
    ChatMessage? found;
    for (final ChatMessage m in mc.dmHistoryFor(widget.peerPubKeyHex)) {
      if (m.id == id) {
        found = m;
        break;
      }
    }
    if (found == null ||
        (found.delivery != MessageDelivery.failed &&
            found.delivery != MessageDelivery.unknown)) {
      return;
    }
    _sentId = null;
    final String text = _sentText;
    _sentText = '';
    if (!mounted || _input.text.isNotEmpty) return;
    setState(() => _input.text = text);
    _input.selection = TextSelection.collapsed(offset: text.length);
    final String? key = _draftKey;
    if (key != null) unawaited(DraftStore.save(key, text));
  }

  String _peerName(MeshcoreController mc) {
    for (final DiscoveredNode n in mc.nodes) {
      if (n.pubKeyHex == widget.peerPubKeyHex ||
          n.pubKeyHex.startsWith(widget.peerPubKeyHex)) {
        return n.name.isEmpty ? n.shortId : n.name;
      }
    }
    return widget.peerPubKeyHex.length >= 12
        ? widget.peerPubKeyHex.substring(0, 12)
        : widget.peerPubKeyHex;
  }

  /// Find the matching [DiscoveredNode] in the fabric, by full pubkey
  /// or prefix. Null if the peer hasn't been heard from yet —
  /// shouldn't happen in practice (we got their pubkey from a DM)
  /// but we degrade gracefully.
  DiscoveredNode? _peerNode(MeshcoreController mc) {
    for (final DiscoveredNode n in mc.nodes) {
      if (n.pubKeyHex == widget.peerPubKeyHex ||
          n.pubKeyHex.startsWith(widget.peerPubKeyHex)) {
        return n;
      }
    }
    return null;
  }

  /// Open the peer's [NodeDetailSheet] — the same sheet you get
  /// from tapping a pin on /grid or /globe, scoped to this DM's
  /// peer. Gives DM users a path to favourite, tag, see distance,
  /// open-in-maps, etc. without leaving the thread.
  Future<void> _openPeerDetail(MeshcoreController mc) async {
    final DiscoveredNode? n = _peerNode(mc);
    if (n == null) {
      // The peer hasn't shown up on the fabric yet (e.g. we got a
      // DM but never heard their advert). Nothing to show; toast
      // explicitly so the user isn't left wondering why the button
      // did nothing.
      final AppLocalizations l = AppLocalizations.of(context);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(l.dmPeerNotInFabric),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext _) => NodeDetailSheet(
        node: n,
        distanceMeters: n.hasLocation
            ? mc.distanceMetersTo(n.latitude!, n.longitude!)
            : null,
        isFavourite: mc.favorites.contains(n.pubKeyHex),
        isKnown: mc.known.contains(n.pubKeyHex),
        onToggleFavourite: () => mc.toggleFavorite(n.pubKeyHex),
        proximity: mc.proximityFor(n),
        cameFromDm: true,
        recentDms: mc.dmHistoryFor(n.pubKeyHex),
        tags: mc.tagsFor(n.pubKeyHex),
        tagSuggestions: mc.allTags,
        onAddTag: (String t) => mc.addTagTo(n.pubKeyHex, t),
        onRemoveTag: (String t) => mc.removeTagFrom(n.pubKeyHex, t),
      ),
    );
  }

  void _send(MeshcoreController mc) {
    final String t = _input.text;
    if (t.trim().isEmpty) return;
    // The send button is disabled for these three, but the text field's own
    // send action is not, so each refusal is stated here as well. Without the
    // first two the controller returned null and the reader was told "no
    // MeshCore radio" while the radio was connected and simply waiting on the
    // last message.
    final AppLocalizations l = AppLocalizations.of(context);
    if (!mc.isReady) {
      context.cue?.play(CueKind.taskError);
      ScaffoldMessenger.maybeOf(context)
        ?..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(l.dmSendNotSent)));
      return;
    }
    if (mc.hasUnsettledDmTo(widget.peerPubKeyHex)) {
      context.cue?.play(CueKind.taskError);
      ScaffoldMessenger.maybeOf(context)
        ?..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(l.dmWaitingForAck)));
      return;
    }
    if (mc.isPeerBlocked(widget.peerPubKeyHex)) {
      context.cue?.play(CueKind.taskError);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).dmBlockedRefused)),
      );
      return;
    }
    final String? key = _draftKey;
    // Cleared on the send, put back by [_restoreIfFailed] if the row fails.
    if (key != null) {
      _draftTimer?.cancel();
      unawaited(DraftStore.clear(key));
    }
    _sentText = t;
    _sentId = null;
    // Cleared only once a row exists. `sendDirectText` returns null when the
    // radio is not ready or when the in-flight ceiling is reached, and the text
    // used to be cleared first: the message vanished from the composer with no
    // row and no explanation.
    unawaited(mc.sendDirectText(widget.peerPubKeyHex, t).then(
      (ChatMessage? m) {
        if (!mounted) return;
        if (m == null) {
          _restoreComposer(t, key);
          context.cue?.play(CueKind.taskError);
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context).dmSendNotSent)),
          );
          return;
        }
        // Same tick as a channel send: the pack carries one "that went" sound,
        // and a DM that leaves should sound like a message leaving.
        context.cue?.play(CueKind.send);
        _sentId = m.id;
        _input.clear();
      },
    ));
  }

  /// Put a message back in the composer after a send that produced no row.
  ///
  /// Only when the field is still empty: a reader who has started typing
  /// something else must not have it replaced by the message that failed.
  void _restoreComposer(String text, String? draftKey) {
    if (_input.text.isNotEmpty) return;
    setState(() {
      _input.text = text;
      _input.selection = TextSelection.collapsed(offset: text.length);
    });
    if (draftKey != null) unawaited(DraftStore.save(draftKey, text));
  }

  Future<void> _onAction(MeshcoreController mc, ChatMessage m) async {
    final ChatAction? action = await showChatActions(context, m);
    if (action == null || !mounted) return;
    switch (action) {
      case ChatAction.replyMention:
        // A direct message is already addressed to exactly one node, so there
        // is nobody to name: the reply is the quote, and the thread is the
        // address. MeshCore has no reply field on a DM at all.
        final String quote = buildReplyQuote(m);
        _input.text = quote + _input.text;
        _input.selection = TextSelection.collapsed(offset: _input.text.length);
        break;
      case ChatAction.quote:
        final String quote = buildReplyQuote(m);
        _input.text = quote + _input.text;
        _input.selection = TextSelection.collapsed(offset: _input.text.length);
        break;
      case ChatAction.friendlyAck:
        // Composed, never sent: an acknowledgement is a message like any other,
        // so it lands in the composer where the reader can add a word, drop a
        // number, or decide not to send it at all.
        final String line = mc.friendlyAckLineFor(m);
        setState(() {
          _input.text = line;
          _input.selection = TextSelection.collapsed(offset: line.length);
        });
        final String? key = _draftKey;
        if (key != null) unawaited(DraftStore.save(key, line));
        break;
      case ChatAction.copy:
        await copyMessageToClipboard(context, m);
        break;
      case ChatAction.react:
        final String? emoji = await pickReaction(context,
            alreadySent: m.ownReactions);
        if (emoji != null && mounted) await mc.reactTo(m, emoji);
        break;
      case ChatAction.forward:
        await forwardMessage(context, mc, m);
        break;
      case ChatAction.retry:
        final RetryOutcome r = await mc.retryMessageOutcome(m.id);
        if (r == RetryOutcome.sentAfterPathReset && mounted) {
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(SnackBar(
                content: Text(AppLocalizations.of(context).retryPathReset)));
        }
        break;
      case ChatAction.block:
        final String? key = m.peerPubKeyHex;
        if (key != null) await confirmAndBlock(context, pubKeyHex: key);
        break;
      case ChatAction.report:
        if (!mounted) return;
        await reportMessage(
          context,
          m,
          threadName: _peerName(mc),
          senderDisplayName: _peerName(mc),
        );
        break;
      case ChatAction.delete:
        if (!mounted) return;
        final bool ok = await confirmDeleteMessage(context, m);
        if (ok) mc.deleteMessageById(m.id);
        break;
    }
  }

  void _autoScroll(int count) {
    if (count == _lastCount) return;
    _lastCount = count;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final MeshcoreController mc = context.watch<MeshcoreController>();
    final TtsController tts = context.watch<TtsController>();
    // Which thread is on screen follows the route stack, not this widget's
    // lifetime: a second DM pushed over this one hides it, and popping back
    // has to claim it again, or the visible thread is announced while it is
    // being read and the hidden one is not.
    _focus?.openPeer = (ModalRoute.of(context)?.isCurrent ?? true)
        ? widget.peerPubKeyHex
        : null;
    _syncBudget(mc);
    final ColorScheme cs = Theme.of(context).colorScheme;
    final bool ready = mc.state == MeshcoreConnectionState.ready;
    // One message in flight per contact: the composer says so rather than
    // accepting a tap the controller would refuse.
    final bool waiting = mc.hasUnsettledDmTo(widget.peerPubKeyHex);
    // A blocked key is refused here rather than at the controller, because the
    // reader needs the reason and not a message that vanishes. The controller
    // refuses too, for the callers that are not a composer.
    final bool blocked = mc.isPeerBlocked(widget.peerPubKeyHex);
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;
    final List<ChatMessage> msgs = mc.dmHistoryFor(widget.peerPubKeyHex);
    _autoScroll(msgs.length);

    return Scaffold(
      appBar: AppBar(
        // The route is already a DM and the header already says whose, so the
        // title is the peer and nothing else. The key is a copy away for the
        // reader who needs it, and lives in full in Peer details.
        title: GestureDetector(
          onLongPress: () => copyPeerKey(context, widget.peerPubKeyHex),
          child: Text(l.dmTitle(_peerName(mc))),
        ),
        actions: <Widget>[
          _SpeechMenu(tts: tts, peerPubKeyHex: widget.peerPubKeyHex, l: l),
          IconButton(
            tooltip: l.dmOpenPeerDetail,
            // The peer, not the page: this opens their details sheet, and an
            // `info` mark in an app bar is read as "about this screen"
            // everywhere else in the app.
            icon: const Icon(Icons.person_outline),
            onPressed: () => _openPeerDetail(mc),
          ),
        ],
      ),
      body: MmScaffold(
        // Same rule as the channel thread: no position bar over a list that
        // appends at its own bottom.
        edgeProgress: false,
        child: Column(
          children: <Widget>[
            HistoryRetentionNotice(
                dropped: mc.droppedForPeer(widget.peerPubKeyHex)),
            Expanded(
              child: msgs.isEmpty
                  ? Center(
                      child: Text(l.dmEmpty,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: cs.onSurfaceVariant)),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      itemCount: msgs.length,
                      itemBuilder: (BuildContext _, int i) => _DmRow(
                        msgs[i],
                        onAction: () => _onAction(mc, msgs[i]),
                      ),
                    ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                // The same inset as the channel composer: two composers for
                // the same act (type, then send) had two different rhythms,
                // which is the kind of difference a user feels without being
                // able to name.
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                child: !ready
                    ? ComposerOffline(connecting: mc.isConnecting)
                    : Row(
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                TextField(
                                  controller: _input,
                                  textInputAction: TextInputAction.send,
                                  onSubmitted: (_) => _send(mc),
                                  decoration: composerFieldDecoration(context,
                                      hint: l.dmComposerHint(_peerName(mc))),
                                ),
                                ComposerCounter(
                                  budget: _budget,
                                  text: _input.text,
                                  label: l,
                                ),
                                if (waiting)
                                  Text(l.dmWaiting,
                                      style: TextStyle(
                                          color: cs.onSurfaceVariant,
                                          fontSize: skin.type.sizeSm)),
                                if (blocked)
                                  Text(l.dmBlockedNotice,
                                      style: TextStyle(
                                          color: cs.onSurfaceVariant,
                                          fontSize: skin.type.sizeSm)),
                              ],
                            ),
                          ),
                          // Same rule as the channel composer: a disabled
                          // send rather than a tap that returns in silence.
                          // The third condition is the radio's own limit: one
                          // message in flight per contact, because the firmware
                          // keeps eight pending ACKs in a circular table and a
                          // second send to the same contact can overwrite the
                          // first one's entry.
                          IconButton(
                            tooltip: blocked
                                ? l.dmBlockedNotice
                                : waiting
                                    ? l.dmWaiting
                                    : l.dmSend,
                            onPressed: _input.text.trim().isEmpty ||
                                    !_budget.canSend(_input.text) ||
                                    waiting ||
                                    blocked ||
                                    !mc.isReady
                                ? null
                                : () => _send(mc),
                            icon: const Icon(Icons.send),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Long-press on the title copies the peer key, which is the one thing an
/// operator needs to compare against the other end's screen.
Future<void> copyPeerKey(BuildContext context, String key) async {
  final AppLocalizations l = AppLocalizations.of(context);
  await Clipboard.setData(ClipboardData(text: key));
  if (!context.mounted) return;
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(
      content: Text(l.dmKeyCopied),
      duration: const Duration(seconds: 2),
    ),
  );
}

class _DmRow extends StatelessWidget {
  const _DmRow(this.m, {required this.onAction});
  final ChatMessage m;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final MmSkin skin = context.skin;
    final AppLocalizations l = AppLocalizations.of(context);
    final String mono = skin.type.monoFamily;
    // A direct message that carries a position is the one place a stranger can
    // tell us where they are, and the row offered nothing: the coordinate sat
    // in the text and the map never learned it. The offer is the same one a
    // channel row makes, with the message's own position rather than ours.
    final InferredPlace? carried = context.select<MeshcoreController, InferredPlace?>(
        (MeshcoreController mc) => mc.coordinateSuggestionFor(m));
    // The same stamp as a channel row: `clockStamp` names a sender whose clock
    // disagrees instead of printing their time as fact (APP-N3). A DM that
    // formatted its own `HH:MM` here was the one list where a fast sender's
    // future time still read as the truth.
    final String time = clockStamp(l, m.at);
    final String tag = m.outgoing ? '»' : '«';
    // Route and signal are facts about the transmission, not the message:
    // they are said in the row's actions sheet, not on every row here.
    if (skin.type.sansLabels) {
      final Widget row =
          StudioMessageRow(message: m, body: m.text, onAction: onAction);
      if (carried == null) return row;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          row,
          PlaceSuggestionLine(
              message: m, name: carried.displayName, place: carried),
        ],
      );
    }
    return InkWell(
      onLongPress: onAction,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // R102 — the gutter scales with the text, as on a channel row: at
            // 1.3x a 56 dp box wrapped a five-character time one character
            // per line.
            SizedBox(
              width: _timeGutter *
                  MediaQuery.textScalerOf(context).scale(1),
              child: Text('$time $tag',
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                      color:
                          m.outgoing ? skin.color.accent : skin.color.fgMuted,
                      fontFamily: mono,
                      fontSize: skin.type.sizeBody)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (looksLikeBot(m.text))
                    const Padding(
                      padding: EdgeInsets.only(bottom: 2),
                      child: BotTag(),
                    ),
                  Text(stripBotMarker(m.text),
                      style: TextStyle(color: skin.color.fg, fontFamily: mono)),
                  if (m.outgoing && m.delivery != null)
                    Row(
                      children: <Widget>[
                        DeliveryStatusIcon(m.delivery!),
                      ],
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

/// R58 — per-peer DM speech tri-state, in the DM header.
///
/// The icon reports **effective** audibility (`peerSpeaks`), not the
/// stored mode, so a peer set to `always` while the audio master is
/// muted reads as silent — which it is. The menu still shows which
/// mode is chosen, so the two facts stay separable.
class _SpeechMenu extends StatelessWidget {
  const _SpeechMenu({
    required this.tts,
    required this.peerPubKeyHex,
    required this.l,
  });

  final TtsController tts;
  final String peerPubKeyHex;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final PeerSpeechMode mode = tts.peerSpeechMode(peerPubKeyHex);
    final bool audible = tts.peerSpeaks(peerPubKeyHex);
    final bool mastered = mode != PeerSpeechMode.never && !tts.speechAudible;
    // A choice of three, so it is the app's picker rather than a menu: the
    // same rule the map's basemap list follows. The menu had no tick on the
    // current mode and no group name, and a popup cannot say either.
    return IconButton(
      tooltip: mastered ? l.dmSpeechMutedByMaster : l.dmSpeech,
      icon: Icon(
        audible ? Icons.record_voice_over : Icons.voice_over_off,
        color: mastered ? Theme.of(context).colorScheme.error : null,
      ),
      onPressed: () async {
        final PeerSpeechMode? picked = await showMmPicker<PeerSpeechMode>(
          context: context,
          title: l.dmSpeech,
          current: mode,
          items: <MmPickerItem<PeerSpeechMode>>[
            MmPickerItem<PeerSpeechMode>.option(
                PeerSpeechMode.inherit, l.dmSpeechInherit),
            MmPickerItem<PeerSpeechMode>.option(
                PeerSpeechMode.always, l.dmSpeechAlways),
            MmPickerItem<PeerSpeechMode>.option(
                PeerSpeechMode.never, l.dmSpeechNever),
          ],
        );
        if (picked == null) return;
        tts.setPeerSpeechMode(peerPubKeyHex, picked);
      },
    );
  }
}
