// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../chat/channel_read_store.dart';
import '../chat/chat_actions.dart';
import '../chat/composer_budget.dart';
import '../chat/composer_counter.dart';
import '../chat/composer_field.dart';
import '../chat/composer_offline.dart';
import '../chat/draft_store.dart';
import '../chat/report_flow.dart';
import '../chat/place_suggestion_line.dart';
import '../chat/studio_message_row.dart';
import '../chat/history_unreadable_notice.dart';
import '../chat/export_passphrase_dialog.dart';
import '../gen/app_localizations.dart';
import '../media/media_codec.dart';
import '../media/media_composer.dart';
import '../media/media_transfer.dart';
import '../voice/voice_capture.dart';
import '../voice/voice_codec.dart';
import '../voice/voice_composer.dart';
import '../voice/voice_inbox.dart';
import '../voice/voice_notes_sheet.dart';
import '../voice/voice_playback.dart';
import '../meshcore/airtime.dart';
import '../meshcore/block_filter.dart';
import '../meshcore/block_store.dart';
import '../meshcore/chat_message.dart';
import '../meshcore/history_export.dart';
import '../meshcore/secure/incoming_export.dart';
import '../meshcore/secure/store_export.dart';
import '../places/place.dart';
import '../places/place_echo.dart';
import '../places/place_store.dart';
import 'delivery_status_icon.dart';
import 'meshbook_view.dart';
import '../meshcore/meshcore_controller.dart';
import '../chat/history_retention_notice.dart';
import '../chat/unread_counts.dart';
import '../meshcore/message_heat.dart' show parseChannelSenderName;
import '../bot/bot_guards.dart';
import '../bot/bot_tag.dart';
import '../theme/mm_skin.dart';
import '../theme/mm_tokens.dart';
import '../tts/tts_controller.dart';
import '../ui/mm_components.dart';
import '../ui/mm_scaffold.dart';
import '../util/clock_model.dart';
import '../util/share.dart';
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

    // D8.20's "do not announce the thread I am reading" is the shell's
    // record, not this page's: the page is kept alive once visited, so a
    // write here would outlive the user leaving the tab.
    final MeshcoreController mc = context.read<MeshcoreController>();
    _owner = mc;
    void listener() {
      if (!mounted) return;
      _syncBudget(mc);
      _syncDraftScope(mc);
      _restoreIfFailed(mc);
    }

    _listener = listener;
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
    // The send control's enabled state is a function of the text, so every
    // keystroke rebuilds the composer — including the keystrokes typed before
    // a thread exists to save a draft into.
    setState(() {});
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
            content: Text(AppLocalizations.of(context)
                .chatBudgetNear(_budget.remainingFor(text)))),
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

  MeshcoreController? _owner;
  VoidCallback? _listener;

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
  /// One conversation as an `MMEX` passphrase file, then the share sheet.
  Future<void> _exportThread(MeshcoreController mc) async {
    final AppLocalizations l = AppLocalizations.of(context);
    final int slot = mc.activeChannel;
    final String key = HistoryExport.channelKey(slot);
    final List<ChatMessage> rows = mc
        .messagesFor(slot)
        .where((ChatMessage m) => HistoryExport.threadKeyOf(m) == key)
        .toList();
    if (rows.isEmpty) return;
    final String? passphrase = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => ExportPassphraseDialog(l: l),
    );
    if (passphrase == null || !mounted) return;
    try {
      final Uint8List bytes = HistoryExport.encodeThread(
        key: key,
        messages: rows,
        passphrase: passphrase,
      );
      // App-support, for the same reason the places ledger uses it: the
      // FileProvider roots cover `files-path` and `cache-path`, and the
      // documents directory is neither.
      final Directory dir = await getApplicationSupportDirectory();
      final File file = File('${dir.path}/thread-$slot.mmex');
      await file.writeAsBytes(bytes);
      final bool shared = await Share.file(file.path,
          mime: 'application/octet-stream', subject: l.chatExportAction);
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
          content:
              Text(shared ? l.chatExportShared : l.chatExportDone(file.path))));
    } on ExportRefused {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(l.chatExportFailed)));
    }
  }

  /// The channel's own activity report — its last 24 h, in a sheet.
  ///
  /// It used to be one entry in the grid's view picker, which is a page about
  /// where things are; a report about this channel belongs on this channel,
  /// one tap from the strip that names it.
  void _openActivity() {
    final AppLocalizations l = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext ctx) => SizedBox(
        height: MediaQuery.sizeOf(ctx).height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(l.meshbookTitle,
                  style: Theme.of(ctx).textTheme.titleMedium),
            ),
            const Expanded(child: MeshbookView()),
          ],
        ),
      ),
    );
  }

  /// Restores conversations from a passphrase export the user still holds.
  ///
  /// The export is the one recovery path once the sealed key is gone, so this
  /// is deliberately forgiving about where the file is: the platform stages a
  /// file the user opened or shared into the app, and the passphrase is asked
  /// here because it is the only secret that travels with the file.
  Future<void> _restoreFromExport(MeshcoreController mc) async {
    final AppLocalizations l = AppLocalizations.of(context);
    final String? path = await IncomingExport.take();
    if (!mounted) return;
    if (path == null) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(l.chatRestoreNothing)));
      return;
    }
    final String? passphrase = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => ExportPassphraseDialog(
        l: l,
        title: l.chatRestoreTitle,
        fieldLabel: l.chatRestorePassphrase,
        confirmLabel: l.chatRestoreConfirm,
      ),
    );
    if (passphrase == null || !mounted) return;
    try {
      final File file = File(path);
      // An export is a few hundred kilobytes; anything far larger is not one.
      if (await file.length() > 8 * 1024 * 1024) {
        throw const ExportRefused('file larger than an export');
      }
      final List<ChatMessage> rows = await HistoryExport.decodeFileAsync(
        bytes: await file.readAsBytes(),
        passphrase: passphrase,
      );
      final int added = await mc.importHistory(rows);
      await file.delete().catchError((Object _) => file);
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(l.chatRestoreDone(added))));
    } on ExportRefused {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(l.chatRestoreFailed)));
    } on FileSystemException {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(l.chatRestoreFailed)));
    }
  }

  /// Records one note on the active channel.
  ///
  /// The channel rules, the ceiling, the cost and the pacing all live in the
  /// sheet; this only hands it the app-scoped pieces and the radio call for one
  /// datagram. A build without a codec or a microphone opens the sheet anyway,
  /// because the sheet's own sentences say which one is missing.
  Future<void> _openVoice(MeshcoreController mc) async {
    final VoiceCapture? capture = context.read<VoiceCapture?>();
    final VoiceCodec? codec = context.read<VoiceCodec?>();
    if (capture == null || codec == null) return;
    await VoiceComposer.show(
      context,
      service: _media,
      capture: capture,
      codec: codec,
      channelPsk: mc.channelPsk(mc.activeChannel),
      playback: context.read<VoicePlayback?>(),
      sendBlob: (Uint8List blob) => mc.sendChannelData(
        channelIdx: mc.activeChannel,
        dataType: kChannelDataTypeDev,
        blob: blob,
      ),
    );
  }

  /// The notes this session holds for the active channel, newest first.
  Future<void> _openVoiceNotes(MeshcoreController mc) async {
    final VoiceInbox? inbox = context.read<VoiceInbox?>();
    final VoiceCodec? codec = context.read<VoiceCodec?>();
    if (inbox == null || codec == null) return;
    await VoiceNotesSheet.show(
      context,
      notes: inbox.notesFor(mc.activeChannel),
      codec: codec,
      playback: context.read<VoicePlayback?>(),
    );
  }

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToHighlight(mc));
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    if (_listener != null) _owner?.removeListener(_listener!);
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
      case ChatAction.replyMention:
        // The MeshCore reply: address the person. `@[Name] ` is the form the
        // ecosystem reads as a reply, so another client shows this as an
        // answer to that sender rather than as prose that starts oddly.
        final String prefix =
            mentionPrefixFor(parseChannelSenderName(m.text)) ?? '';
        _input.text = prefix + _input.text;
        _input.selection = TextSelection.collapsed(offset: _input.text.length);
        break;
      case ChatAction.quote:
        final String quote = buildReplyQuote(m);
        _input.text = quote + _input.text;
        _input.selection = TextSelection.collapsed(offset: _input.text.length);
        break;
      case ChatAction.copy:
        await copyMessageToClipboard(context, m);
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
        (MeshcoreController mc) => mc.state == MeshcoreConnectionState.ready);
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
    final bool ttsEnabled =
        context.select<TtsController, bool>((TtsController t) => t.enabled);
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
    // Voice notes the session holds for this channel: the strip's badge and the
    // sheet read the one store, so they cannot disagree about what is there.
    final VoiceInbox? voiceInbox = context.watch<VoiceInbox?>();
    final int voiceNotes = voiceInbox?.countFor(active) ?? 0;
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
                      // The label ink comes from MmChoiceChip rather than
                      // from a local pair: one chip naming its own colours is
                      // how the places sheet ended up with a light label on a
                      // light fill.
                      child: MmChoiceChip(
                        label: Text(ch.value),
                        selected: ch.key == active,
                        avatar: (unread[ch.key] ?? 0) > 0
                            ? _UnreadBadge(
                                key: ValueKey<String>('unread-${ch.key}'),
                                count: unread[ch.key]!,
                                onSelectedColor: ch.key == active,
                              )
                            : null,
                        onSelected: (_) => mc.setActiveChannel(ch.key),
                      ),
                    ),
                  ),
                // One overflow for everything that is not a channel. The
                // strip answers "which channel", so search, export and manage
                // live behind one control at its end instead of competing with
                // the channel names (and instead of appearing only when a
                // thread happens to have rows).
                // The channel activity report is about the channel that is
                // selected here, and it is the one thing in the strip people
                // open for fun. A `more_vert` menu is where actions hide, so
                // it gets its own control beside the strip's overflow rather
                // than a fifth row inside it.
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: IconButton(
                    key: const ValueKey<String>('chat-activity-visible'),
                    tooltip: l.meshbookTitle,
                    onPressed: _openActivity,
                    icon: const Icon(Icons.insights),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: PopupMenuButton<String>(
                    key: const ValueKey<String>('chat-overflow'),
                    tooltip: l.chatMoreActions,
                    icon: const Icon(Icons.more_vert),
                    onSelected: (String v) {
                      switch (v) {
                        case 'voice':
                          _openVoiceNotes(mc);
                        case 'search':
                          _openSearch(mc);
                        case 'export':
                          _exportThread(mc);
                        case 'manage':
                          context.push('/settings/channels');
                        case 'restore':
                          _restoreFromExport(mc);
                      }
                    },
                    itemBuilder: (BuildContext _) => <PopupMenuEntry<String>>[
                      // The notes this session took off this channel. It lives
                      // here, not on the strip: the strip answers "which
                      // channel", and a fifth control competing with the
                      // channel names is the shape the comment above it warns
                      // against. The count rides in the label, because a row
                      // that says "Voice notes" is otherwise silent about
                      // whether there is anything to open.
                      PopupMenuItem<String>(
                        key: const ValueKey<String>('chat-voice-notes'),
                        value: 'voice',
                        child: Row(
                          children: <Widget>[
                            const Icon(Icons.graphic_eq, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                voiceNotes == 0
                                    ? l.voiceNotesTitle
                                    : l.voiceNotesCount(voiceNotes),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuItem<String>(
                        key: const ValueKey<String>('chat-search'),
                        value: 'search',
                        enabled: msgs.isNotEmpty,
                        child: Row(
                          children: <Widget>[
                            const Icon(Icons.search, size: 20),
                            const SizedBox(width: 12),
                            // A menu row has to survive a long label on
                            // a narrow screen: the text takes what is
                            // left and ellipsises rather than overflowing.
                            Expanded(
                              child: Text(
                                l.chatSearchAction,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuItem<String>(
                        key: const ValueKey<String>('chat-export-thread'),
                        value: 'export',
                        enabled: msgs.isNotEmpty,
                        child: Row(
                          children: <Widget>[
                            const Icon(Icons.ios_share, size: 20),
                            const SizedBox(width: 12),
                            // A menu row has to survive a long label on
                            // a narrow screen: the text takes what is
                            // left and ellipsises rather than overflowing.
                            Expanded(
                              child: Text(
                                l.chatExportAction,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuItem<String>(
                        key: const ValueKey<String>('chat-restore'),
                        value: 'restore',
                        child: Row(
                          children: <Widget>[
                            const Icon(Icons.settings_backup_restore, size: 20),
                            const SizedBox(width: 12),
                            // A menu row has to survive a long label on
                            // a narrow screen: the text takes what is
                            // left and ellipsises rather than overflowing.
                            Expanded(
                              child: Text(
                                l.chatRestoreMenu,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuItem<String>(
                        key: const ValueKey<String>('chat-manage-channels'),
                        value: 'manage',
                        child: Row(
                          children: <Widget>[
                            const Icon(Icons.tune, size: 20),
                            const SizedBox(width: 12),
                            // A menu row has to survive a long label on
                            // a narrow screen: the text takes what is
                            // left and ellipsises rather than overflowing.
                            Expanded(
                              child: Text(
                                l.chatManageChannels,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
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
                  )
                else
                  // Speech off everywhere: the per-channel toggle would be a
                  // control that does nothing, so the slot says why and opens
                  // the screen that turns it on. Losing this left a control
                  // that simply vanished for the user who switched speech off.
                  //
                  // The icon is the *settings* one, not a muted speaker. It
                  // wears `volume_off` until the owner read it on the phone: a
                  // speaker glyph in a toolbar promises a toggle, and this
                  // button navigates. The state is in the tooltip, which is
                  // also the row's label for a screen reader.
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: IconButton(
                      key: const ValueKey<String>('chat-speech-off'),
                      tooltip: l.chatSpeechOffAction,
                      onPressed: () => context.push('/settings/app'),
                      icon: Icon(Icons.settings_outlined,
                          color: cs.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          // The sealed history could not be opened on this device: say so and
          // offer the one recovery path, rather than showing an empty thread
          // beside a report that it is missing.
          HistoryUnreadableNotice(onRestore: () => _restoreFromExport(mc)),
          HistoryRetentionNotice(dropped: dropped),

          // Message list (active channel) + R29 jump-to-newest pill.
          Expanded(
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: msgs.isEmpty
                      ? Center(
                          child: Text(l.chatEmpty,
                              style: TextStyle(color: cs.onSurfaceVariant)),
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

          // Composer. Without a radio there is nothing to type into, so the
          // row becomes the state and the way out of it instead of a disabled
          // field whose only advice is on another screen.
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: !ready
                  ? ComposerOffline(
                      connecting: context.select<MeshcoreController, bool>(
                          (MeshcoreController mc) => mc.isConnecting),
                    )
                  : LayoutBuilder(
                      builder: (BuildContext c, BoxConstraints box) {
                        // The field and three 48 dp buttons cannot share a
                        // 320 dp row at 200 % text without the field shrinking
                        // to the width of its own icon. Measured, not guessed:
                        // the floor is what the hint needs on one line, and
                        // below it the buttons take their own row instead of
                        // the field being cut.
                        final double fieldNeed = _fieldFloor(context);
                        final double fieldRoom =
                            box.maxWidth - _composerActionsWidth;
                        final bool stacked = fieldRoom < fieldNeed;
                        final Widget field = Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            TextField(
                              controller: _input,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _send(mc),
                              decoration: composerFieldDecoration(context,
                                  hint: l.chatComposerHint(activeName)),
                            ),
                            ComposerCounter(
                              budget: _budget,
                              text: _input.text,
                              label: l,
                            ),
                          ],
                        );
                        if (stacked) {
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              field,
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: <Widget>[
                                  ..._composerActions(context, mc, l),
                                ],
                              ),
                            ],
                          );
                        }
                        return Row(
                      children: <Widget>[
                        Expanded(
                          child: field,
                        ),
                        ..._composerActions(context, mc, l),
                      ],
                    );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  /// The three composer actions, in order, as they appear on their row.
  List<Widget> _composerActions(
      BuildContext context, MeshcoreController mc, AppLocalizations l) {
    final MeshcoreController m = mc;
    final bool ready = m.isReady;
    return <Widget>[
      IconButton(
        key: const ValueKey<String>('chat-voice'),
        tooltip: l.voiceTitle,
        onPressed: ready ? () => _openVoice(m) : null,
        icon: const Icon(Icons.mic_none_outlined),
      ),
      IconButton(
        key: const ValueKey<String>('chat-attach'),
        tooltip: l.mediaComposerTitle,
        onPressed: ready
            ? () => MediaComposer.show(
                  context,
                  service: _media,
                  // The platform picker where this build has one, and a named
                  // "cannot read a photo" state where it does not, so a harness
                  // never reaches a plugin.
                  source: context.read<MediaPhotoSource?>() ??
                      kNoMediaPhotoSource,
                  channelPsk: m.channelPsk(m.activeChannel),
                  byteBudget: kMediaPhotoBudgetBytes,
                  sendBlob: (Uint8List blob) => m.sendChannelData(
                    channelIdx: m.activeChannel,
                    dataType: kChannelDataTypeDev,
                    blob: blob,
                  ),
                )
            : null,
        icon: const Icon(Icons.add_photo_alternate_outlined),
      ),
      // The send control states whether it can act. It used to be enabled with
      // an empty field and with text over the radio's byte budget, and `_send`
      // returned in silence in both cases: a control that looks pressable and
      // does nothing. The counter under the field already says how far over the
      // budget the text is, so disabling here hides no explanation.
      IconButton(
        tooltip: l.chatSend,
        onPressed: _input.text.trim().isEmpty || !_budget.canSend(_input.text)
            ? null
            : () => _send(m),
        icon: const Icon(Icons.send),
      ),
    ];
  }

  /// What three 48 dp buttons and their gaps take from the composer row.
  static const double _composerActionsWidth = 48 * 3 + 8;

  /// The width the field needs before the buttons take their own row: ten
  /// characters at the field's own size, plus its inset and its two icon slots.
  /// Ten is a word and a space — under that the field is a search box, and the
  /// three actions beside it are what is eating the row.
  ///
  /// Measured from the real face at the real text scale rather than fixed in dp,
  /// because the buttons do not grow with the text and the field does not
  /// shrink with it either: at 200 % a 148 dp field holds four or five
  /// characters, which is a search box, not a composer. At 1.0 text on the
  /// owner's handset the same rule leaves the row exactly as it was.
  static double _fieldFloor(BuildContext context) {
    final TextStyle style = Theme.of(context).textTheme.bodyLarge ??
        TextStyle(fontSize: context.skin.type.sizeLg);
    final TextPainter p = TextPainter(
      text: TextSpan(text: 'n' * 10, style: style),
      textDirection: Directionality.of(context),
      maxLines: 1,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final double need = p.width + 56;
    p.dispose();
    return need;
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

class _MessageRow extends StatefulWidget {
  const _MessageRow(this.m,
      {super.key, required this.onAction, this.sinceLast});
  final ChatMessage m;
  final VoidCallback onAction;

  /// Time since the same identity last spoke on this channel (DR Pop name
  /// tag). Null = first message from them this session, or not block mode.
  final Duration? sinceLast;

  @override
  State<_MessageRow> createState() => _MessageRowState();
}

class _MessageRowState extends State<_MessageRow> {
  ChatMessage get m => widget.m;
  VoidCallback get onAction => widget.onAction;
  Duration? get sinceLast => widget.sinceLast;

  /// The send time is revealed, not printed.
  ///
  /// A terminal thread where every line carries `16:07` reads as a log file,
  /// and on a channel that is busy the stamps are most of the ink. The time
  /// is a detail you go looking for, so it appears when you ask: hold the row,
  /// or open its actions. It stays revealed for that row afterwards, because
  /// hiding it again under the reader's eyes is its own small hostility.
  bool _showTime = false;

  void _revealTime() {
    if (_showTime) return;
    setState(() => _showTime = true);
  }

  /// Hold or the actions button: reveal the stamp, then do the thing asked.
  VoidCallback get _revealThenAct => () {
        _revealTime();
        onAction();
      };

  /// APP-N3 — a stamp the reader can trust: the sender's own `HH:MM` when
  /// that clock agrees with this phone, and a named marker when it does not
  /// (a sender running fast used to print a time in the future).
  String _time(AppLocalizations l) => clockStamp(l, m.at);

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
    final Widget row = switch (_chatModeFor(skin.preset)) {
      _ChatMode.log => _log(context, skin),
      _ChatMode.bubble => _bubble(context, skin),
      _ChatMode.block => _block(context, skin),
    };
    // A message that names a place offers to report it. The line sits under
    // whichever row shape the skin uses — one placement, so no preset can
    // keep the old behaviour of naming a place and offering nothing.
    //
    // `select` rather than `watch`: the answer changes only when this row's
    // own text stops being a suggestion, so a notify for some other message
    // does not rebuild the list.
    final String? suggested = context.select<MeshcoreController, String?>(
        (MeshcoreController mc) => mc.placeSuggestionFor(m));
    if (suggested == null) return row;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        row,
        PlaceSuggestionLine(message: m, name: suggested),
      ],
    );
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
          echo: place == null
              ? null
              : PlaceEchoLine(place: place, store: context.read<PlaceStore>()),
          onAction: onAction);
    }
    final String mono = skin.type.monoFamily;
    final ({String? sender, String body}) parts = _split();
    final String? state =
        m.outgoing && m.delivery != null ? deliveryLabel(l, m.delivery!) : null;
    final String spoken = <String>[
      if (parts.sender != null) parts.sender!,
      _time(l),
      if (state != null) state,
      parts.body,
    ].join(', ');
    return Semantics(
      label: spoken,
      child: InkWell(
        onLongPress: _revealThenAct,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // R102 — scale the gutter with the text (see StudioMessageRow).
              // Narrow while the stamp is hidden: the gutter is the time's
              // place, and an empty 56 dp column is a hole in every row. The
              // direction glyph stays, because it is not a timestamp.
              SizedBox(
                width: (_showTime ? 56 : 16) *
                    MediaQuery.textScalerOf(context).scale(1),
                child: Text(_showTime ? '${_time(l)} ${m.outgoing ? '»' : '«'}'
                    : m.outgoing ? '»' : '«',
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
                        style:
                            TextStyle(color: skin.color.fg, fontFamily: mono)),
                    if (PlaceEchoLine.placeOf(m) case final Place place)
                      PlaceEchoLine(
                          place: place, store: context.read<PlaceStore>()),
                    _metaRow(skin),
                  ],
                ),
              ),
              IconButton(
                tooltip: AppLocalizations.of(context).chatMessageActions,
                iconSize: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: _revealThenAct,
                icon: Icon(Icons.more_vert, color: skin.color.fgMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- chat bubbles (Hyperlocal / AG-HUD) ----------------------------
  Widget _bubble(BuildContext context, MmSkin skin) {
    final ({String? sender, String body}) s = _split();
    // A message field is delimited by its FILL, not by a stroke around it.
    // Both at once is the shape that made the light skins read as a grid of
    // boxes: a paper panel (`surface`) with a visible hairline round it is two
    // ways of saying the same edge. The fill is `raised` — one step off the
    // page in every skin's own layer stack — so an incoming bubble is visible
    // on paper and on black without a second delimiter. Our own message keeps
    // the accent tint, which is a different signal (whose side it is), not a
    // second edge.
    final Color fill = m.outgoing
        ? skin.color.accent.withValues(alpha: 0.16)
        : skin.color.raised;
    return _aligned(
      context: context,
      skin: skin,
      decoration: ShapeDecoration(
        color: fill,
        shape: mmShapeBorder(skin.shape, side: BorderSide.none),
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
  //
  // This is the one place a fill and a stroke are both right: the 3 px rule is
  // the skin's motif, not an outline drawn around a filled box, and removing
  // it would leave two adjacent colours touching with no edge — which is what
  // the rule exists to prevent. The fill-only rule applies to the bubble
  // skins (`_bubble`) and to tags; a cited exception is not a precedent.
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

    final Widget field = Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      // Mondrian black rule around every colour field.
      decoration:
          BoxDecoration(color: fill, border: Border.all(color: base, width: 3)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (s.sender != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(s.sender!.toUpperCase(),
                  style: TextStyle(
                      color: ink.withValues(alpha: 0.85),
                      fontSize: skin.type.sizeSm,
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
                const SizedBox(width: 4),
              ],
              if (_showTime)
                Text(_time(l),
                    style: TextStyle(
                        color: ink.withValues(alpha: 0.65),
                        fontSize: skin.type.sizeMicro)),
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
          constraints:
              BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.6),
          child: field,
        ),
      ),
      if (tag != null) ...<Widget>[const SizedBox(width: 6), tag],
    ];

    return InkWell(
      onLongPress: _revealThenAct,
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
    final AppLocalizations l = AppLocalizations.of(context);
    return Align(
      alignment: m.outgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        child: InkWell(
          onLongPress: _revealThenAct,
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
                            fontSize: skin.type.sizeSm,
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
                if ((m.outgoing && m.delivery != null) || _showTime) ...<Widget>[
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (m.outgoing && m.delivery != null) ...<Widget>[
                        DeliveryStatusIcon(m.delivery!),
                        const SizedBox(width: 4),
                      ],
                      if (_showTime)
                        Text(_time(l),
                            style: TextStyle(
                                color: metaColor,
                                fontSize: skin.type.sizeMicro)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The row's own delivery glyph, and nothing else: route and signal are
  /// facts about a transmission, not about the message, so they live in the
  /// row's actions sheet where a reader goes when they need them.
  Widget _metaRow(MmSkin skin) {
    if (!(m.outgoing && m.delivery != null)) return const SizedBox.shrink();
    return Row(
      children: <Widget>[
        DeliveryStatusIcon(m.delivery!),
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
    final MmSkin skin = context.skin;
    return Container(
      width: 58,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
          color: base, border: Border.all(color: color, width: 3)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            width: 36,
            height: 36,
            child: CustomPaint(
              painter: _InvaderPainter(
                  seed: _fnv1a(seedKey), color: color, bg: base),
            ),
          ),
          if (since != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(since!,
                maxLines: 1,
                style: TextStyle(
                    color: color,
                    fontFamily: mono,
                    fontSize: skin.type.sizeMicro,
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
        canvas.drawRect(Rect.fromLTWH(x * cw, y * ch, cw, ch).deflate(0.6), on);
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
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.arrow_downward, size: 16, color: cs.onPrimary),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      color: cs.onPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: context.skin.type.sizeBodyLg)),
            ],
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

/// The passphrase a thread export travels with. The store's own key never
/// leaves the Keystore, so a file that must open years later carries its own.
