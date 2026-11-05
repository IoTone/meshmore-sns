// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../chat/channel_read_store.dart';
import '../chat/chat_actions.dart';
import '../chat/composer_budget.dart';
import '../chat/draft_store.dart';
import '../chat/report_flow.dart';
import '../chat/studio_message_row.dart';
import '../gen/app_localizations.dart';
import '../media/media_codec.dart';
import '../media/media_composer.dart';
import '../media/media_transfer.dart';
import '../meshcore/airtime.dart';
import '../meshcore/block_filter.dart';
import '../meshcore/block_store.dart';
import '../meshcore/chat_message.dart';
import '../places/place.dart';
import '../places/place_echo.dart';
import '../places/place_store.dart';
import 'delivery_status_icon.dart';
import '../meshcore/meshcore_controller.dart';
import '../chat/history_retention_notice.dart';
import '../chat/unread_counts.dart';
import '../notifications/notification_focus.dart';
import '../meshcore/message_heat.dart' show parseChannelSenderName;
import '../bot/bot_guards.dart';
import '../bot/bot_tag.dart';
import '../theme/mm_skin.dart';
import '../theme/mm_tokens.dart';
import '../tts/tts_controller.dart';
import '../ui/mm_page_header.dart';
import '../ui/mm_scaffold.dart';
import '../util/clock_model.dart';
import '../ui/mm_shape.dart';
import 'package:meshcore/meshcore.dart';

