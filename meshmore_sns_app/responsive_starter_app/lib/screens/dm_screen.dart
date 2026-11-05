// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../chat/chat_actions.dart';
import '../chat/report_flow.dart';
import '../chat/draft_store.dart';
import '../chat/studio_message_row.dart';
import '../gen/app_localizations.dart';
import '../bot/bot_guards.dart';
import '../bot/bot_tag.dart';
import '../meshcore/chat_message.dart';
import 'delivery_status_icon.dart';
import '../meshcore/discovered_node.dart';
import '../meshcore/meshcore_controller.dart';
import '../chat/history_retention_notice.dart';
import '../notifications/notification_focus.dart';
import '../theme/mm_skin.dart';
import '../tts/tts_controller.dart';
import '../ui/mm_scaffold.dart';
import 'node_detail_sheet.dart';
import 'package:meshcore/meshcore.dart';

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
  final ScrollController _scroll = ScrollController();
  StreamSubscription<ChatMessage>? _sub;
  NotificationFocus? _focus;
  int _lastCount = 0;

  /// APP-E7 — the draft key for this thread, and its pending debounced write.
  /// A thread draft is keyed by the radio and the peer, so the same peer on a
  /// second radio is a second conversation with its own unsent text.
  String? _draftKey;
  Timer? _draftTimer;

  /// The message the last send created, so a failure can put the text back.
  String? _sentId;
  String _sentText = '';

  @override
  void initState() {
    super.initState();
    final MeshcoreController mc = context.read<MeshcoreController>();
    _draftKey = _keyFor(mc);
    _input.addListener(_onComposerChanged);
    unawaited(_recall());
    mc.addListener(_onControllerChanged);
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
    _focus?.openPeer = null;
    _sub?.cancel();
    _input.removeListener(_onComposerChanged);
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
    final String? key = _draftKey;
    if (key == null) return;
    final String text = _input.text;
    _draftTimer?.cancel();
    _draftTimer = Timer(DraftStore.debounce, () {
      unawaited(DraftStore.save(key, text));
    });
    setState(() {});
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
    final String? key = _draftKey;
    // Cleared on the send, put back by [_restoreIfFailed] if the row fails.
    if (key != null) {
      _draftTimer?.cancel();
      unawaited(DraftStore.clear(key));
    }
    _sentText = t;
    _sentId = null;
    unawaited(mc.sendDirectText(widget.peerPubKeyHex, t).then(
      (ChatMessage? m) {
        if (m != null) _sentId = m.id;
      },
    ));
    _input.clear();
  }

  Future<void> _onAction(MeshcoreController mc, ChatMessage m) async {
    final ChatAction? action = await showChatActions(context, m);
    if (action == null || !mounted) return;
    switch (action) {
      case ChatAction.reply:
        final String quote = buildReplyQuote(m);
        _input.text = quote + _input.text;
        _input.selection = TextSelection.collapsed(offset: _input.text.length);
        break;
      case ChatAction.copy:
        await copyMessageToClipboard(context, m);
        break;
      case ChatAction.retry:
        await mc.retryMessage(m.id);
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
    final ColorScheme cs = Theme.of(context).colorScheme;
    final bool ready = mc.state == MeshcoreConnectionState.ready;
    final AppLocalizations l = AppLocalizations.of(context);
    final List<ChatMessage> msgs =
        mc.dmHistoryFor(widget.peerPubKeyHex);
    _autoScroll(msgs.length);
    final String pubkeyDisplay = widget.peerPubKeyHex.length >= 12
        ? '${widget.peerPubKeyHex.substring(0, 12)}…'
        : widget.peerPubKeyHex;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.dmTitle(_peerName(mc))),
        actions: <Widget>[
          _SpeechMenu(tts: tts, peerPubKeyHex: widget.peerPubKeyHex, l: l),
          IconButton(
            tooltip: l.dmOpenPeerDetail,
            icon: const Icon(Icons.info_outline),
            onPressed: () => _openPeerDetail(mc),
          ),
        ],
      ),
      body: MmScaffold(
        child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              l.dmPubkeyLabel(pubkeyDisplay),
              style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontFamily: 'JetBrains Mono',
                  fontSize: 11),
            ),
          ),
          const Divider(height: 1),
          HistoryRetentionNotice(
              dropped: mc.droppedForPeer(widget.peerPubKeyHex)),
          Expanded(
            child: msgs.isEmpty
                ? Center(
                    child: Text(l.dmEmpty,
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
              padding: const EdgeInsets.fromLTRB(12, 6, 8, 10),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _input,
                      enabled: ready,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(mc),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: ready
                            ? l.dmComposerHint(_peerName(mc))
                            : l.chatComposerOffline,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: l.dmSend,
                    onPressed: ready ? () => _send(mc) : null,
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

class _DmRow extends StatelessWidget {
  const _DmRow(this.m, {required this.onAction});
  final ChatMessage m;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final MmSkin skin = context.skin;
    final String mono = skin.type.monoFamily;
    final String time = '${m.at.hour.toString().padLeft(2, '0')}:'
        '${m.at.minute.toString().padLeft(2, '0')}';
    final String tag = m.outgoing ? '»' : '«';
    final List<String> meta = <String>[
      if (m.snrDb != null) 'SNR ${m.snrDb!.toStringAsFixed(1)}',
      if (m.isFlood) 'flood',
    ];
    // R71: Studio = words sans, machine data mono (StudioMessageRow).
    if (skin.type.sansLabels) {
      return StudioMessageRow(
          message: m, body: m.text, extraMeta: meta, onAction: onAction);
    }
    return InkWell(
      onLongPress: onAction,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 56,
              child: Text('$time $tag',
                  style: TextStyle(
                      color:
                          m.outgoing ? skin.color.accent : skin.color.fgMuted,
                      fontFamily: mono,
                      fontSize: 12)),
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
                  if (meta.isNotEmpty || m.outgoing && m.delivery != null)
                    Row(
                      children: <Widget>[
                        if (m.outgoing && m.delivery != null) ...<Widget>[
                          DeliveryStatusIcon(m.delivery!),
                          const SizedBox(width: 5),
                        ],
                        if (meta.isNotEmpty)
                          Text(meta.join(' · '),
                              style: TextStyle(
                                  color: cs.onSurfaceVariant, fontSize: 11)),
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
              icon: Icon(Icons.more_vert,
                  color: cs.onSurfaceVariant),
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
    return PopupMenuButton<PeerSpeechMode>(
      tooltip: mastered ? l.dmSpeechMutedByMaster : l.dmSpeech,
      icon: Icon(
        audible ? Icons.record_voice_over : Icons.voice_over_off,
        color: mastered ? Theme.of(context).colorScheme.error : null,
      ),
      initialValue: mode,
      onSelected: (PeerSpeechMode m) =>
          tts.setPeerSpeechMode(peerPubKeyHex, m),
      itemBuilder: (BuildContext _) => <PopupMenuEntry<PeerSpeechMode>>[
        PopupMenuItem<PeerSpeechMode>(
          value: PeerSpeechMode.inherit,
          child: Text(l.dmSpeechInherit),
        ),
        PopupMenuItem<PeerSpeechMode>(
          value: PeerSpeechMode.always,
          child: Text(l.dmSpeechAlways),
        ),
        PopupMenuItem<PeerSpeechMode>(
          value: PeerSpeechMode.never,
          child: Text(l.dmSpeechNever),
        ),
      ],
    );
  }
}
