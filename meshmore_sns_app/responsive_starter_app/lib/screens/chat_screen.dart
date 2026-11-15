// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../chat/channel_read_store.dart';
import '../chat/block_actions.dart';
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
import '../cue/cue_service.dart';
import '../gen/app_localizations.dart';
import '../media/media_codec.dart';
import '../media/media_composer.dart';
import '../media/media_fetch_service.dart';
import '../media/media_offer.dart';
import '../media/media_photo.dart';
import '../media/mp1.dart';
import '../media/media_inbox.dart';
import '../media/media_transfer.dart';
import '../media/photo_inbox.dart';
import '../media/media_prefs.dart';
import '../media/received_photos_sheet.dart';
import '../ui/mp1_preview.dart';
import '../voice/voice_capture.dart';
import '../voice/voice_codec.dart';
import '../voice/voice_composer.dart';
import '../voice/voice_inbox.dart';
import '../voice/voice_notes_sheet.dart';
import 'channel_create_sheet.dart';
import '../voice/voice_playback.dart';
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
import '../util/provider_lookup.dart';
import '../util/clock_model.dart';
import '../ui/mm_scaffold.dart';
import '../util/share.dart';
import '../ui/mm_shape.dart';
import 'package:meshcore/meshcore.dart';

/// The DR Pop invader's sprite box, in pixels. The painter draws to it.
const double _invaderBox = 36;

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
  ///
  /// `late final` so the estimate can be the radio's own: this was built with
  /// the flat 4 ms/byte figure, which is calibrated to the USA/Canada preset and
  /// understates a slow preset by an order of magnitude, so the cost line a
  /// reader saw before spending the airtime was wrong by that factor. The
  /// estimator is read once, on the first send, by which time the radio has
  /// reported its parameters in any normal session.
  late final MediaTransferService _media = MediaTransferService(
    codec: const AvifMediaCodec(),
    estimator: context.read<MeshcoreController>().airtimeEstimator,
    clock: DateTime.now,
  );

  /// The pictures this session has taken off the channels.
  ///
  /// The app's `MediaInbox` reassembles a payload and hands it to whoever
  /// claimed it; nothing claimed an image, so a photo sent on a channel was
  /// reassembled and then dropped — the sender's receipt said "accepted" and
  /// the receiver saw nothing at all. This is the claim, and it is per tab
  /// because the sheet it opens is per channel.
  PhotoInbox? _photos;

  /// The message the last send created, so a failure can put the text back.

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

  /// The id of the newest row this screen last marked read, so a rebuild does not
  /// write the same mark again and a new message does write a new one.
  String? _markedNewest;

  /// The channel that mark was written for. The count alone was not enough:
  /// switching to a channel whose row count happened to equal the previous
  /// one's left the new thread never marked at all.
  int? _markedChannel;

  /// The channel the composer's text belongs to, so a scope change can tell a
  /// channel switch (which empties the field) from a radio hand-off (which
  /// must not).
  int? _draftChannel;
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
    }

    _listener = listener;
    mc.addListener(listener);
    _input.addListener(_onComposerChanged);
    _syncBudget(mc);
    _syncDraftScope(mc);
    // The inbound half of photos. The app-scoped inbox is the one consumer of
    // the radio's datagrams; this listens to what it completed, so a picture
    // that arrives while the reader is on another tab is still here when they
    // come back.
    // A nullable `read` still throws when nothing is registered, and a screen
    // that cannot build without an inbox is a screen that breaks in every
    // harness and every reduced app. The lookup is tolerant for the same reason
    // `context.skin` is: the feature is optional, the composer is not.
    MediaInbox? inbox;
    try {
      inbox = context.read<MediaInbox?>();
    } on ProviderNotFoundException {
      inbox = null;
    }
    if (inbox != null) {
      _photos = PhotoInbox(completed: inbox.completed)..start();
    }
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
    final bool sameChannel = _draftChannel == mc.activeChannel;
    final String typed = _input.text;
    _draftKey = key;
    _draftChannel = mc.activeChannel;
    _draftTimer?.cancel();
    _draftTimer = null;
    // The composer belongs to the conversation that is on screen. Saving the
    // draft and leaving the text in place offered one channel's half-written
    // message to the next — the owner's "it keeps the same message you typed
    // when you change channel". The listener is detached around the clear so
    // the empty text is not written as a draft for the *new* key.
    if (previous != null) unawaited(DraftStore.save(previous, typed));
    // Only a *channel* change empties the composer. A radio scope change with
    // the same channel is a migration — the draft typed before the radio
    // answered belongs to the thread that is still on screen — and clearing
    // there would throw away the sentence the user was writing while the link
    // came up.
    if (previous != null && !sameChannel) {
      _input.removeListener(_onComposerChanged);
      _input.clear();
      _input.addListener(_onComposerChanged);
    }
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
      // A sheet is not inside `MmScaffold`, so nothing else lifts its last row
      // clear of the navigation area; `showModalBottomSheet` keeps the inset in
      // the sheet's MediaQuery (`useSafeArea` is false), and it is applied here.
      builder: (BuildContext ctx) => SizedBox(
        height: MediaQuery.sizeOf(ctx).height * 0.7,
        child: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(l.meshbookTitle,
                    style: Theme.of(ctx).textTheme.titleMedium),
              ),
              const Expanded(child: MeshbookView()),
            ],
          ),
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

  /// The pictures this session holds for the active channel, newest first.
  Future<void> _openReceivedPhotos(MeshcoreController mc) async {
    final PhotoInbox? inbox = _photos;
    if (inbox == null) return;
    await ReceivedPhotosSheet.show(
      context,
      photos: inbox.photosFor(mc.activeChannel),
      codec: _media.codec,
      // Pictures that arrived in a codec this build does not carry. The count
      // is the fetch service's, and it is the only place a reader can learn
      // that something did arrive.
      foreign: context.read<MediaFetchService?>()?.foreignPictures ?? 0,
    );
  }

  /// Make a channel without leaving the thread.
  ///
  /// The only way to make one used to be Settings → Channels, which is four taps
  /// from the place a reader thinks of channels: here, on the strip that lists
  /// them. Making one from here also lands them in it, because a channel created
  /// and not selected is a channel they have to go looking for.
  Future<void> _createChannel(MeshcoreController mc) async {
    final bool? made =
        await ChannelCreateSheet.show(context, controller: mc);
    if (made == true && mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context).channelCreateCreated)));
    }
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
    // A debounce that is cancelled without a flush loses the last keystrokes:
    // type, leave the tab inside 700 ms, and the tail of the sentence is gone.
    if (_draftTimer != null && _draftTimer!.isActive) {
      final String? key = _draftKey;
      final String text = _input.text;
      if (key != null && text.trim().isNotEmpty) {
        unawaited(DraftStore.save(key, text));
      }
    }
    _draftTimer?.cancel();
    _photos?.dispose();
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
    // A sent message is no longer a draft, and a *failed* send is not put back
    // into the composer either. The failed row is already in the thread with a
    // retry action on it, so restoring the text duplicated it and left the box
    // holding the last message the moment a send went wrong — the owner's "it
    // keeps the message after you send it".
    //
    // A send that produced **no row at all** is the other case, and it is the
    // one that used to lose the text: nothing was written, so there is nothing
    // in the thread to retry, and the draft is put back below.
    if (key != null) {
      _draftTimer?.cancel();
      unawaited(DraftStore.clear(key));
    }
    // The text is cleared only once something was actually sent. It used to be
    // cleared first, so a send that returned null — the radio not ready, or a
    // capability the firmware has denied — took the message out of the composer
    // and put nothing in the thread: the reader's words were gone with no row
    // and no explanation.
    unawaited(mc.sendChannelTextTo(mc.activeChannel, t).then(
      (ChatMessage? sent) {
        if (!mounted) return;
        if (sent == null) {
          _restoreComposer(t, key);
          context.cue?.play(CueKind.taskError);
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context).chatSendNotSent)),
          );
          return;
        }
        // The one cue every pack has carried since it was written and nothing
        // played: a short "that went" tick, distinct from the arrival sounds so
        // a sender hears their own message leave and nobody else's.
        context.cue?.play(CueKind.send);
        _input.clear();
        _nearWarned = false;
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
    // Pictures this session has taken off this channel, read where the buttons
    // are drawn: the control appears only when there is one, because a fourth
    // icon on every channel would be a promise that something is there.
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
    final Map<int, int> unread = <int, int>{
      ...(allMessages == 0
          ? const <int, int>{}
          : UnreadCounts.perChannel(
              channels: channels.map((MapEntry<int, String> e) => e.key),
              history: mc.messagesFor,
              reads: reads,
              filter: filter,
            )),
    };
    // The thread on screen, scrolled to its newest row, is being read as it
    // arrives. The mark moves a frame later than the count is computed, so the
    // chip for the channel the reader is looking at used to blink a badge on
    // for that frame — the owner's "a notification lands and the tag I am
    // sitting on goes dark with a number". A channel you are reading has no
    // unread traffic, so it is removed from the map rather than drawn and then
    // cleared.
    final bool readingThisThread = (widget.isCurrent ?? true) && _atBottom;
    if (readingThisThread) unread.remove(active);
    // Reading is a state of the *tab*, not of the scroll position: a reader who
    // has scrolled up is still looking at the thread, and leaving the mark behind
    // made the badge tick up on the channel they were sitting on. The
    // jump-to-newest pill already offers the rows they scrolled past.
    //
    // The mark is remembered per channel, and it is advanced only after the
    // write lands. Both matter: a count from one channel that happened to match
    // another's left the second one permanently unmarked, and advancing before
    // the write meant a single failed write made the badge stick until the next
    // message arrived.
    if (reads != null &&
        (widget.isCurrent ?? true) &&
        msgs.isNotEmpty &&
        (_markedChannel != active || _markedNewest != msgs.last.id)) {
      final int channel = active;
      // The newest *row*, not the count: history is capped at 250 per channel,
      // so once a channel is full an arriving message evicts one and the length
      // never changes again — the mark stopped advancing and the badge on the
      // thread being read started counting again.
      final String newestId = msgs.last.id;
      final ChatMessage newest = msgs.last;
      _markedChannel = channel;
      _markedNewest = newestId;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await reads.markRead(channel,
            at: newest.at.add(const Duration(milliseconds: 1)));
      });
    }

    return MmScaffold(
      // A thread appends at the bottom, so a bar that grows as you scroll would
      // say the opposite of what the view does. The edge here is neutral: one
      // hairline, the same length at every position.
      edgeProgress: false,
      child: Column(
        children: <Widget>[
          // R91 — one row, one job: switch channel. The caption above it
          // said "CHANNEL · PUBLIC" while the selected chip two lines below
          // already said "Public", and the collapse chevron existed only to
          // hide the strip under it. Header + strip was 108 dp for that.
          SizedBox(
            height: context.skin.space.step(9) + context.skin.space.screenEdge,
            child: Row(
              children: <Widget>[
                // Only the channels scroll. The three controls at the end are
                // fixed: they used to be the last children of this list, so a
                // reader with enough channels could not reach "more" without
                // scrolling the strip sideways, and adding the create chip was
                // enough to push them off a 390 dp screen entirely.
                Expanded(
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
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
                        // The count rides in the label, not in the chip's
                        // `avatar`. Material draws an avatar inside a circle at
                        // the chip's leading edge, so a count there read as a
                        // dark disc with a second glyph in it. A small number
                        // after the name is the whole fact.
                        label: _ChannelChipLabel(
                          name: ch.value,
                          unread: unread[ch.key] ?? 0,
                          badgeKey: ValueKey<String>('unread-${ch.key}'),
                        ),
                        selected: ch.key == active,
                        // The chip's fill states the selection; a tick as well
                        // is one mark too many beside a channel name.
                        showCheckmark: false,
                        onSelected: (_) => mc.setActiveChannel(ch.key),
                      ),
                    ),
                  ),
                // A channel can be made from the strip itself.
                //
                // The overflow menu had the row, and an overflow is where a
                // reader looks last: the strip is the one place that lists
                // channels, so the way to make one belongs at the end of that
                // list, where the eye already is when it runs out of names. One
                // tap, and no menu between the intent and the sheet.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Semantics(
                    button: true,
                    label: l.channelCreateTitle,
                    excludeSemantics: true,
                    child: ActionChip(
                      key: const ValueKey<String>('chat-new-channel-chip'),
                      avatar: const Icon(Icons.add, size: 16),
                      label: Text(l.channelCreateTitle),
                      onPressed: () => _createChannel(mc),
                    ),
                  ),
                ),
                  ],
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
                        case 'new-channel':
                          _createChannel(mc);
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
                        key: const ValueKey<String>('chat-new-channel'),
                        value: 'new-channel',
                        child: Row(
                          children: <Widget>[
                            const Icon(Icons.add, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                l.channelCreateTitle,
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
          // A hidden control has to say where it went, once and briefly. Only
          // on a channel where media is not offered.
          if (!_mediaAllowed(mc))
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Text(
                l.chatMediaPrivateOnly,
                key: const ValueKey<String>('chat-media-private-only'),
                style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: context.skin.type.sizeSm),
              ),
            ),
          const Divider(height: 1),
          // The sealed history could not be opened on this device: say so and
          // offer the one recovery path, rather than showing an empty thread
          // beside a report that it is missing.
          HistoryUnreadableNotice(onRestore: () => _restoreFromExport(mc)),
          HistoryRetentionNotice(dropped: dropped),

          // Photos announced on this channel that nobody has asked for yet.
          // One preview, one line, one action: the pixels are a tap away and
          // they will arrive as a direct record, never as a flood.
          _PhotoAnnouncementStrip(channelIdx: mc.activeChannel),
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
  /// Whether a photo or a voice note belongs on this channel.
  ///
  /// The mesh's own etiquette, and now the app's: a chunked picture is a dozen
  /// or so datagrams every repeater in range re-transmits, so it belongs on a
  /// direct message or a private channel. The public channel is the one
  /// everybody shares, which makes it exactly the wrong place. Measured against
  /// what other MeshCore clients document, this is their rule too.
  bool _mediaAllowed(MeshcoreController mc) {
    if (!mc.isReady) return false;
    final List<int>? psk = mc.channelPsk(mc.activeChannel);
    if (psk == null) return false;
    final bool isPublic = mc.activeChannel == 0 &&
        psk.length == kPublicChannelPsk.length &&
        <int>[for (int i = 0; i < psk.length; i++) i]
            .every((int i) => psk[i] == kPublicChannelPsk[i]);
    return !isPublic;
  }

  List<Widget> _composerActions(
      BuildContext context, MeshcoreController mc, AppLocalizations l) {
    final MeshcoreController m = mc;
    final int receivedPhotos = _photos?.countFor(m.activeChannel) ?? 0;
    final bool ready = m.isReady;
    // Hidden, not disabled: a button that cannot work is a promise the app
    // cannot keep, and the strip above the composer already says where media
    // goes.
    final bool media = _mediaAllowed(m);
    return <Widget>[
      if (media)
        IconButton(
          key: const ValueKey<String>('chat-voice'),
          tooltip: l.voiceTitle,
          onPressed: ready ? () => _openVoice(m) : null,
          icon: const Icon(Icons.mic_none_outlined),
        ),
      if (receivedPhotos > 0)
        IconButton(
          key: const ValueKey<String>('chat-received-photos'),
          tooltip: l.mediaReceivedTitle,
          onPressed: () => _openReceivedPhotos(m),
          icon: Badge(
            label: Text('$receivedPhotos'),
            child: const Icon(Icons.photo_library_outlined),
          ),
        ),
      if (media)
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
                  byteBudget: MediaSendSize.standard.budgetBytes,
                  // The preview carries MeshPix's data type, so a MeshPix user
                  // sees our announcement and we see theirs.
                  sendBlob: (Uint8List blob) => m.sendChannelData(
                    channelIdx: m.activeChannel,
                    dataType: kMp1DataType,
                    blob: blob,
                  ),
                  // The app provides one store for the session. A harness that
                  // pumps this screen without it still gets a working sheet:
                  // the offers simply live as long as the composer.
                  offers: readOrNull<MediaOfferStore>(context) ??
                      MediaOfferStore(),
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
        onPressed: _input.text.trim().isEmpty ||
                !_budget.canSend(_input.text) ||
                !m.isReady
            ? null
            : () => _send(m),
        icon: const Icon(Icons.send),
      ),
    ];
  }

  /// What three 48 dp buttons and their gaps take from the composer row.
  /// How wide the action row is, in the worst case it can be.
  ///
  /// Three buttons, plus the received-photos control when this channel has one.
  /// The field's floor is measured against this, so a row that is one icon wider
  /// than the constant would push the field under its own hint.
  double get _composerActionsWidth {
    final int buttons = (_photos?.photos.isNotEmpty ?? false) ? 4 : 3;
    return 48 * buttons + 8;
  }

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

  /// The send time is *not* on the row, in any state.
  ///
  /// A terminal thread where every line carries `16:07` reads as a log file, and
  /// on a busy channel the stamps are most of the ink. An earlier version
  /// revealed the stamp on the row when it was held, which widened a column in
  /// the middle of the thread and moved every line sideways under the reader's
  /// finger as they reached for the menu. The time is a property of the message,
  /// so it belongs in the message's own sheet, at the top, with the rest of what
  /// the row has no space for.
  VoidCallback get _revealThenAct => onAction;

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
    final Widget? chips = m.reactions.isEmpty ? null : _ReactionChips(m.reactions);
    if (suggested == null && chips == null) return row;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        row,
        if (chips != null) chips,
        if (suggested != null) PlaceSuggestionLine(message: m, name: suggested),
      ],
    );
  }

  /// The preview this row carries, drawn as the palette grid it is.
  ///
  /// A preview arrives as one channel datagram, so it is the row's own content
  /// rather than something that arrives later: without it the thread shows an
  /// empty line where somebody sent a picture.
  Widget? _picture(MmSkin skin) {
    final Mp1Image? image = m.mp1Image;
    if (image == null) return null;
    return _MessagePicture(image: image, skin: skin);
  }

  // --- terminal log (SEELE / NERV / Recon) ---------------------------
  Widget _log(BuildContext context, MmSkin skin) {
    final AppLocalizations l = AppLocalizations.of(context);
    // R71: Studio sets words sans, machine data mono (see
    // StudioMessageRow); the terminal presets keep the all-mono log.
    if (skin.type.sansLabels) {
      final ({String? sender, String body}) s = _split();
      final Place? place = PlaceEchoLine.placeOf(m);
      final Widget? picture = _picture(skin);
      final Widget row = StudioMessageRow(
          message: m,
          body: s.body,
          sender: s.sender,
          echo: place == null
              ? null
              : PlaceEchoLine(place: place, store: context.read<PlaceStore>()),
          onAction: onAction);
      if (picture == null) return row;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[row, picture],
      );
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
              // A fixed direction glyph, scaled with the text. The gutter is
              // not the time's place any more: the time is in the actions
              // sheet, so nothing in the row moves when the reader asks for it.
              SizedBox(
                width: 16 * MediaQuery.textScalerOf(context).scale(1),
                child: Text(m.outgoing ? '»' : '«',
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
                    if (m.text.isNotEmpty)
                      Text(stripBotMarker(m.text),
                          style: TextStyle(
                              color: skin.color.fg, fontFamily: mono)),
                    if (_picture(skin) case final Widget picture) picture,
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
      picture: _picture(skin),
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
          if (s.body.isNotEmpty)
            Text(stripBotMarker(s.body),
                style: TextStyle(
                    color: ink,
                    fontFamily: skin.type.bodyFamily,
                    fontWeight: FontWeight.w600,
                    height: 1.3)),
          if (_picture(skin) case final Widget picture) picture,
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (m.outgoing && m.delivery != null)
                DeliveryStatusIcon(m.delivery!),
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

    // The action button sits in the free space beside the field, on the same
    // side as the name tag for an incoming message and on the far side for our
    // own. Long-press still works; this is the visible, accessible path.
    final Widget actions = IconButton(
      tooltip: AppLocalizations.of(context).chatMessageActions,
      iconSize: 16,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      onPressed: _revealThenAct,
      icon: Icon(Icons.more_vert, color: skin.color.fgMuted),
    );

    final List<Widget> cells = <Widget>[
      Flexible(
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.6),
          child: field,
        ),
      ),
      const SizedBox(width: 4),
      actions,
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
    Widget? picture,
  }) {
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
                // A visible way to act. The log mode has had this button since
                // R20; the bubble and block modes were long-press only, which
                // leaves three of eleven presets with no discoverable action and
                // no accessible alternative to the gesture.
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (sender != null)
                      Flexible(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(sender,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: senderColor,
                                  fontSize: skin.type.sizeSm,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                    IconButton(
                      tooltip: AppLocalizations.of(context).chatMessageActions,
                      iconSize: 16,
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      constraints:
                          const BoxConstraints(minWidth: 48, minHeight: 48),
                      onPressed: _revealThenAct,
                      icon: Icon(Icons.more_vert, color: metaColor),
                    ),
                  ],
                ),
                if (body.isNotEmpty)
                  Text(body,
                      style: TextStyle(
                          color: bodyColor,
                          fontFamily: bodyFamily,
                          fontWeight: bodyWeight,
                          height: 1.3)),
                if (picture != null) picture,
                if (PlaceEchoLine.placeOf(m) case final Place place)
                  PlaceEchoLine(
                      place: place, store: context.read<PlaceStore>()),
                if (m.outgoing && m.delivery != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      DeliveryStatusIcon(m.delivery!),
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
            width: _invaderBox,
            height: _invaderBox,
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

/// A channel's name, with its unread count after it.
///
/// Inline rather than as the chip's `avatar`: Material renders an avatar inside
/// a circle at the chip's leading edge, where a count reads as a dark disc with
/// a second glyph in it. The count is the only decoration a channel tag needs,
/// and it goes away when the thread is read.
class _ChannelChipLabel extends StatelessWidget {
  const _ChannelChipLabel({
    required this.name,
    required this.unread,
    required this.badgeKey,
  });

  final String name;
  final int unread;
  final Key badgeKey;

  @override
  Widget build(BuildContext context) {
    if (unread <= 0) return Text(name);
    final MmSkin skin = context.skin;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(name),
        SizedBox(width: skin.space.step(1)),
        _UnreadBadge(key: badgeKey, count: unread),
      ],
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
      {super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final MmSkin skin = context.skin;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: skin.space.step(1)),
      constraints: BoxConstraints(minWidth: skin.space.step(5)),
      // The attention pair, not the accent pair. On a *selected* chip the
      // accent is already the chip's own fill, so an accent badge vanished into
      // the chip it was counting for — the owner's "the numbers and bubbles in
      // the channel tags are wrong". `alert`/`onAlert` is the app's one
      // attention pair and reads on both states of every skin.
      decoration: BoxDecoration(
        color: skin.color.alert,
        borderRadius: BorderRadius.circular(skin.shape.cornerSize),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: skin.type.sizeMicro,
          fontWeight: FontWeight.w700,
          color: skin.color.onAlert,
        ),
      ),
    );
  }
}