/// R6 — the channel chat. A channel-selector chip strip on top
/// (collapsible to reclaim vertical space), a scrollable message list
/// for the active channel, a composer, and a per-channel TTS toggle in
/// the header (R5; only meaningful while the global switch is on).
///
/// Lives inside [HomeShell]'s `PageView` (the shell owns the AppBar),
/// so this is a plain [Column], not a [Scaffold].
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, this.isCurrent});

  /// True when this tab is the one on screen. Null means "assume current",
  /// which is what a widget test that builds the screen alone wants and what
  /// the shell overrides with its own index.
  final bool? isCurrent;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with AutomaticKeepAliveClientMixin<ChatScreen> {
  // Keep state alive across PageView swipes — first build pays the
  // construction cost; returning to this tab is then near-free.
  @override
  bool get wantKeepAlive => true;

  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  int _lastCount = 0;

  /// APP-D1/D2 — the composer's byte budget, recomputed when the radio or its
  /// advertised name changes (the name is part of what the radio sends).
  ComposerBudget _budget = ComposerBudget.forSender(null);
  String _budgetName = '<unknown>';

  /// APP-E7 — the conversation this composer is drafting into, and the pending
  /// write. A null key means the radio or the channel is not known yet.
  String? _draftKey;
  Timer? _draftTimer;
  bool _nearWarned = false;

  /// The media path for this tab: one codec, one estimate, one receiver.
  /// Built once so a photo send does not reload the native library per tap.
  final MediaTransferService _media = MediaTransferService(
    codec: const AvifMediaCodec(),
    estimator: const AirtimeEstimator(),
    clock: DateTime.now,
  );

  /// The message the last send created, so a failure can put the text back.
  String? _sentId;
  String _sentText = '';

  /// R29 — number of new messages that have arrived while the user
  /// has scrolled away from the bottom. Drives the "↓ N new" pill.
  /// Resets whenever the user returns to the bottom (manually or via
  /// the pill).
  int _unreadSinceScrollAway = 0;

  /// Cached "is the scroll near the bottom?" so the build can decide
  /// pill visibility + auto-scroll behaviour without re-querying
  /// `position` (which throws when there are no clients).
  bool _atBottom = true;

  /// APP-E6 — the row a search hit asked for. It is tinted until the reader
  /// scrolls or switches channel, and the key is what lets the list find it
  /// after the jump.
  String? _highlightId;
  final GlobalKey _highlightKey = GlobalKey();
  int _revealTries = 0;
  Timer? _highlightTimer;

  /// The message count this screen last marked read, so a rebuild does not
  /// write the same mark again and a new message does write a new one.
  int _markedCount = -1;
  BlockFilter? _fallbackFilter;

  /// Vertical slack in pixels — within this we treat the user as
  /// "at the bottom" and keep auto-following. Generous enough to
  /// survive a single new-message row appending below them without
  /// flipping state.
  static const double _bottomSlackPx = 64.0;

  @override
  void initState() {
    super.initState();
    // Channel speech is *not* subscribed here. It lives in `CueBridge`,
    // which is app-scoped, so a channel speaks whether or not you are
    // looking at it — see the note there. This screen still owns the
    // per-channel mute toggle in its header; only the playback moved.

    // R29 — track scroll position so we know whether to follow the
    // newest message automatically or surface a jump-to-newest pill.
    _scroll.addListener(_onScroll);

    // D8.20 — the channel on screen is not announced. The active slot can
    // change without this widget rebuilding into a new state, so follow the
    // controller rather than reading the index once.
    final MeshcoreController mc = context.read<MeshcoreController>();
    _focusOwner = mc;
    // Resolved once: `dispose` must not look up an ancestor, and the focus
    // record outlives this screen's element by no more than this reference.
    _focus = context.read<NotificationFocus?>();
    void listener() {
      if (!mounted) return;
      // The cached record, not an ancestor lookup: the controller can notify
      // while this element is being deactivated, where a lookup is illegal.
      _focus?.openChannel = mc.activeChannel;
      _syncBudget(mc);
      _syncDraftScope(mc);
      _restoreIfFailed(mc);
    }

    _focusListener = listener;
    // A harness that builds this screen without the app-scoped focus record
    // simply has nothing to suppress.
    _focus?.openChannel = mc.activeChannel;
    mc.addListener(listener);
    _input.addListener(_onComposerChanged);
    _syncBudget(mc);
    _syncDraftScope(mc);
  }

  /// R109-composer — the counter and the refusal read one model, so they cannot
  /// disagree about whether a message fits.
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

  /// APP-E7 — keep one draft per conversation. Moving to another channel (or
  /// another radio) flushes what was typed and recalls what belongs there.
  void _syncDraftScope(MeshcoreController mc) {
    final String key = DraftStore.keyFor(
      DraftStore.radioScope(mc.selfInfo?.publicKey),
      channelIdx: mc.activeChannel,
    );
    if (key == _draftKey) return;
    final String? previous = _draftKey;
    final String typed = _input.text;
    _draftKey = key;
    _draftTimer?.cancel();
    _draftTimer = null;
    if (previous != null) unawaited(DraftStore.save(previous, typed));
    unawaited(_recall(key));
  }

  Future<void> _recall(String key) async {
    final String draft = await DraftStore.read(key);
    if (!mounted || key != _draftKey || draft.isEmpty) return;
    if (_input.text.isNotEmpty) return;
    setState(() => _input.text = draft);
    _input.selection = TextSelection.collapsed(offset: draft.length);
  }

  /// APP-E7 — a keystroke is not a write. One per pause, keyed to the draft it
  /// belongs to, so a channel switch mid-typing cannot land in the new thread.
  void _onComposerChanged() {
    final String? key = _draftKey;
    if (key == null) return;
    final String text = _input.text;
    _draftTimer?.cancel();
    _draftTimer = Timer(DraftStore.debounce, () {
      unawaited(DraftStore.save(key, text));
    });
    if (text.trim().isEmpty) _nearWarned = false;
    if (!_nearWarned && _budget.stateFor(text) == ComposerState.near) {
      _nearWarned = true;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
            content: Text(AppLocalizations.of(context).chatBudgetNear)),
      );
    }
    setState(() {});
  }

  /// A send that fails gives the text back: the composer keeps what the user
  /// typed instead of clearing it into a red row they have to retype.
  void _restoreIfFailed(MeshcoreController mc) {
    final String? id = _sentId;
    if (id == null || _sentText.isEmpty) return;
    ChatMessage? found;
    for (final ChatMessage m in mc.messagesFor(mc.activeChannel)) {
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

  MeshcoreController? _focusOwner;
  VoidCallback? _focusListener;
  NotificationFocus? _focus;

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final double maxExtent = _scroll.position.maxScrollExtent;
    final double pixels = _scroll.position.pixels;
    // "At bottom" with slack — survives a single new-row append
    // without flipping state. Empty / short lists report
    // maxScrollExtent==0 and pixels==0, also "at bottom".
    final bool nowAtBottom = (maxExtent - pixels) <= _bottomSlackPx;
    if (nowAtBottom == _atBottom) return;
    setState(() {
      _atBottom = nowAtBottom;
      if (nowAtBottom) _unreadSinceScrollAway = 0;
    });
  }

  void _jumpToNewest() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
    // _onScroll will null out the counter once we settle at bottom,
    // but flip the state synchronously so the pill disappears on tap
    // instead of after the animation.
    setState(() {
      _unreadSinceScrollAway = 0;
      _atBottom = true;
    });
  }

  /// APP-E6 — a hit opens the thread it came from.
  ///
  /// A direct message lives in its own route, so the hit pushes it; a channel
  /// row switches to that channel and reveals the row in place.
  Future<void> _openSearch(MeshcoreController mc) async {
    final String? id = await context.push<String>('/chat/search');
    if (id == null || !mounted) return;
    ChatMessage? target;
    for (final MapEntry<int, String> ch in mc.channels) {
      for (final ChatMessage m in mc.messagesFor(ch.key)) {
        if (m.id == id) {
          target = m;
          break;
        }
      }
      if (target != null) break;
    }
    if (target == null) return;
    final String? peer = target.peerPubKeyHex;
    if (peer != null && peer.isNotEmpty) {
      await context.push('/dm/$peer');
      return;
    }
    mc.setActiveChannel(target.channelIdx);
    _highlightTimer?.cancel();
    setState(() {
      _highlightId = id;
      _revealTries = 0;
    });
    _scrollToHighlight(mc);
    _highlightTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      setState(() => _highlightId = null);
    });
  }

  /// Brings the highlighted row into view.
  ///
  /// A `ListView.builder` only builds what is near the viewport, so a row far
  /// up the thread has no context to scroll to. The estimate jumps to where
  /// the row should be; once it is built, `ensureVisible` finishes the job.
  /// Bounded, because a row that was evicted by the cap has no position at all.
  void _scrollToHighlight(MeshcoreController mc) {
    if (!mounted) return;
    final String? id = _highlightId;
    if (id == null) return;
    final List<ChatMessage> msgs = mc.messagesFor(mc.activeChannel);
    final int idx = msgs.indexWhere((ChatMessage m) => m.id == id);
    if (idx < 0) return;
    final BuildContext? target = _highlightKey.currentContext;
    if (target != null) {
      Scrollable.ensureVisible(
        target,
        alignment: 0.4,
        duration: const Duration(milliseconds: 220),
      );
      return;
    }
    if (_revealTries >= 4 || !_scroll.hasClients) return;
    _revealTries++;
    final double extent = _scroll.position.maxScrollExtent;
    final double frac = msgs.length <= 1 ? 0 : idx / (msgs.length - 1);
    _scroll.jumpTo((extent * frac).clamp(0.0, extent));
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _scrollToHighlight(mc));
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    if (_focusListener != null) _focusOwner?.removeListener(_focusListener!);
    _focus?.openChannel = null;
    _scroll.removeListener(_onScroll);
    _input.removeListener(_onComposerChanged);
    _draftTimer?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send(MeshcoreController mc) {
    final String t = _input.text;
    if (t.trim().isEmpty) return;
    final ComposerBudget budget = _budget;
    if (!budget.canSend(t)) {
      final AppLocalizations l = AppLocalizations.of(context);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(l.chatBudgetTooLong(budget.overBy(t)))),
      );
      return;
    }
    final String? key = _draftKey;
    // The draft is cleared only when the radio has taken the text; a failure
    // puts it back through `_restoreIfFailed`.
    if (key != null) {
      _draftTimer?.cancel();
      unawaited(DraftStore.clear(key));
    }
    _sentText = t;
    _sentId = null;
    unawaited(mc.sendChannelTextTo(mc.activeChannel, t).then(
      (ChatMessage? m) {
        if (m != null) _sentId = m.id;
      },
    ));
    _input.clear();
    _nearWarned = false;
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
          threadName: mc.activeChannelName,
          senderDisplayName: parseChannelSenderName(m.text),
        );
        break;
      case ChatAction.delete:
        if (!mounted) return;
        final bool ok = await confirmDeleteMessage(context, m);
        if (ok) mc.deleteMessageById(m.id);
        break;
    }
  }

  /// R29 — only auto-follow new messages while the user IS at the
  /// bottom. If they've scrolled up to read history, count the new
  /// arrival(s) into [_unreadSinceScrollAway] instead so the
  /// jump-to-newest pill can offer them an explicit re-sync. The
  /// pre-R29 behaviour of yanking the viewport on every new row was
  /// hostile to anyone trying to scroll back.
  void _autoScroll(int count) {
    if (count == _lastCount) return;
    final int delta = count - _lastCount;
    _lastCount = count;
    if (_atBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    } else if (delta > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _unreadSinceScrollAway += delta);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // for AutomaticKeepAliveClientMixin

    // Selectorised subscriptions — only rebuild this screen when one
    // of these specific slices changes. Avoids per-advert / per-
    // battery-sample / per-drain rebuilds that the previous
    // `context.watch<MeshcoreController>()` would cause.
    final bool ready = context.select<MeshcoreController, bool>(
        (MeshcoreController mc) =>
            mc.state == MeshcoreConnectionState.ready);
    final int active = context.select<MeshcoreController, int>(
        (MeshcoreController mc) => mc.activeChannel);
    final String activeName = context.select<MeshcoreController, String>(
        (MeshcoreController mc) => mc.activeChannelName);
    final List<MapEntry<int, String>> channels =
        context.select<MeshcoreController, List<MapEntry<int, String>>>(
            (MeshcoreController mc) => mc.channels);
    final List<ChatMessage> msgs =
        context.select<MeshcoreController, List<ChatMessage>>(
            (MeshcoreController mc) => mc.messagesFor(active));
    // Delivery glyphs change inside the same message objects, which the
    // list selector above cannot see (it deep-compares identical
    // elements); this counter is what repaints them.
    context.select<MeshcoreController, int>(
        (MeshcoreController mc) => mc.deliveryRevision);
    final bool ttsEnabled = context.select<TtsController, bool>(
        (TtsController t) => t.enabled);
    final bool muted = context.select<TtsController, bool>(
        (TtsController t) => t.isChannelMuted(active));
    final bool speaks = context.select<TtsController, bool>(
        (TtsController t) => t.channelSpeaks(active));
    // Rows this thread has lost to the 250-row cap, said out loud.
    final int dropped = context.select<MeshcoreController, int>(
        (MeshcoreController mc) => mc.droppedForChannel(active));

    // Read (no listen) for action callbacks + values we deliberately
    // didn't list above (channel name + chip list are derived from
    // cached state, so they update via the slices we *do* watch).
    final MeshcoreController mc = context.read<MeshcoreController>();
    final ColorScheme cs = Theme.of(context).colorScheme;
    _autoScroll(msgs.length);
    final AppLocalizations l = AppLocalizations.of(context);

    // Channel unread (register §2: only DM unread existed). The badge is
    // per channel and skips blocked rows, and the mark moves only while this
    // tab is the one on screen and the reader is at the bottom of the thread.
    final ChannelReadStore? reads = context.watch<ChannelReadStore?>();
    final BlockStore? blocks = context.watch<BlockStore?>();
    final BlockFilter filter = blocks == null
        ? (_fallbackFilter ??= BlockFilter(BlockStore()))
        : BlockFilter(blocks);
    // A badge is about a channel this screen is not showing, so the build has
    // to notice a message arriving anywhere. The total count is the cheapest
    // value that moves when it does; a per-channel map would compare by
    // identity and rebuild on every unrelated notification.
    final int allMessages = context.select<MeshcoreController, int>(
      (MeshcoreController c) {
        int n = 0;
        for (final MapEntry<int, String> ch in c.channels) {
          n += c.messagesFor(ch.key).length;
        }
        return n;
      },
    );
    final Map<int, int> unread = allMessages == 0
        ? const <int, int>{}
        : UnreadCounts.perChannel(
            channels: channels.map((MapEntry<int, String> e) => e.key),
            history: mc.messagesFor,
            reads: reads,
            filter: filter,
          );
    if (reads != null &&
        (widget.isCurrent ?? true) &&
        _atBottom &&
        msgs.isNotEmpty &&
        _markedCount != msgs.length) {
      _markedCount = msgs.length;
      final int channel = active;
      final ChatMessage newest = msgs.last;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(reads.markRead(channel,
            at: newest.at.add(const Duration(milliseconds: 1))));
      });
    }

    return MmScaffold(
      child: Column(
      children: <Widget>[
        MmPageHeader(title: l.tabChat),
        // R91 — one row, one job: switch channel. The caption above it
        // said "CHANNEL · PUBLIC" while the selected chip two lines below
        // already said "Public", and the collapse chevron existed only to
        // hide the strip under it. Header + strip was 108 dp for that.
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            children: <Widget>[
              for (final MapEntry<int, String> ch in channels)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Semantics(
                    label: (unread[ch.key] ?? 0) > 0
                        ? '${ch.value}, ${l.chatUnread(unread[ch.key]!)}'
                        : ch.value,
                    selected: ch.key == active,
                    button: true,
                    excludeSemantics: true,
                    child: ChoiceChip(
                      label: Text(ch.value),
                      selected: ch.key == active,
                      avatar: (unread[ch.key] ?? 0) > 0
                          ? _UnreadBadge(
                              key: ValueKey<String>('unread-${ch.key}'),
                              count: unread[ch.key]!,
                              onSelectedColor: ch.key == active,
                            )
                          : null,
                      labelStyle: TextStyle(
                        color: ch.key == active
                            ? cs.onPrimary
                            : cs.onSurface,
                        fontWeight: ch.key == active
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                      onSelected: (_) => mc.setActiveChannel(ch.key),
                    ),
                  ),
                ),
              // APP-E6 — search sits at the end of the strip, where the
              // strip's own subject (which channel) is already decided.
              if (msgs.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: IconButton(
                    key: const ValueKey<String>('chat-search'),
                    tooltip: l.chatSearchAction,
                    onPressed: () => _openSearch(mc),
                    icon: const Icon(Icons.search),
                  ),
                ),
              // Manage channels: a chip, not a "#" icon next to the
              // channel chips, where two different meanings of "channel"
              // sat side by side.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ActionChip(
                  avatar: const Icon(Icons.add, size: 16),
                  label: Text(l.chatManageChannels),
                  onPressed: () => context.push('/settings/channels'),
                ),
              ),
              // Per-channel speech, at the end of the strip because it is
              // a property of the channel that is selected there.
              if (ttsEnabled)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: IconButton(
                    tooltip: muted ? l.chatTtsMuted : l.chatTtsActive,
                    onPressed: () => context
                        .read<TtsController>()
                        .toggleChannelMute(active),
                    icon: Icon(
                      speaks ? Icons.volume_up : Icons.volume_off,
                      color: speaks ? cs.primary : cs.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        HistoryRetentionNotice(dropped: dropped),

        // Message list (active channel) + R29 jump-to-newest pill.
        Expanded(
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: msgs.isEmpty
                    ? Center(
                        child: Text(l.chatEmpty,
                            style: TextStyle(
                                color: cs.onSurfaceVariant)),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        itemCount: msgs.length,
                        itemBuilder: (BuildContext ctx, int i) {
                          final bool lit = msgs[i].id == _highlightId;
                          final Widget row = _MessageRow(
                            msgs[i],
                            key: lit ? _highlightKey : null,
                            onAction: () => _onAction(mc, msgs[i]),
                            // The DR Pop name tag shows the cadence since
                            // this identity last spoke; only that mode reads
                            // it, so only compute it there.
                            sinceLast: _chatModeFor(ctx.skin.preset) ==
                                    _ChatMode.block
                                ? _sinceLastFromSame(msgs, i)
                                : null,
                          );
                          if (!lit) return row;
                          return ColoredBox(
                            color: cs.secondaryContainer,
                            child: row,
                          );
                        },
                      ),
              ),
              // The pill only appears when the user is NOT at the
              // bottom (so they wouldn't otherwise see the newest
              // row) AND new messages have actually arrived since
              // they scrolled away. If the user scrolls up but no
              // new messages come in, no pill — silence is correct.
              if (!_atBottom && _unreadSinceScrollAway > 0)
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: _JumpToNewestPill(
                    count: _unreadSinceScrollAway,
                    onTap: _jumpToNewest,
                    label: l.chatJumpToNewest(_unreadSinceScrollAway),
                  ),
                ),
            ],
          ),
        ),

        // Composer.
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 8, 10),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      TextField(
                        controller: _input,
                        enabled: ready,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(mc),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: ready
                              ? l.chatComposerHint(activeName)
                              : l.chatComposerOffline,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      _ComposerCounter(
                        budget: _budget,
                        text: _input.text,
                        label: l,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: const ValueKey<String>('chat-attach'),
                  tooltip: l.mediaComposerTitle,
                  onPressed: ready
                      ? () => MediaComposer.show(
                            context,
                            service: _media,
                            source: kNoMediaPhotoSource,
                            channelPsk: mc.channelPsk(mc.activeChannel),
                            byteBudget: kMediaPhotoBudgetBytes,
                            sendBlob: (Uint8List blob) => mc.sendChannelData(
                              channelIdx: mc.activeChannel,
                              dataType: kChannelDataTypeDev,
                              blob: blob,
                            ),
                          )
                      : null,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                ),
                IconButton(
                  tooltip: l.chatSend,
                  onPressed: ready ? () => _send(mc) : null,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ),
      ],
      ),
    );
  }
}

/// How a theme renders chat: a terminal **log** (SEELE / NERV / Recon
/// codec), chat **bubbles** (Hyperlocal / AG-HUD), or flat saturated
/// **blocks** (DR Pop). Per the UX brief's per-concept chat treatment.
enum _ChatMode { log, bubble, block }

_ChatMode _chatModeFor(MmThemePreset p) => switch (p) {
      MmThemePreset.hyperlocal || MmThemePreset.agHud => _ChatMode.bubble,
      MmThemePreset.drPop => _ChatMode.block,
      _ => _ChatMode.log, // seele, nerv, recon — terminal log
    };

class _MessageRow extends StatelessWidget {
  const _MessageRow(this.m,
      {super.key, required this.onAction, this.sinceLast});
  final ChatMessage m;
  final VoidCallback onAction;

  /// Time since the same identity last spoke on this channel (DR Pop name
  /// tag). Null = first message from them this session, or not block mode.
  final Duration? sinceLast;

  /// APP-N3 — a stamp the reader can trust: the sender's own `HH:MM` when
  /// that clock agrees with this phone, and a named marker when it does not
  /// (a sender running fast used to print a time in the future).
  String _time(AppLocalizations l) => clockStamp(l, m.at);

  List<String> get _meta => <String>[
        if (m.isFlood) 'flood',
        if (m.snrDb != null) 'SNR ${m.snrDb!.toStringAsFixed(1)}',
      ];