/// The passphrase a thread export travels with. The store's own key never
/// leaves the Keystore, so a file that must open years later carries its own.

/// The previews this session heard on one channel, newest first.
///
/// A picture on a mesh is announced, not sent: the sender spends one datagram
/// on a 24x24 palette preview and keeps the pixels for whoever asks. That makes
/// this strip the door to every photo on the channel, and the only thing that
/// has to be on screen for the model to work.
class _PhotoAnnouncementStrip extends StatelessWidget {
  const _PhotoAnnouncementStrip({required this.channelIdx});

  final int channelIdx;

  @override
  Widget build(BuildContext context) {
    final MediaFetchService? fetch = watchOrNull<MediaFetchService>(context);
    if (fetch == null) return const SizedBox.shrink();
    final List<PhotoAnnouncement> here = fetch.announcements
        .where((PhotoAnnouncement a) => a.channelIdx == channelIdx)
        .toList()
        .reversed
        .toList();
    if (here.isEmpty) return const SizedBox.shrink();
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;
    return SizedBox(
      // Two 56 dp thumbnails plus the gap the row is built around.
      height: skin.space.step(9) * 2 + skin.space.rowGap,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: skin.space.rowInset),
        itemCount: here.length,
        separatorBuilder: (_, __) => SizedBox(width: skin.space.rowGap),
        itemBuilder: (BuildContext c, int i) {
          final PhotoAnnouncement a = here[i];
          return InkWell(
            key: ValueKey<String>('photo-announce-${a.id}'),
            onTap: () => fetch.request(id: a.id, channelIdx: channelIdx),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // Once the pixels arrive the thumbnail is the picture, not the
                // palette preview.
                if (fetch.loaded[a.id] case final MediaPhoto photo)
                  RgbaThumbnail(photo: photo, size: 56)
                else
                  Mp1PreviewImage(image: a.image, size: 56),
                SizedBox(width: skin.space.rowGap),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(l.photoAnnounceTitle,
                        style: TextStyle(
                            color: skin.color.fg,
                            fontSize: skin.type.sizeBody)),
                    Text(
                      fetch.loaded.containsKey(a.id)
                          ? l.photoAnnounceLoaded
                          : a.upgradeChunks == 0
                              ? l.photoAnnouncePreviewOnly
                              : l.photoAnnounceLoad(a.upgradeChunks),
                      style: TextStyle(
                          color: skin.color.fgMuted,
                          fontSize: skin.type.sizeSm),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// A picture inside a message row.
///
/// Three states, one thumbnail: the preview while the full picture is unfetched,
/// the decoded picture once it is, and the same palette grid after a restart
/// because the row kept the datagram rather than the pixels.
///
/// The not-fetched line is text, not a control. Asking for the pixels is the
/// strip above the composer, which is the one place allowed to spend that
/// airtime; a second button here would be a second way to ask for the same
/// thing, and the row is not where a reader looks to spend it.
class _MessagePicture extends StatefulWidget {
  const _MessagePicture({required this.image, required this.skin});

  final Mp1Image image;
  final MmSkin skin;

  @override
  State<_MessagePicture> createState() => _MessagePictureState();
}

class _MessagePictureState extends State<_MessagePicture> {
  /// Grey until App settings says otherwise, which is also the default.
  bool _color = false;

  @override
  void initState() {
    super.initState();
    MediaPrefs.colorPhotos().then((bool v) {
      if (mounted && v) setState(() => _color = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = widget.skin;
    // A thumbnail, not a billboard: four body heights, so it grows with the
    // text a reader chose and never dominates the line it arrived in.
    final double side = (skin.type.sizeBody * 4).clamp(48.0, 96.0);
    final MediaFetchService? fetch = watchOrNull<MediaFetchService>(context);
    final MediaPhoto? full = fetch?.loaded[widget.image.transferId];
    final bool waiting = full == null && widget.image.upgradeChunks > 0;
    return Padding(
      padding: EdgeInsets.only(top: skin.space.labelToControl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Semantics(
            image: true,
            label: l.mediaPhotoSemantics,
            child: InkWell(
              key: ValueKey<String>('message-picture-${widget.image.transferId}'),
              onTap: () => _open(context, l),
              child: full != null
                  ? RgbaThumbnail(photo: full, size: side)
                  : Mp1PreviewImage(
                      image: widget.image, size: side, color: _color),
            ),
          ),
          if (waiting)
            Padding(
              padding: EdgeInsets.only(top: skin.space.insideText),
              child: Text(
                l.photoAnnounceLoad(widget.image.upgradeChunks),
                style: TextStyle(
                    color: skin.color.fgMuted, fontSize: skin.type.sizeSm),
              ),
            ),
        ],
      ),
    );
  }

  /// Full size, in a dialog, over the row that carries it.
  void _open(BuildContext context, AppLocalizations l) {
    final MmSkin skin = widget.skin;
    showDialog<void>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        backgroundColor: skin.color.surface,
        content: Mp1PreviewImage(
          image: widget.image,
          size: math.min(MediaQuery.sizeOf(c).width - 96, 336),
          color: _color,
        ),
        actions: <Widget>[
          // MmAction, not a TextButton: a bare text button reads as a label,
          // and the guard in test/ui/tap_affordance_guard_test.dart holds that
          // line for every surface in the app.
          MmAction(
            label: l.mediaClose,
            onPressed: () => Navigator.of(c).pop(),
          ),
        ],
      ),
    );
  }
}

/// The reactions on one message, under the row it belongs to.
///
/// A count rather than a list of names: on a 320 dp row three names is not a
/// chip, it is a paragraph, and the sheet that opens on tap is where the names
/// belong. The sender is null for MeshCore Open's shorthand, which carries no
/// identity, so the count is all the information there is.
class _ReactionChips extends StatelessWidget {
  const _ReactionChips(this.reactions);

  final Map<String, List<String?>> reactions;

  @override
  Widget build(BuildContext context) {
    final MmSkin skin = context.skin;
    return Padding(
      padding: EdgeInsets.only(left: skin.space.rowInset, top: skin.space.rowGap),
      child: Wrap(
        spacing: skin.space.rowGap,
        runSpacing: skin.space.insideText,
        children: <Widget>[
          for (final MapEntry<String, List<String?>> e in reactions.entries)
            Container(
              key: ValueKey<String>('reaction-${e.key}'),
              padding: EdgeInsets.symmetric(
                  horizontal: skin.space.labelToControl,
                  vertical: skin.space.insideText),
              decoration: ShapeDecoration(
                color: skin.color.surfaceAlt,
                shape: mmShapeBorder(skin.shape,
                    side: BorderSide(color: skin.color.line)),
              ),
              child: Text(
                e.value.length > 1 ? '${e.key} ${e.value.length}' : e.key,
                style: TextStyle(
                    color: skin.color.fg, fontSize: skin.type.sizeBody),
              ),
            ),
        ],
      ),
    );
  }
}