  /// Sender handle + body for incoming channel messages (`name: text`);
  /// our own outgoing messages carry no prefix.
  ({String? sender, String body}) _split() {
    if (m.outgoing) return (sender: null, body: m.text);
    final String? s = parseChannelSenderName(m.text);
    if (s == null) return (sender: null, body: m.text);
    final int i = m.text.indexOf(': ');
    return (sender: s, body: i >= 0 ? m.text.substring(i + 2) : m.text);
  }

  @override
  Widget build(BuildContext context) {
    final MmSkin skin = context.skin;
    return switch (_chatModeFor(skin.preset)) {
      _ChatMode.log => _log(context, skin),
      _ChatMode.bubble => _bubble(context, skin),
      _ChatMode.block => _block(context, skin),
    };
  }

  // --- terminal log (SEELE / NERV / Recon) ---------------------------
  Widget _log(BuildContext context, MmSkin skin) {
    final AppLocalizations l = AppLocalizations.of(context);
    // R71: Studio sets words sans, machine data mono (see
    // StudioMessageRow); the terminal presets keep the all-mono log.
    if (skin.type.sansLabels) {
      final ({String? sender, String body}) s = _split();
      final Place? place = PlaceEchoLine.placeOf(m);
      return StudioMessageRow(
          message: m,
          body: s.body,
          sender: s.sender,
          extraMeta: _meta,
          echo: place == null
              ? null
              : PlaceEchoLine(place: place, store: context.read<PlaceStore>()),
          onAction: onAction);
    }
    final String mono = skin.type.monoFamily;
    final List<String> meta = _meta;
    return InkWell(
      onLongPress: onAction,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // R102 — scale the gutter with the text (see StudioMessageRow).
            SizedBox(
              width: 56 * MediaQuery.textScalerOf(context).scale(1),
              child: Text('${_time(l)} ${m.outgoing ? '»' : '«'}',
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                      color: m.outgoing
                          ? skin.color.accent
                          : skin.color.fgMuted,
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
                      style:
                          TextStyle(color: skin.color.fg, fontFamily: mono)),
                  if (PlaceEchoLine.placeOf(m) case final Place place)
                    PlaceEchoLine(
                        place: place, store: context.read<PlaceStore>()),
                  _metaRow(skin, meta, mono),
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

  // --- chat bubbles (Hyperlocal / AG-HUD) ----------------------------
  Widget _bubble(BuildContext context, MmSkin skin) {
    final ({String? sender, String body}) s = _split();
    final Color fill = m.outgoing
        ? skin.color.accent.withValues(alpha: 0.16)
        : skin.color.surface;
    return _aligned(
      context: context,
      skin: skin,
      decoration: ShapeDecoration(
        color: fill,
        shape: mmShapeBorder(skin.shape,
            side: BorderSide(
                color: skin.color.line, width: skin.shape.borderWidth)),
      ),
      sender: s.sender,
      senderColor: skin.color.accent,
      body: s.body,
      bodyColor: skin.color.fg,
      bodyFamily: skin.type.bodyFamily,
      metaColor: skin.color.fgMuted,
    );
  }

  // --- saturated colour fields + name tags (DR Pop, Mondrian) --------
  // Each message is a flat colour field bordered like a Mondrian panel.
  // Incoming fields take the *name's* stable neon colour; in the free
  // space beside the field sits a name tag — a Space-Invader sprite
  // (unique per name, stable for the session) plus the cadence since that
  // name last spoke.
  Widget _block(BuildContext context, MmSkin skin) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ({String? sender, String body}) s = _split();
    final Color base = skin.color.base;
    final String idKey = _identityKey(m);
    // A name is always the same colour for the life of the session
    // (deterministic from the handle); our own messages stay accent.
    final Color fill = m.outgoing
        ? skin.color.accent
        : _mondrianColorFor(idKey.isEmpty ? s.body : idKey);
    final Color ink = fill.computeLuminance() > 0.45 ? base : skin.color.fg;
    final List<String> meta = _meta;

    final Widget field = Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      // Mondrian black rule around every colour field.
      decoration: BoxDecoration(
          color: fill, border: Border.all(color: base, width: 3)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (s.sender != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(s.sender!.toUpperCase(),
                  style: TextStyle(
                      color: ink.withValues(alpha: 0.85),
                      fontSize: 11,
                      letterSpacing: 1,
                      fontWeight: FontWeight.w800)),
            ),
          // The sender prefix is split off first, so the marker sits at
          // the head of the BODY here, not of the raw text.
          if (looksLikeBot(s.body))
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: BotTag(color: ink),
            ),
          Text(stripBotMarker(s.body),
              style: TextStyle(
                  color: ink,
                  fontFamily: skin.type.bodyFamily,
                  fontWeight: FontWeight.w600,
                  height: 1.3)),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (m.outgoing && m.delivery != null) ...<Widget>[
                DeliveryStatusIcon(m.delivery!),
                const SizedBox(width: 5),
              ],
              Text(<String>[_time(l), ...meta].join(' · '),
                  style: TextStyle(
                      color: ink.withValues(alpha: 0.65), fontSize: 10)),
            ],
          ),
        ],
      ),
    );

    final Widget? tag = idKey.isEmpty
        ? null
        : _NameTag(
            seedKey: idKey,
            color: fill,
            base: base,
            mono: skin.type.monoFamily,
            since: sinceLast == null
                ? null
                : _compactSince(AppLocalizations.of(context), sinceLast!),
          );

    final List<Widget> cells = <Widget>[
      Flexible(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.6),
          child: field,
        ),
      ),
      if (tag != null) ...<Widget>[const SizedBox(width: 6), tag],
    ];

    return InkWell(
      onLongPress: onAction,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          // Incoming hugs the left (tag in the right free space); our own
          // messages hug the right (tag in the left free space).
          mainAxisAlignment:
              m.outgoing ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: m.outgoing ? cells.reversed.toList() : cells,
        ),
      ),
    );
  }

  /// Shared bubble/block scaffold: left/right aligned, optional sender
  /// header, body, and the meta/delivery footer.
  Widget _aligned({
    required BuildContext context,
    required MmSkin skin,
    required Decoration decoration,
    required String? sender,
    required Color senderColor,
    required String body,
    required Color bodyColor,
    String? bodyFamily,
    FontWeight? bodyWeight,
    required Color metaColor,
  }) {
    final List<String> meta = _meta;
    final AppLocalizations l = AppLocalizations.of(context);
    return Align(
      alignment: m.outgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78),
        child: InkWell(
          onLongPress: onAction,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            decoration: decoration,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (sender != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(sender,
                        style: TextStyle(
                            color: senderColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                  ),
                Text(body,
                    style: TextStyle(
                        color: bodyColor,
                        fontFamily: bodyFamily,
                        fontWeight: bodyWeight,
                        height: 1.3)),
                if (PlaceEchoLine.placeOf(m) case final Place place)
                  PlaceEchoLine(
                      place: place, store: context.read<PlaceStore>()),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (m.outgoing && m.delivery != null) ...<Widget>[
                      DeliveryStatusIcon(m.delivery!),
                      const SizedBox(width: 5),
                    ],
                    Text(
                        <String>[_time(l), ...meta].join(' · '),
                        style: TextStyle(color: metaColor, fontSize: 10)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _metaRow(MmSkin skin, List<String> meta, String mono) {
    if (meta.isEmpty && !(m.outgoing && m.delivery != null)) {
      return const SizedBox.shrink();
    }
    return Row(
      children: <Widget>[
        if (m.outgoing && m.delivery != null) ...<Widget>[
          DeliveryStatusIcon(m.delivery!),
          const SizedBox(width: 5),
        ],
        if (meta.isNotEmpty)
          Text(meta.join(' · '),
              style: TextStyle(color: skin.color.fgMuted, fontSize: 11)),
      ],
    );
  }
}

// ---- DR Pop name tags (Mondrian block mode) -------------------------------

/// The identity a message is attributed to for the session: an incoming
/// channel sender's handle, or a sentinel for our own outgoing messages.
/// Empty = anonymous (no parseable `name:` prefix) → no tag.
///
/// The sentinel is NUL-prefixed so it can never collide with a real
/// handle. It MUST be written as the six-character escape below, not
/// as a literal NUL byte: a raw NUL makes the whole file read as
/// binary, and grep / ripgrep then skip it silently rather than
/// reporting an error -- searches come back empty instead of failing.
String _identityKey(ChatMessage m) =>
    m.outgoing ? '\u0000self' : (parseChannelSenderName(m.text) ?? '');

/// Time since the same identity last spoke before message [i] in [msgs]
/// (chronological). Null = first time we've heard this identity in-buffer.
Duration? _sinceLastFromSame(List<ChatMessage> msgs, int i) {
  final String key = _identityKey(msgs[i]);
  if (key.isEmpty) return null;
  for (int j = i - 1; j >= 0; j--) {
    if (_identityKey(msgs[j]) == key) {
      return msgs[i].at.difference(msgs[j].at);
    }
  }
  return null;
}

/// Stable 32-bit FNV-1a hash — gives each handle a deterministic colour +
/// sprite that's identical for the life of the session (and beyond), with
/// no per-session registry to maintain.
int _fnv1a(String s) {
  int h = 0x811c9dc5;
  for (final int u in s.codeUnits) {
    h = (h ^ u) & 0xffffffff;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h;
}

/// Mondrian-ish bold neon fields for DR Pop, picked deterministically per
/// identity so a name keeps its colour all session.
const List<Color> _mondrianPalette = <Color>[
  Color(0xFFFF2E88), // magenta
  Color(0xFF00C2FF), // cyan
  Color(0xFFD7FF00), // acid
  Color(0xFFFF6B2E), // orange
  Color(0xFF9B4DFF), // violet
  Color(0xFF2E7DEF), // blue
  Color(0xFFFFC400), // yellow
];

Color _mondrianColorFor(String key) =>
    _mondrianPalette[_fnv1a(key) % _mondrianPalette.length];

/// Compact "since they last spoke" — `now` / `5m` / `2h` / `3d`.
String _compactSince(AppLocalizations l, Duration d) {
  if (d.inSeconds < 60) return l.chatSinceNow;
  if (d.inMinutes < 60) return l.chatSinceMinutes(d.inMinutes);
  if (d.inHours < 24) return l.chatSinceHours(d.inHours);
  return l.chatSinceDays(d.inDays);
}

/// The free-space tag beside a DR Pop message: a Space-Invader sprite that's
/// unique to the identity, plus the cadence since they last spoke.
class _NameTag extends StatelessWidget {
  const _NameTag({
    required this.seedKey,
    required this.color,
    required this.base,
    required this.mono,
    this.since,
  });

  final String seedKey;
  final Color color;
  final Color base;
  final String mono;
  final String? since;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 58,
      padding: const EdgeInsets.all(5),
      decoration:
          BoxDecoration(color: base, border: Border.all(color: color, width: 3)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            width: 36,
            height: 36,
            child: CustomPaint(
              painter:
                  _InvaderPainter(seed: _fnv1a(seedKey), color: color, bg: base),
            ),
          ),
          if (since != null) ...<Widget>[
            const SizedBox(height: 3),
            Text(since!,
                maxLines: 1,
                style: TextStyle(
                    color: color,
                    fontFamily: mono,
                    fontSize: 10,
                    fontWeight: FontWeight.w700)),
          ],
        ],
      ),
    );
  }
}

/// A horizontally-symmetric "Space Invaders" sprite on a 5×5 grid, lit from
/// a deterministic bit stream so each seed yields a distinct little
/// creature. Mirror across the centre column gives the arcade look.
class _InvaderPainter extends CustomPainter {
  const _InvaderPainter({
    required this.seed,
    required this.color,
    required this.bg,
  });

  final int seed;
  final Color color;
  final Color bg;

  static const int _cols = 5;
  static const int _rows = 5;

  @override
  void paint(Canvas canvas, Size size) {
    final double cw = size.width / _cols;
    final double ch = size.height / _rows;
    final Paint on = Paint()..color = color;
    final int half = (_cols + 1) ~/ 2; // 3: cols 0,1 + centre col 2
    int st = seed == 0 ? 0x9e3779b9 : seed;
    int bit() {
      st = (st * 1103515245 + 12345) & 0x7fffffff; // LCG
      return (st >> 16) & 1;
    }

    for (int y = 0; y < _rows; y++) {
      for (int x = 0; x < half; x++) {
        if (bit() == 0) continue;
        canvas.drawRect(
            Rect.fromLTWH(x * cw, y * ch, cw, ch).deflate(0.6), on);
        final int mx = _cols - 1 - x; // mirror
        if (mx != x) {
          canvas.drawRect(
              Rect.fromLTWH(mx * cw, y * ch, cw, ch).deflate(0.6), on);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_InvaderPainter old) =>
      old.seed != seed || old.color != color || old.bg != bg;
}

/// R29 — overlay pill nudging the user back to the newest message.
/// Renders only when the scroll position is away from the bottom
/// AND new messages have arrived since the user scrolled away.
class _JumpToNewestPill extends StatelessWidget {
  const _JumpToNewestPill({
    required this.count,
    required this.label,
    required this.onTap,
  });
  final int count;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.primary,
      elevation: 4,
      shape: context.skin.shape.squareControls
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(kSquareRadius))
          : const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 14, 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.arrow_downward,
                  size: 16, color: cs.onPrimary),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      color: cs.onPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

/// APP-D1 — how much of the radio's text budget the composer has used.
///
/// The number is the same one `_send` refuses with, computed by
/// [ComposerBudget]. It is shown as remaining bytes rather than a ratio because
/// the limit is in bytes, not characters: a Japanese message has far fewer
/// characters than an English one at the same count. The count is text, not
/// colour, and it is a live region so a screen reader announces the change.
class _ComposerCounter extends StatelessWidget {
  const _ComposerCounter({
    required this.budget,
    required this.text,
    required this.label,
  });

  final ComposerBudget budget;
  final String text;
  final AppLocalizations label;

  @override
  Widget build(BuildContext context) {
    final ComposerState state = budget.stateFor(text);
    final MmTokens tokens = context.skin.color;
    final Color colour = switch (state) {
      ComposerState.ok => tokens.fgMuted,
      ComposerState.near => tokens.accent,
      ComposerState.over => tokens.alert,
    };
    final int remaining = budget.remainingFor(text);
    final String shown = state == ComposerState.over
        ? label.chatBudgetTooLong(budget.overBy(text))
        : budget.prefixKnown
            // Measured against the radio's whole budget, not the sender's
            // share: "152 of 160 left" is a number a person can check.
            ? label.chatBudgetRemaining(
                remaining, ChannelTextLimits.maxTextBytes)
            : label.chatBudgetEstimate(
                remaining, ChannelTextLimits.maxTextBytes);
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Semantics(
        liveRegion: true,
        label: shown,
        child: Text(
          shown,
          style: TextStyle(
            color: colour,
            fontSize: context.skin.type.sizeMicro,
          ),
        ),
      ),
    );
  }
}


/// The count a channel chip carries while it has unread messages.
///
/// A count, not a dot: the register asks for per-channel unread counts, and a
/// bare dot makes the reader open a channel to learn whether it was one
/// message or forty. The colour follows the chip's own selected state so the
/// number stays legible on both.
class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge(
      {super.key, required this.count, required this.onSelectedColor});

  final int count;
  final bool onSelectedColor;

  @override
  Widget build(BuildContext context) {
    final MmSkin skin = context.skin;
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: skin.space.step(1)),
      constraints: BoxConstraints(minWidth: skin.space.step(5)),
      decoration: BoxDecoration(
        color: onSelectedColor ? cs.onPrimary : cs.primary,
        borderRadius: BorderRadius.circular(skin.shape.cornerSize),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: skin.type.sizeMicro,
          fontWeight: FontWeight.w700,
          color: onSelectedColor ? cs.primary : cs.onPrimary,
        ),
      ),
    );
  }
}
