// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';

import '../util/mesh_log.dart';
import '../util/prefs.dart';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:meshcore/meshcore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'failure.dart';
import 'link_acquire.dart';

import 'airtime.dart';
import 'airtime_prefs.dart';
import 'airtime_meter.dart';
import '../app/app_errors.dart';
import 'background_keepalive.dart';
import 'background_prefs.dart';
import 'battery_history_store.dart';
import 'battery_model.dart';
import 'default_channel_store.dart';
import 'device_power_specs.dart';
import 'ble_connector.dart';
import 'channel_datagram.dart';
import 'command_ledger.dart';
import 'contact_store.dart';
import 'chat_message.dart';
import 'radio_config_transaction.dart';
import 'radio_identity_store.dart';
import 'chat_store.dart';
import 'discovered_node.dart';
import 'dm_read_store.dart';
import 'favorite_store.dart';
import 'known_store.dart';
import 'superseded_store.dart';
import 'node_tags_store.dart';
import 'mesh_event.dart';
import 'message_heat.dart';
import 'node_telemetry.dart';
import 'own_location.dart';
import 'coverage_store.dart';
import 'paired_device_history.dart';
import 'paired_device_store.dart';
import 'reconnect_policy.dart';
import '../perms/location_service.dart';
import '../sns/city_gazetteer.dart';
import '../sns/meshbook.dart';
import '../sns/meshbook_store.dart';
import '../sns/place_inference.dart';
import '../sns/weather_inference.dart';
import '../util/frame_trackers.dart';
import '../util/safe_notifier.dart';
import '../util/geo.dart' as geo;

/// App-facing facade over [MeshcoreConnection], exposed via Provider.
///
/// Human-readable reason for a `RESP_CODE_ERR` code (protocol spec
/// `err_code`), so a silent failure like a full contact table surfaces as
/// text instead of an opaque "0103".
String deviceErrorReason(int? code) => switch (code) {
      1 => 'unsupported command',
      2 => 'not found',
      3 => 'contact list full',
      4 => 'bad state',
      5 => 'storage I/O error',
      6 => 'illegal argument',
      null => 'unknown',
      _ => 'code $code',
    };

/// The transport is obtained through [transportFactory]; the default
/// scans/connects over BLE, but tests inject a fake transport so the
/// whole controller path is `flutter test`-covered without hardware.
/// Which reply the firmware gives for a send (verified against
/// `MyMesh.cpp`): channel text, raw data, channel datagrams and the
/// self-advert are answered with a bare OK/ERR; a DM, a status request, a
/// telemetry request and a trace are answered with `RESP_CODE_SENT`.
/// [CommandAnswer] carries that distinction into the ledger.
/// What a Retry did, so the screen can say it rather than guess.
enum RetryOutcome { refused, sent, sentAfterPathReset }

class MeshcoreController extends ChangeNotifier with SafeNotifier {
  MeshcoreController({
    Future<MeshcoreTransport> Function()? transportFactory,
    MeshcoreConnection? connection,
    ReconnectPolicy? reconnectPolicy,
    Future<void> Function(Duration)? reconnectDelay,
    BackgroundKeepalive? backgroundKeepalive,
    LocationService? locationService,
    Duration? deliveryTimeoutOverride,
    Duration? channelDataTimeout,
    Duration? radioConfigTimeout,
    Duration? telemetryPollInterval,
    Duration? selfInfoPollInterval,
    Duration? linkCloseTimeout,
    Duration? linkOpenTimeout,
    Duration? contactIdleOverride,
    Duration? channelProbeIdleOverride,
    PlaceInferenceEngine? placeInferenceEngine,
    AirtimeMeter? airtimeMeter,
  })  : _deliveryTimeoutOverride = deliveryTimeoutOverride,
        _linkCloseTimeout = linkCloseTimeout ?? kLinkCloseTimeout,
        _linkOpenTimeout = linkOpenTimeout ?? kLinkOpenTimeout,
        _contactIdleOverride = contactIdleOverride,
        _channelProbeIdleOverride = channelProbeIdleOverride,
        _channelDataTimeoutOverride = channelDataTimeout,
        _radioConfigTimeoutOverride = radioConfigTimeout,
        _selfInfoPollInterval =
            selfInfoPollInterval ?? const Duration(seconds: 60),
        _telemPollIntervalOverride = telemetryPollInterval,
        _placeEngine = placeInferenceEngine ??
            PlaceInferenceEngine(gazetteer: const CityGazetteer()),
        _transportFactory =
            transportFactory ?? BleConnector.autoConnect,
        _keepalive =
            backgroundKeepalive ?? const NoopBackgroundKeepalive(),
        _connection = connection ?? MeshcoreConnection(),
        // 6s floor keeps retry scans inside Android 17's silent BLE
        // scan throttle (5 start/stop cycles per 30s).
        _reconnect = reconnectPolicy ??
            ReconnectPolicy(floor: const Duration(seconds: 6)),
        _delay = reconnectDelay ?? Future<void>.delayed,
        _location = locationService ?? NoopLocationService(),
        _airtime = airtimeMeter ?? AirtimeMeter() {
    unawaited(_loadAirtimePolicy());
    _statesSub = _connection.states.listen((MeshcoreConnectionState s) {
      _state = s;
      notifyListeners();
      if (s == MeshcoreConnectionState.ready) {
        _reconnectAttempt = 0;
        // Post R41 bug fix: hydrate paired-name / -remote-id from
        // prefs every time we reach ready. BleConnector._finish has
        // already persisted the pairing by this point, but the
        // controller's cached fields are only set by
        // autoConnectIfPaired() / connectToPickedDevice() — neither
        // of which fires for a "Connect" tap on the dashboard slab
        // that goes through a fresh scan. Without this rehydrate
        // the Device sheet read "No device paired" right after a
        // successful manual connect.
        unawaited(_hydratePairedFromPrefs());
        // These radios have no persistent RTC; without this every
        // device-sourced timestamp (contact last-heard, message
        // times) is in an unset clock, so "in range" and ordering
        // are meaningless. Standard companion-app behaviour.
        // READ the device clock first, and write it only if the reply shows
        // the device behind. The firmware only moves its clock forward
        // (`MyMesh.cpp:1247-1257`), so writing blind refuses on every radio
        // that kept time across a reboot — a refused command the app then had
        // to explain away in the activity feed.
        _requestDeviceTime();
        _requestDeviceInfo();
        // Know whether this is still the radio the app has been talking to.
        unawaited(_checkRadioIdentity());
        // R38 — read the device's custom-var map (gps, gps_interval,
        // …). Also: if the user already has advertLocPolicy=GPS but
        // the firmware's GPS module is disabled, auto-enable it so
        // `sensors.node_lat/lon` actually start tracking. This is
        // the silent on-boarding step the official companion app
        // performs.
        _requestCustomVars();
        _startBatteryPolling();
        _startSelfInfoPolling();
        _probeChannels();
        // Pull self-telemetry once on ready — the only thing
        // CMD_SET_OTHER_PARAMS's telemetry mode controls is whether
        // the device *broadcasts* it on the air; the companion path
        // (CMD_SEND_TELEMETRY_REQ → PUSH_CODE_TELEMETRY_RESPONSE) is
        // always available and returns immediately for the self case.
        // Used to populate altitude in ownLocation.
        requestSelfTelemetry();
        // Begin politely polling contacts for telemetry (opt-in) so
        // temperature / altitude populate across the fabric.
        _startTelemetryPolling();
        // Drain anything the device queued before/while we connected
        // (heard contacts/adverts + received messages). This one IS a
        // backlog: it is history, not traffic arriving now.
        _drainStart(backlog: true);
        // The radio never pushes its stored contact table: it streams it only
        // in answer to `CMD_GET_CONTACTS`, and `END_OF_CONTACTS` carries the
        // most recent `lastmod` so the next request can ask for changes only
        // (`MyMesh.cpp:2209-2232`). Without this the app connected to a radio
        // holding twenty contacts, showed "0 known", and filled the list only
        // if the user happened to open the device-contacts screen.
        unawaited(_syncContactsOnConnect());
        // D8.1: a channel broadcast goes out under the radio's own flood scope,
        // so the app asks what that is and can tell the user who receives. The
        // reply is `RESP_CODE_DEFAULT_FLOOD_SCOPE` (0x1C), which the frame
        // codec leaves as an unsupported frame and decodes on demand.
        _requestFloodScope();
        // The radio's add policy, once per connection: the device page shows
        // it, and it is what decides whether a new node becomes a contact at
        // all. The repeat ranges explain a radio that hears but does not relay.
        unawaited(requestAutoAddConfig());
        unawaited(requestAllowedRepeatFreq());
        unawaited(requestTuningParams());
        // Keep the process alive in the background so the link +
        // drain survive Doze (Android only; no-op elsewhere).
        if (_bgKeepaliveEnabled) unawaited(_startKeepalive());
        // R33 — if the user has a saved default channel slot,
        // switch to it now. The device persists its own active
        // slot too; this preference wins on app launch so a
        // user with multiple radios always lands on their
        // preferred slot rather than whatever each device
        // happens to remember. One-shot per ready transition
        // (subsequent in-session reconnects don't re-apply).
        if (!_appliedDefaultChannel) {
          _appliedDefaultChannel = true;
          unawaited(_applyDefaultChannel());
        }
      } else if (s == MeshcoreConnectionState.reconnecting ||
          s == MeshcoreConnectionState.failed) {
        // The link the commands were sent over is gone, so the radio's
        // answers cannot be attributed to them any more. Failing them here
        // would be wrong (a reconnect may still deliver), so they keep
        // their own watchdogs and the queue is cleared so the *next* OK is
        // not credited to a command that may never be answered.
        for (final String id in _ledger.reset()) {
          // A marker dropped by the link is not an answer. A chat row waiting
          // on it reads unknown rather than being left in `sending` forever.
          if (id == _channelDataMarker) {
            _completeChannelData(const DecodeFailure(
              MeshcoreDecodeError(DecodeErrorKind.empty, 'link lost'),
            ));
          } else if (id == _configMarker) {
            _completeRadioConfig(const RadioAnswer.silent());
          } else if (id == _rawSendMarker) {
            abandonRawSend();
          } else if (id == _toolSendMarker || id == _advertSendMarker) {
            _dropPending(id);
          } else {
            _uncertainOutgoing(id, 'link lost before the radio answered');
          }
        }
        // A radio-config write in flight on that link will never be answered
        // now. Report it as silent rather than let the caller wait out the
        // timeout for an answer that cannot come.
        _completeRadioConfig(const RadioAnswer.silent());
        // The next connection asks for the contact table again. The stream's
        // watchdog stops here too: an end-of-contacts frame that never arrived
        // would otherwise leave `_probing` true and make the next sync wait out
        // its idle windows before asking anything.
        _contactIdleTimer?.cancel();
        _contactIdleTimer = null;
        _probing = false;
        _contactsSyncRequested = false;
        _floodScopeAsked = false;
        // A handshake timeout is not congestion: the radio never answered a
        // frame that was sent to it, and the ladder's six-second floor exists
        // for Android's BLE scan throttle rather than for this. The first
        // retry after a timeout therefore goes out at once. Only the first:
        // a radio that never answers would otherwise be re-scanned with no
        // delay at all, which is the pattern that throttle drops silently, so
        // from the second attempt the ladder and its floor apply again.
        final int timeouts = _connection.handshakeTimeouts;
        final bool handshakeTimedOut = timeouts > _handshakeTimeoutsSeen;
        if (handshakeTimedOut) _handshakeTimeoutsSeen = timeouts;
        _maybeScheduleReconnect(
            immediate: handshakeTimedOut && _reconnectAttempt == 0);
      }
    });
    _inboundSub = _connection.inbound.listen(_processInbound);
    _rawSub = _connection.rawInbound.listen((Uint8List bytes) {
      final String hex = bytes
          .map((int b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      _capture.add(hex);
      if (_capture.length > _captureCap) _capture.removeAt(0);
    });
    _historyRestored = _loadChatHistory();
    unawaited(_loadDropped());
    unawaited(_loadContactsSince());
    // The radio's contact table is kept across restarts. Without it the
    // incremental token below asks the radio only for contacts changed since
    // the last session, and the app searched a table it had thrown away.
    _loadSyncedContacts();
    unawaited(_meshbook.load().then((_) => notifyListeners()));
    _loadBackgroundPref();
    _loadDefaultChannel();
    _loadFavorites();
    _loadKnown();
    _loadSuperseded();
    _loadTags();
    _loadCoverage();
    _loadBatteryHistory();
    _loadPowerSpecs();
    _loadTelemetryPollPref();
    _loadPeriodicAdvertPref();
    _loadPlaceInferPrefs();
    unawaited(_dmReadStore.load().then((_) {
      // Notify so any UI watching unread counts (Nodes badge, etc.)
      // re-renders once the persisted last-read timestamps are in.
      notifyListeners();
    }));
  }

  final DmReadStore _dmReadStore = DmReadStore();

  // --- "Known" nodes (R18) ---
  // Nodes we've had direct/attributable communication with (a
  // received DM, or a direct exchange) — drives the steady pulse on
  // the hyperlocal grid. Distinct from `favorites` (= "contacts",
  // rapid blink) and from the broader **fabric** of merely-seen
  // nodes.

  final Set<String> _known = <String>{};

  Set<String> get known => Set<String>.unmodifiable(_known);

  bool isKnown(String pubKeyHex) => _known.contains(pubKeyHex);

  Future<void> markKnown(String pubKeyHex) async {
    if (!_known.add(pubKeyHex)) return;
    notifyListeners();
    await KnownStore.save(_known);
  }

  Future<void> _loadKnown() async {
    final Set<String> v = await KnownStore.load();
    if (v.isEmpty) return;
    _known
      ..clear()
      ..addAll(v);
    notifyListeners();
  }

  // Keys the user reconciled away (a contact that returned under a new
  // key). Pruned from the fabric on ingest so the radio's lingering old
  // contact never reappears as a duplicate. See identityMatchFor / R56.
  final Set<String> _superseded = <String>{};

  bool isSuperseded(String pubKeyHex) => _superseded.contains(pubKeyHex);

  Future<void> _loadSuperseded() async {
    final Set<String> v = await SupersededStore.load();
    if (v.isEmpty) return;
    _superseded
      ..clear()
      ..addAll(v);
    // Drop any that are currently in the fabric (re-synced before load).
    for (final String k in v) {
      _nodes.remove(k);
      _contacts.remove(k);
    }
    notifyListeners();
  }

  // --- Favourites = "contacts" in the UX sense (R18 dependency) ---

  final Set<String> _favorites = <String>{};

  /// Read-only view of favourited node pubkey-hexes (the user's
  /// **contacts** in our UX sense; **fabric** = all seen).
  Set<String> get favorites => Set<String>.unmodifiable(_favorites);

  bool isFavorite(String pubKeyHex) => _favorites.contains(pubKeyHex);

  /// Toggle, persist, notify.
  Future<void> toggleFavorite(String pubKeyHex) async {
    if (!_favorites.add(pubKeyHex)) _favorites.remove(pubKeyHex);
    notifyListeners();
    await FavoriteStore.save(_favorites);
  }

  Future<void> _loadFavorites() async {
    final Set<String> v = await FavoriteStore.load();
    if (v.isEmpty) return;
    _favorites
      ..clear()
      ..addAll(v);
    notifyListeners();
  }

  // --- R28 — free-text tags per node ---
  //
  // Tags live alongside favourites but are orthogonal: a node can be
  // tagged "Mt. Hood Repeater" without being a favourite, and vice
  // versa. Multiple tags per node. Persisted as a single JSON blob.

  final Map<String, List<String>> _tags = <String, List<String>>{};

  /// Read-only view of every node's tag list. Empty list when the
  /// node has no tags (mirrors how `[]` is the natural "no tags"
  /// rendering).
  List<String> tagsFor(String pubKeyHex) =>
      List<String>.unmodifiable(_tags[pubKeyHex] ?? const <String>[]);

  /// Union of every tag ever attached anywhere, sorted for stable
  /// surface in autocomplete / "filter by tag" UI. Lowercased for
  /// dedup but original case preserved by picking the first variant.
  List<String> get allTags {
    final Map<String, String> seen = <String, String>{};
    for (final List<String> list in _tags.values) {
      for (final String t in list) {
        seen.putIfAbsent(t.toLowerCase(), () => t);
      }
    }
    final List<String> out = seen.values.toList()
      ..sort(
          (String a, String b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return out;
  }

  /// Add [tag] to [pubKeyHex]. Trimmed; case-insensitive dedup
  /// within the node (so "HAM" and "ham" can't coexist on the same
  /// node — the existing variant wins). No-op for empty input.
  Future<void> addTagTo(String pubKeyHex, String tag) async {
    final String t = tag.trim();
    if (t.isEmpty) return;
    final List<String> cur =
        List<String>.from(_tags[pubKeyHex] ?? const <String>[]);
    final String lower = t.toLowerCase();
    if (cur.any((String e) => e.toLowerCase() == lower)) return;
    cur.add(t);
    _tags[pubKeyHex] = cur;
    notifyListeners();
    await NodeTagsStore.save(_tags);
  }

  /// Remove [tag] from [pubKeyHex] (case-insensitive). No-op if not
  /// present. Drops the node from the map when its last tag goes so
  /// the persisted blob stays clean.
  Future<void> removeTagFrom(String pubKeyHex, String tag) async {
    final List<String>? cur = _tags[pubKeyHex];
    if (cur == null) return;
    final String lower = tag.trim().toLowerCase();
    final int before = cur.length;
    cur.removeWhere((String e) => e.toLowerCase() == lower);
    if (cur.length == before) return;
    if (cur.isEmpty) {
      _tags.remove(pubKeyHex);
    } else {
      _tags[pubKeyHex] = cur;
    }
    notifyListeners();
    await NodeTagsStore.save(_tags);
  }

  Future<void> _loadTags() async {
    final Map<String, List<String>> v = await NodeTagsStore.load();
    if (v.isEmpty) return;
    _tags
      ..clear()
      ..addAll(v);
    notifyListeners();
  }

  Future<void> _loadBackgroundPref() async {
    _bgKeepaliveEnabled = await BackgroundKeepalivePrefs.enabled();
    notifyListeners();
  }

  /// Whether the Android background keep-alive foreground service is
  /// enabled (R17 / U8). No-op on non-Android.
  bool get backgroundKeepaliveEnabled => _bgKeepaliveEnabled;

  /// Starts the keep-alive service, recording a refusal instead of letting it
  /// escape as an unhandled error.
  Future<void> _startKeepalive() async {
    try {
      await _keepalive.start();
      if (_keepaliveFailure != null) {
        _keepaliveFailure = null;
        notifyListeners();
      }
    } catch (error) {
      final String message = AppErrors.firstLine(error);
      AppErrors.record(error, StackTrace.current, where: 'keepalive');
      if (_keepaliveFailure != message) {
        _keepaliveFailure = message;
        notifyListeners();
      }
    }
  }

  Future<void> setBackgroundKeepaliveEnabled(bool v) async {
    _bgKeepaliveEnabled = v;
    notifyListeners();
    await BackgroundKeepalivePrefs.setEnabled(v);
    if (v && isReady) {
      await _startKeepalive();
    } else if (!v) {
      await _keepalive.stop();
    }
  }

  /// Completes when the restored history has been merged.
  ///
  /// Restoring is asynchronous because the store is a sealed file, so anything
  /// that needs the history to be there waits for this rather than for a
  /// guessed delay.
  Future<void> get historyRestored => _historyRestored;
  late final Future<void> _historyRestored;

  /// Restore persisted chat history (the protocol can't re-fetch it;
  /// the device queue is drained destructively). Loaded entries are
  /// older than anything received during the async gap, so they go
  /// at the front.
  Future<void> _loadChatHistory() async {
    final List<ChatMessage> hist = await ChatStore.load();
    if (hist.isEmpty) return;
    _messages.insertAll(0, hist);
    if (_messages.length > _messagesCap) {
      for (final ChatMessage m
          in _messages.getRange(0, _messages.length - _messagesCap)) {
        _noteDropped(m);
      }
      _messages.removeRange(0, _messages.length - _messagesCap);
    }
    _invalidateMessagesCache();
    notifyListeners();
  }

  /// Write the history soon, not necessarily now.
  ///
  /// `ChatStore.save` seals the whole kept history (up to 250 rows) through
  /// the Keystore and rewrites one file, and this used to run on every ingest
  /// *and* every delivery-state change — two full-history seals per message,
  /// which on a busy channel is the most expensive thing the app does per
  /// frame. A short window collapses a burst into one write; the dispose path
  /// flushes whatever is pending, so an app killed inside the window still
  /// loses nothing that was on screen.
  ///
  /// The debounce is the same shape the contact table already uses
  /// (`_contactsSaveTimer`), because two stores with two strategies is how a
  /// codebase grows a third.
  static const Duration _chatSaveWindow = Duration(milliseconds: 400);
  Timer? _chatSaveTimer;
  bool _chatSavePending = false;

  void _persistChat() {
    _chatSavePending = true;
    _chatSaveTimer ??= Timer(_chatSaveWindow, _flushChat);
  }

  void _flushChat() {
    _chatSaveTimer?.cancel();
    _chatSaveTimer = null;
    if (!_chatSavePending) return;
    _chatSavePending = false;
    unawaited(ChatStore.save(List<ChatMessage>.from(_messages)));
  }

  /// Merges rows from an exported file into the history, in memory and on
  /// disk, newest last. Returns how many rows were new.
  ///
  /// A restore is the one path that brings history back after the sealed key
  /// is gone, so it must survive what the live path never meets: rows whose
  /// ids already exist (a file exported twice), rows out of order, and more
  /// rows than the cap holds.
  Future<int> importHistory(List<ChatMessage> rows) async {
    final Set<String> known = <String>{for (final ChatMessage m in _messages) m.id};
    int added = 0;
    for (final ChatMessage m in rows) {
      if (known.add(m.id)) added++;
    }
    if (added == 0) return 0;
    final List<ChatMessage> merged = <ChatMessage>[
      ..._messages,
      for (final ChatMessage m in rows)
        if (!_messages.any((ChatMessage x) => x.id == m.id)) m,
    ]..sort((ChatMessage a, ChatMessage b) => a.at.compareTo(b.at));
    _messages
      ..clear()
      ..addAll(merged);
    if (_messages.length > _messagesCap) {
      for (final ChatMessage m
          in _messages.getRange(0, _messages.length - _messagesCap)) {
        _noteDropped(m);
      }
      _messages.removeRange(0, _messages.length - _messagesCap);
    }
    _invalidateMessagesCache();
    await ChatStore.save(List<ChatMessage>.from(_messages));
    ChatStore.unreadable.value = false;
    notifyListeners();
    return added;
  }

  /// R20 / U11 — delete a single message **locally**. The OTA copy
  /// has already been delivered; MeshCore has no recall semantic, so
  /// the UI must convey that the remote/other recipients still have
  /// the message. Returns true if a row matched.
  bool deleteMessageById(String id) {
    final int before = _messages.length;
    _messages.removeWhere((ChatMessage m) => m.id == id);
    if (_messages.length == before) return false;
    _invalidateMessagesCache();
    _persistChat();
    notifyListeners();
    return true;
  }

  /// Recent raw inbound frames (hex), newest last. Bounded ring buffer
  /// for the M6 interop capture workflow.
  final List<String> _capture = <String>[];
  static const int _captureCap = 256;
  StreamSubscription<Uint8List>? _rawSub;

  List<String> get captureLog => List<String>.unmodifiable(_capture);

  /// Most recent `0x88` RF-log frame hex, or null.
  String? get lastRfLogHex {
    for (int i = _capture.length - 1; i >= 0; i--) {
      if (_capture[i].startsWith('88')) return _capture[i];
    }
    return null;
  }

  /// Build a `grp_txt_capture` interop fixture (see
  /// `packages/meshcore/test/vectors/interop/SCHEMA.md`). Pass the
  /// captured `0x88` frame hex (default: [lastRfLogHex]).
  String exportGrpTxtFixture({
    required String pskHex,
    required String knownPlaintextUtf8,
    String channelName = 'Public',
    String description = '',
    String firmware = '',
    String? rfLogFrameHex,
  }) {
    final String? hex = rfLogFrameHex ?? lastRfLogHex;
    if (hex == null) {
      throw StateError('no 0x88 RF-log frame captured');
    }
    return const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'kind': 'grp_txt_capture',
      'description': description,
      'firmware': firmware,
      'channel_name': channelName,
      'psk_hex': pskHex,
      'known_plaintext_utf8': knownPlaintextUtf8,
      'rf_log_frame_hex': hex,
    });
  }

  final Future<MeshcoreTransport> Function() _transportFactory;
  final BackgroundKeepalive _keepalive;
  bool _bgKeepaliveEnabled = true; // default on (user-accepted)

  /// Why the keep-alive service could not start, or null while it is up.
  ///
  /// Android 12 and later refuse a background `startService`
  /// (`ForegroundServiceStartNotAllowedException`), and the refusal is silent
  /// unless it is caught: a process without the service is one Doze may kill,
  /// so the link and every buffered message go with it. The settings row shows
  /// this instead of leaving the user to infer it from missing messages.
  String? _keepaliveFailure;
  String? get keepaliveFailure => _keepaliveFailure;

  /// Whether the app is on screen. Timers that spend radio airtime check it.
  ///
  /// The battery, telemetry and self-info timers each cost a frame on the air,
  /// and a frame a minute for a number nobody can see is the kind of cost this
  /// product cannot carry on a shared band.
  bool _visible = true;
  bool get visible => _visible;

  /// Called from the lifecycle observer. Polling resumes with the app.
  void setVisible(bool v) {
    if (_visible == v) return;
    _visible = v;
    if (v) {
      if (isReady) {
        _startBatteryPolling();
        if (_telemPollEnabled) _startTelemetryPolling();
      }
    } else {
      _battTimer?.cancel();
      _telemPollTimer?.cancel();
    }
  }
  final MeshcoreConnection _connection;

  StreamSubscription<MeshcoreConnectionState>? _statesSub;
  StreamSubscription<MeshcoreInbound>? _inboundSub;
  MeshcoreTransport? _transport;

  final ReconnectPolicy _reconnect;
  final Future<void> Function(Duration) _delay;

  /// The app's own transmitter meter. Every outgoing frame is quoted against
  /// it before the write and charged after it, so the 1 % duty cycle is a
  /// measurement rather than a claim (APP-C5, register §2).
  final AirtimeMeter _airtime;

  /// The meter itself, for a test that needs to fill or inspect it without
  /// sending an hour of traffic.
  @visibleForTesting
  AirtimeMeter get airtimeMeterForTest => _airtime;

  /// Frames the meter refused, since launch. A refusal never reaches the radio.
  int _airtimeRefusals = 0;
  final LocationService _location;
  OwnLocation? _phoneFix;

  MeshcoreConnectionState _state = MeshcoreConnectionState.disconnected;
  MeshcoreInbound? _lastFrame;
  String? _error;
  Failure? _failure;
  BleMtuTooSmall? _mtuRefusal;
  bool _connecting = false;
  bool _manualDisconnect = false;
  bool _gaveUp = false;
  int _reconnectAttempt = 0;
  int _reconnectGen = 0;

  /// How long a teardown of the previous link is given, and how long a new
  /// transport is given, before the app stops waiting. See `link_acquire.dart`
  /// for where the numbers come from.
  final Duration _linkCloseTimeout;
  final Duration _linkOpenTimeout;

  /// Teardowns that outlasted [_linkCloseTimeout].
  ///
  /// Counted rather than treated as a failure: the app went on to open a new
  /// link, so nothing was refused. It is a fact about the phone's stack, and
  /// the reason a reconnect would otherwise look frozen.
  int _linkCloseTimeouts = 0;

  /// Handshake timeouts already reacted to, so one timeout is one immediate
  /// retry rather than a retry on every state notification.
  int _handshakeTimeoutsSeen = 0;

  MeshcoreConnectionState get state => _state;
  MeshcoreInbound? get lastFrame => _lastFrame;
  SelfInfo? get selfInfo => _connection.selfInfo;

  /// Handshakes this session has started. One per link open.
  int get handshakeAttempts => _connection.handshakeAttempts;

  /// Handshakes this session that ended without the radio's SELF_INFO.
  int get handshakeTimeouts => _connection.handshakeTimeouts;

  /// Link teardowns that outlasted the wait the app allows.
  int get linkCloseTimeouts => _linkCloseTimeouts;

  /// Our own node's 64-char pubkey hex (lower-case, no spaces), or
  /// `null` until `SelfInfo` arrives. Used to filter ourselves out
  /// of the fabric on /grid and the Nodes list (we don't want to
  /// DM ourselves) and to suppress the Message action in
  /// `NodeDetailSheet` when the tapped node IS us.
  String? get ownPubKeyHex {
    final SelfInfo? si = selfInfo;
    if (si == null) return null;
    final StringBuffer b = StringBuffer();
    for (final int byte in si.publicKey) {
      b.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return b.toString();
  }

  /// Own location resolved **device-first**, then phone-fallback.
  /// The MeshCore `SelfInfo` response carries a `latitude`/`longitude`
  /// pair which the device populates from its onboard GPS (or from a
  /// manually-pinned advert location). We treat exactly `(0, 0)` as
  /// unset — the canonical "no fix yet" sentinel the firmware
  /// initialises to.
  ///
  /// When the device reports unset (or hasn't responded yet), we
  /// fall back to a one-shot phone fix captured by
  /// [requestPhoneLocationFix] (Phase B / R22).
  ///
  /// Altitude has its own priority chain because SelfInfo doesn't
  /// carry altitude over the wire (lat/lon only). We prefer, in
  /// order:
  ///   1. Self-telemetry's GPS altitude (the device's own GPS chip,
  ///      via the CMD_SEND_TELEMETRY_REQ / 0x8B path — step 3).
  ///   2. The cached phone-GPS altitude (R22 one-shot or R36 auto-
  ///      publish hand-off).
  ///   3. None, in which case the elevation-profile view falls back
  ///      to the "?" band.
  OwnLocation? get ownLocation {
    final SelfInfo? si = selfInfo;
    final double? altFromTelemetry = selfTelemetry?.altitudeMeters;
    final double? altFromPhone = _phoneFix?.altitudeMeters;
    final double? altMerged = altFromTelemetry ?? altFromPhone;
    if (si != null &&
        !(si.latitude.abs() < 1e-9 && si.longitude.abs() < 1e-9)) {
      return OwnLocation(
        latitude: si.latitude,
        longitude: si.longitude,
        altitudeMeters: altMerged,
        source: OwnLocationSource.deviceReported,
      );
    }
    return _phoneFix;
  }

  /// The cached one-shot phone-GPS fix, if any. Cleared by
  /// [clearPhoneLocationFix]. Used as the fallback inside
  /// [ownLocation] when the device hasn't reported a fix.
  OwnLocation? get phoneLocationFix => _phoneFix;

  /// R22 / U13 — capture a single phone-GPS fix and cache it as
  /// our fallback own-location. The runtime permission is requested
  /// just-in-time by the [LocationService] when the user has not
  /// decided yet, so any caller works without asking first.
  /// Returns true on success; see [requestPhoneLocationFixOutcome]
  /// when the caller can explain a failure.
  Future<bool> requestPhoneLocationFix({
    Duration timeLimit = const Duration(seconds: 15),
  }) async =>
      (await requestPhoneLocationFixOutcome(timeLimit: timeLimit)).isOk;

  /// The same request, reporting *why* it produced no fix, so a screen
  /// can say "location permission needed" instead of "no GPS fix" when
  /// the two are completely different problems.
  Future<LocationOutcome> requestPhoneLocationFixOutcome({
    Duration timeLimit = const Duration(seconds: 15),
  }) async {
    final LocationOutcome outcome =
        await _location.requestFix(timeLimit: timeLimit);
    final PhoneFix? fix = outcome.fix;
    if (fix == null) return outcome;
    _phoneFix = OwnLocation(
      latitude: fix.latitude,
      longitude: fix.longitude,
      altitudeMeters: fix.altitudeMeters,
      source: OwnLocationSource.phoneFix,
    );
    // R25+1 — record into the trail. Phone fixes are a primary
    // source of ownLocation when the device GPS is off or stale.
    _trackOwnLocationForTrail();
    notifyListeners();
    return outcome;
  }

  /// Wipes the cached phone fix (so [ownLocation] reverts to
  /// device-reported, or null if neither is available).
  void clearPhoneLocationFix() {
    if (_phoneFix == null) return;
    _phoneFix = null;
    notifyListeners();
  }

  /// Cache an externally-acquired [PhoneFix] as our phone-side
  /// own-location. Used by `AutoPublishController` (R36) which
  /// already calls `_location.currentFix()` periodically — pumping
  /// every fix through here means `ownLocation.altitudeMeters` and
  /// the elevation-profile view stay live without a dedicated
  /// background subscription. Dedup is cheap because the same
  /// PhoneFix re-cached is a no-op aside from notifyListeners.
  void cachePhoneFix(PhoneFix fix) {
    _phoneFix = OwnLocation(
      latitude: fix.latitude,
      longitude: fix.longitude,
      altitudeMeters: fix.altitudeMeters,
      source: OwnLocationSource.phoneFix,
    );
    _trackOwnLocationForTrail();
    notifyListeners();
  }

  /// Great-circle distance (m) from our own location to the given
  /// point, or `null` when we don't have an own location yet.
  /// Lazy by construction — call this from a `ListView.builder`
  /// row and only visible rows pay the (microsecond) cost.
  double? distanceMetersTo(double targetLat, double targetLon) {
    final OwnLocation? own = ownLocation;
    if (own == null) return null;
    return geo.haversineMeters(
        own.latitude, own.longitude, targetLat, targetLon);
  }

  // --- R25+1 movement trail ---------------------------------------
  //
  // Rolling in-memory record of our own GPS fixes, used by the
  // equal-grid view to draw a "where I've been" polyline. Trail
  // grows passively as new ownLocation samples arrive (called from
  // _trackOwnLocationForTrail in the inbound listener); deduped by
  // movement so a stationary device doesn't fill the buffer with
  // identical points.
  //
  // Buffer is capped to keep the polyline render cheap and the
  // memory footprint trivial — at the default cap of 60 points and
  // 25 m dedup threshold that's roughly 1.5 km of recent path.

  static const int _trailCap = 60;
  static const double _trailMinMoveMeters = 25.0;
  final List<({double latitude, double longitude, int unixSec})>
      _ownTrail =
      <({double latitude, double longitude, int unixSec})>[];

  /// Read-only view of the most-recent own-location samples, oldest
  /// first. Empty until at least one ownLocation has been resolved.
  List<({double latitude, double longitude, int unixSec})>
      get ownTrail => List<
              ({
                double latitude,
                double longitude,
                int unixSec
              })>.unmodifiable(_ownTrail);

  /// Append the current ownLocation to [_ownTrail] if it has moved
  /// > [_trailMinMoveMeters] from the last sample. Safe to call on
  /// every inbound frame; cheap when no movement happened.
  void _trackOwnLocationForTrail() {
    final OwnLocation? own = ownLocation;
    if (own == null) return;
    if (_ownTrail.isNotEmpty) {
      final last = _ownTrail.last;
      final double d = geo.haversineMeters(
          last.latitude, last.longitude, own.latitude, own.longitude);
      if (d < _trailMinMoveMeters) return;
    }
    _ownTrail.add((
      latitude: own.latitude,
      longitude: own.longitude,
      unixSec: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    ));
    while (_ownTrail.length > _trailCap) {
      _ownTrail.removeAt(0);
    }
    // F8 — every sampled own-location is a "the mesh reaches here"
    // observation, since the trail only updates while we have a
    // working link to the device.
    _recordCoverage(own.latitude, own.longitude);
  }

  // --- F8 coverage map -------------------------------------------
  //
  // Persistent record of cells where we've observed mesh activity.
  // Each inbound frame contributes a cell (we know the mesh exists
  // somewhere reachable while we're online) and each known peer's
  // lat/lon contributes a cell (the mesh extends to where they are).
  // Stored as `Map<cellKey, lastObservedUnix>` so the FabricSurveyView
  // can fade older cells.

  final Map<String, int> _coverage = <String, int>{};
  bool _coverageDirty = false;
  Timer? _coverageSaveTimer;

  /// Read-only snapshot of observed coverage cells, keyed by
  /// `latBucket,lonBucket` strings (see [CoverageStore.cellKey]).
  /// Each value is the most-recent UNIX-second timestamp the cell
  /// was observed.
  Map<String, int> get coverageCells =>
      Map<String, int>.unmodifiable(_coverage);

  Future<void> _loadCoverage() async {
    final Map<String, int> v = await CoverageStore.load();
    if (v.isEmpty) return;
    _coverage
      ..clear()
      ..addAll(v);
    notifyListeners();
  }

  /// Wipe the coverage record. Used by tests + a "reset coverage"
  /// affordance in the FabricSurveyView's overflow menu.
  Future<void> resetCoverage() async {
    _coverage.clear();
    _coverageDirty = false;
    _coverageSaveTimer?.cancel();
    await CoverageStore.clear();
    notifyListeners();
  }

  /// Record a single observation. Bucketed by [CoverageStore.cellDeg];
  /// repeated calls on the same cell within a second are a no-op
  /// (timestamp resolution). Persistence is batched on a 5-second
  /// timer so a long drive doesn't pound shared_preferences.
  void _recordCoverage(double lat, double lon) {
    // Guard: an advert can carry a malformed i32 lat/lon that decodes
    // to an out-of-Earth-range double (anything up to ±2147°). Without
    // this filter the bogus value gets persisted as a coverage cell
    // and trips flutter_map's polygon assertion next time the survey
    // view renders (it expects latitudes in ±90 / longitudes in ±180).
    if (!lat.isFinite || !lon.isFinite) return;
    if (lat.abs() > 90.0 || lon.abs() > 180.0) return;
    // (0,0) is the unset sentinel (Null Island) — never a real
    // observation. Drop it so the coverage quilt doesn't grow a
    // phantom cell off West Africa.
    if (lat.abs() < 1e-9 && lon.abs() < 1e-9) return;
    final ({int latBucket, int lonBucket}) b =
        CoverageStore.bucketFor(lat, lon);
    final String key = CoverageStore.cellKey(b.latBucket, b.lonBucket);
    final int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (_coverage[key] == now) return;
    _coverage[key] = now;
    while (_coverage.length > CoverageStore.maxCells) {
      // Drop the oldest entry by min-timestamp scan. O(N) per
      // eviction but only happens when we overflow the cap.
      String? oldestKey;
      int oldestTs = 1 << 62;
      _coverage.forEach((String k, int t) {
        if (t < oldestTs) {
          oldestTs = t;
          oldestKey = k;
        }
      });
      if (oldestKey == null) break;
      _coverage.remove(oldestKey);
    }
    _coverageDirty = true;
    _coverageSaveTimer ??= Timer(
        const Duration(seconds: 5), _flushCoveragePersist);
  }

  Future<void> _flushCoveragePersist() async {
    _coverageSaveTimer = null;
    if (!_coverageDirty) return;
    _coverageDirty = false;
    await CoverageStore.save(_coverage);
  }

  /// Spatial-aware "is this node nearby?" classification used by the
  /// IN RANGE / FAR badges. See [NodeProximity] for the band
  /// definitions. The temporal-only `recentlyHeard` fallback only
  /// fires when neither side has GPS — once we have both, distance
  /// alone decides.
  ///
  /// Thresholds picked from LoRa practical-reach experience: 10 km
  /// is comfortably "in your area" even on narrow-band tuples; 50 km
  /// is well beyond a typical direct link, so labelling those as
  /// FAR is informative.
  static const double _nearThresholdMeters = 10000;
  static const double _farThresholdMeters = 50000;

  NodeProximity proximityFor(DiscoveredNode n) {
    if (n.hasLocation) {
      final double? d = distanceMetersTo(n.latitude!, n.longitude!);
      if (d != null) {
        if (d < _nearThresholdMeters) return NodeProximity.near;
        if (d > _farThresholdMeters) return NodeProximity.far;
        return NodeProximity.mid;
      }
    }
    // No spatial info — fall back to recency. Calling
    // n.recentlyHeard avoids the deprecated alias warning.
    if (n.recentlyHeard) return NodeProximity.recent;
    return NodeProximity.unknown;
  }
  String? get error => _error;

  /// The last link failure as a translated cause (APP-N2). Null when the
  /// last attempt did not fail, or when the failure was not a link one.
  Failure? get failure => _failure;
  bool get isConnecting => _connecting;
  bool get isReady => _state == MeshcoreConnectionState.ready;

  /// The link's negotiated ATT MTU, when the transport reports one.
  ///
  /// A link below [MeshcoreBle.requiredMtu] cannot carry the firmware's
  /// largest frame in one notification. [BleConnector] refuses such a link on
  /// Android, so this is normally the value of a link that is good enough —
  /// shown because it is the number that explains a lost frame when one goes
  /// missing anyway.
  int? get mtu => _connection.mtu;

  /// Set when the last connect attempt was refused for a too-small MTU.
  /// Typed rather than a string so the screen can say it in the user's
  /// language, with the number the link actually got.
  BleMtuTooSmall? get mtuRefusal => _mtuRefusal;

  /// Notifications that ended mid-frame (see [MeshcoreConnection
  /// .truncatedFrames]).
  int get truncatedFrames => _connection.truncatedFrames;

  /// Frames that decoded with bytes left over (see [MeshcoreConnection
  /// .trailingBytesFrames]).
  int get trailingBytesFrames => _connection.trailingBytesFrames;

  /// Notifications that arrived with no bytes in them.
  int get emptyFrames => _connection.emptyFrames;

  /// Number of reconnect attempts since the last successful link.
  int get reconnectAttempt => _reconnectAttempt;

  /// True once the reconnect policy has exhausted [ReconnectPolicy
  /// .maxAttempts] without recovering.
  bool get gaveUp => _gaveUp;

  /// The radio's own key as it was the last time the app accepted it, and
  /// whether the link now answers with a different one. A reflash or a
  /// replacement changes the key while the BLE identity can survive, so this
  /// is the only signal that the history on screen belongs to another node
  /// (D8.7). Nothing is migrated automatically: the user says which it is.
  String? get previousRadioKey => _previousRadioKey;
  bool get radioChanged => _radioChanged;
  String? _previousRadioKey;
  bool _radioChanged = false;

  /// The connected radio is the one the user means: record its key and stop
  /// asking. The diagnostics line is what offers this.
  Future<void> acceptRadioIdentity() async {
    final String? own = ownPubKeyHex;
    if (own == null) return;
    await RadioIdentityStore.save(own);
    _previousRadioKey = own;
    _radioChanged = false;
    notifyListeners();
  }

  /// Compares the connected radio's key with the one on record. Silent the
  /// first time (a fresh install records what it sees), and silent when the
  /// radio reports an all-zero key, which means it has not been provisioned.
  Future<void> _checkRadioIdentity() async {
    final String? own = ownPubKeyHex;
    if (own == null || own == '') return;
    if (RegExp(r'^0+$').hasMatch(own)) return;
    final String? stored = await RadioIdentityStore.read();
    if (stored == null) {
      await RadioIdentityStore.save(own);
      _previousRadioKey = own;
      _radioChanged = false;
      notifyListeners();
      return;
    }
    if (stored == own) {
      _previousRadioKey = stored;
      _radioChanged = false;
      notifyListeners();
      return;
    }
    _previousRadioKey = stored;
    _radioChanged = true;
    notifyListeners();
  }

  void _maybeScheduleReconnect({bool immediate = false}) {
    if (_manualDisconnect || _connecting) return;
    final int next = _reconnectAttempt + 1;
    if (!_reconnect.shouldRetry(next)) {
      if (!_gaveUp) {
        _gaveUp = true;
        notifyListeners();
      }
      return;
    }
    _reconnectAttempt = next;
    final int gen = _reconnectGen;
    final Duration d =
        immediate ? Duration.zero : _reconnect.delayForAttempt(next);
    unawaited(_delay(d).then((_) {
      // Drop stale schedules (a newer connect/disconnect superseded us).
      if (gen != _reconnectGen || _manualDisconnect || _connecting) return;
      if (_state == MeshcoreConnectionState.ready) return;
      unawaited(connect(isRetry: true));
    }));
  }

  /// Acquire a transport and start the handshake. Safe to call again
  /// after a failure. A user-initiated call ([isRetry] false) clears
  /// the manual-disconnect latch and resets the backoff.
  Future<void> connect({bool isRetry = false}) async {
    if (_connecting) return;
    _connecting = true;
    if (!isRetry) {
      _manualDisconnect = false;
      _gaveUp = false;
      _reconnectAttempt = 0;
      _reconnectGen++;
    }
    _error = null;
    _failure = null;
    _mtuRefusal = null;
    notifyListeners();
    Object? failure;
    try {
      // Both waits are bounded. An unbounded close held `_connecting` set
      // forever and left the screen reading "handshaking" with nothing behind
      // it; a timed-out close is recorded and the app goes on to open a new
      // link, because the old transport is unreachable either way.
      final MeshcoreTransport? previous = _transport;
      if (previous != null) {
        try {
          await previous.close().timeout(_linkCloseTimeout);
        } on TimeoutException {
          _linkCloseTimeouts++;
          notifyListeners();
        }
      }
      final MeshcoreTransport t =
          await _transportFactory().timeout(_linkOpenTimeout);
      _transport = t;
      _connection.attach(t);
      // Success: the handshake now drives state via the connection
      // stream. Do NOT inspect _state here — that transition is
      // delivered asynchronously and would still read `failed`.
    } on TimeoutException {
      // The factory did not resolve inside the wait. Typed rather than left
      // as a raw timeout so the screen can name the half that stalled; a
      // TimeoutException from inside the connector lands here too, and the
      // copy holds for both.
      failure = LinkAcquireTimeout(LinkStage.open, _linkOpenTimeout);
      _error = failure.toString();
      _failure = Failure.from(failure);
      _state = MeshcoreConnectionState.failed;
    } catch (e) {
      failure = e;
      // An MTU refusal is not a link fault and not retryable by backoff: the
      // same radio will negotiate the same MTU. Keep it typed so the screen
      // can explain it, and do not let the reconnect policy spin on it.
      _mtuRefusal = e is BleMtuTooSmall ? e : null;
      _error = e.toString();
      _failure = Failure.from(e);
      _state = MeshcoreConnectionState.failed;
    }
    _connecting = false;
    notifyListeners();
    // Transport acquisition failed (the connection stream never sees
    // this, so drive the backoff from here). An MTU refusal is the one
    // failure backoff cannot fix: the same radio negotiates the same value,
    // so retrying is only five more identical failures.
    if (failure != null && _mtuRefusal == null) _maybeScheduleReconnect();
  }

  // --- Airtime metering ---

  /// What the meter has charged in the last hour.
  Duration get airtimeSpent => _airtime.spent;

  /// The policy's allowance, or null when the policy has no cap.
  Duration? get airtimeBudget => _airtime.budget;

  /// Room left in the window, or null when there is no cap.
  Duration? get airtimeRemaining => _airtime.remaining;

  AirtimePolicy get airtimePolicy => _airtime.policy;

  /// Frames the meter refused since launch. A refusal is not a radio error:
  /// the frame never left the phone.
  int get airtimeRefusals => _airtimeRefusals;

  /// Whether a frame of [bytes] would fit inside the current window.
  bool canSpendAirtime(int bytes) =>
      _airtime.quote(_airtimeEstimator.forBytes(bytes)).allowed;

  /// Changes the policy and persists it. The meter keeps its history: what has
  /// already been spent is a fact about the hour, not about the policy.
  Future<void> setAirtimePolicy(AirtimePolicy value) async {
    if (_airtime.policy == value) return;
    _airtime.policy = value;
    notifyListeners();
    await AirtimePolicyPrefs.setPolicy(value);
  }

  /// The exact time-on-air estimate for the radio that reports it, or the
  /// documented flat figure until the first self-info arrives.
  AirtimeEstimator get _airtimeEstimator {
    final SelfInfo? si = selfInfo;
    if (si != null) {
      final AirtimeEstimator? exact = loraEstimator(
        bandwidthKhz: si.bandwidthKhz,
        spreadingFactor: si.spreadingFactor,
        codingRate: si.codingRate,
      );
      if (exact != null) return exact;
    }
    return airtimeEstimatorFor(null);
  }

  Future<void> _loadAirtimePolicy() async {
    try {
      _airtime.policy = await AirtimePolicyPrefs.policy();
      notifyListeners();
    } catch (_) {
      // No preferences backend (a test, a host without the plugin): the
      // constructor's fallback is already the safe policy.
    }
  }

  /// Send a raw command frame (e.g. from [MeshcoreFrameCodec]).
  ///
  /// This is the single write path for every outgoing frame (text, DM,
  /// datagram, media chunk, tool request, advert, radio config), so it is
  /// where the app's own duty cycle is charged. A frame that does not fit the
  /// rolling window is refused *before* the write with [AirtimeRefused]; a
  /// write that throws is refunded, because nothing left the phone.
  /// [gated] marks the frames that are the user's traffic — text, DMs,
  /// datagrams, adverts, tool requests. Those are what a duty cycle exists to
  /// bound, and they are refused when the window is full. Link maintenance
  /// (the handshake, the sync drain, a channel probe, a config write) always
  /// goes: refusing it would leave an exhausted meter unable to reconnect or
  /// be reconfigured, which is a worse failure than spending a few dozen
  /// bytes. Everything is charged either way, so the figure stays honest.
  Future<void> send(Uint8List frame, {bool gated = false}) async {
    final Duration cost = _airtimeEstimator.forBytes(frame.length);
    if (gated && !_airtime.quote(cost).allowed) {
      _airtimeRefusals++;
      notifyListeners();
      throw AirtimeRefused(needed: cost, budget: _airtime.budget);
    }
    _airtime.charge(cost);
    try {
      await _connection.sendCommand(frame);
    } catch (_) {
      _airtime.refund(cost);
      rethrow;
    }
    _notifyAirtime();
  }

  /// A meter line does not need a rebuild per frame. One per second keeps the
  /// figure live without turning a burst into a wall of notifications.
  DateTime? _airtimeNotifiedAt;

  void _notifyAirtime() {
    final DateTime now = DateTime.now();
    final DateTime? last = _airtimeNotifiedAt;
    if (last != null && now.difference(last) < const Duration(seconds: 1)) {
      return;
    }
    _airtimeNotifiedAt = now;
    notifyListeners();
  }

  // --- R60 Tools seams ---

  /// Every decoded inbound frame (broadcast). Tools match their own
  /// replies here; the controller keeps processing them as usual.
  Stream<MeshcoreInbound> get inboundFrames => _connection.inbound;

  /// Marker id in [_ledger] for a tool request that will be answered
  /// by RESP_CODE_SENT. Without it, that SENT would be taken as the
  /// confirmation of whichever chat message is oldest in flight.
  static const String _toolSendMarker = '\u0000tool';

  /// Marker id in [_ledger] for a self-advert, which the firmware
  /// answers with RESP_CODE_OK (`MyMesh.cpp` CMD_SEND_SELF_ADVERT).
  /// Without it that OK would confirm a channel message that is still
  /// waiting for its own OK.
  static const String _advertSendMarker = '\u0000advert';

  /// Send a tool's remote request (status / trace / telemetry) — one
  /// the radio answers with RESP_CODE_SENT — without disturbing chat
  /// delivery tracking. If the radio answers ERR instead, call
  /// [abandonToolRequest].
  Future<void> sendToolRequest(Uint8List frame) async {
    _registerMarker(_toolSendMarker, CommandAnswer.sent);
    try {
      await send(frame, gated: true);
    } catch (_) {
      abandonToolRequest();
      rethrow;
    }
  }

  /// The radio refused a [sendToolRequest] (ERR) or never answered:
  /// drop its marker so the next SENT goes to the right message.
  void abandonToolRequest() => _dropPending(_toolSendMarker);

  /// Marker id in [_ledger] for a channel datagram (`CMD_SEND_CHANNEL_DATA`),
  /// which the firmware answers with a bare OK/ERR (`MyMesh.cpp:1158-1189`).
  static const String _channelDataMarker = '\u0000chdata';

  /// The datagram send currently waiting for its OK/ERR, if any. Sends are
  /// serialised ([_channelDataTail]) because the answer carries no tag.
  Completer<MeshcoreInbound>? _channelDataAnswer;
  Future<void> _channelDataTail = Future<void>.value();

  /// How long a datagram send waits for the radio's answer. Overridable so
  /// tests do not spend five seconds proving a timeout.
  final Duration? _channelDataTimeoutOverride;

  static const Duration _channelDataTimeout = Duration(seconds: 5);

  /// Send [blob] on [channelIdx] as a channel datagram (`0x3E`).
  ///
  /// The blob is a payload for whatever layer owns [dataType]; this method
  /// only carries it. Sends are serialised: the radio's answer has no tag,
  /// so two in flight could not be told apart.
  Future<ChannelDataSendResult> sendChannelData({
    required int channelIdx,
    required int dataType,
    required List<int> blob,
    int pathLen = kPathLenFlood,
    List<int> path = const <int>[],
  }) {
    final Future<ChannelDataSendResult> result =
        _channelDataTail.then((_) => _sendChannelData(
              channelIdx: channelIdx,
              dataType: dataType,
              blob: blob,
              pathLen: pathLen,
              path: path,
            ));
    _channelDataTail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<ChannelDataSendResult> _sendChannelData({
    required int channelIdx,
    required int dataType,
    required List<int> blob,
    required int pathLen,
    required List<int> path,
  }) async {
    if (!isReady) {
      return const ChannelDataSendResult(ChannelDataSendStatus.notReady);
    }
    final Uint8List frame;
    try {
      frame = MeshcoreFrameCodec.sendChannelData(
        channelIdx: channelIdx,
        dataType: dataType,
        blob: blob,
        pathLen: pathLen,
        path: path,
      );
    } on ChannelDataException catch (e) {
      return ChannelDataSendResult(
        ChannelDataSendStatus.refusedLocally,
        refusal: e.refusal,
      );
    }
    final Completer<MeshcoreInbound> answer = Completer<MeshcoreInbound>();
    _channelDataAnswer = answer;
    _registerMarker(_channelDataMarker, CommandAnswer.ok);
    try {
      await send(frame, gated: true);
      final MeshcoreInbound reply = await answer.future
          .timeout(_channelDataTimeoutOverride ?? _channelDataTimeout);
      if (reply is OkFrame) {
        return const ChannelDataSendResult(ChannelDataSendStatus.accepted);
      }
      return ChannelDataSendResult(
        ChannelDataSendStatus.refusedByRadio,
        errorCode: (reply as ErrorFrame).code,
      );
    } on TimeoutException {
      _dropPending(_channelDataMarker);
      // The frame was written, so the radio may have transmitted it.
      return const ChannelDataSendResult(ChannelDataSendStatus.noAnswer);
    } on AirtimeRefused {
      _dropPending(_channelDataMarker);
      return const ChannelDataSendResult(
          ChannelDataSendStatus.refusedAirtime);
    } catch (_) {
      _dropPending(_channelDataMarker);
      _emitTaskError('sendChannelData');
      return const ChannelDataSendResult(ChannelDataSendStatus.notReady);
    } finally {
      if (identical(_channelDataAnswer, answer)) _channelDataAnswer = null;
    }
  }

  /// Marker id in [_ledger] for a raw-data send (`CMD_SEND_RAW_DATA`),
  /// which the firmware answers with a bare OK or ERR, never SENT
  /// (`MyMesh.cpp` CMD_SEND_RAW_DATA: `writeOKFrame()` / `writeErrFrame()`).
  /// Without it that OK would confirm a channel message still waiting for
  /// its own.
  static const String _rawSendMarker = '\u0000raw';

  /// Send one raw-data command and register its OK/ERR so neither is
  /// credited to a chat message. The caller reads the answer from
  /// [inboundFrames]; if none arrives, call [abandonRawSend].
  /// The record's answer: the OK or ERR the ledger credited to *this* send.
  ///
  /// Returning it is the point. The caller used to watch every inbound
  /// OK/ERR itself, which credited one answer twice — once to the chat
  /// message the ledger had claimed and once to the raw send waiting beside
  /// it. An answer now belongs to whoever claimed it.
  Future<MeshcoreInbound> sendRawCommand(Uint8List frame) async {
    final Completer<MeshcoreInbound> answer = Completer<MeshcoreInbound>();
    _rawAnswer = answer;
    _registerMarker(_rawSendMarker, CommandAnswer.ok);
    try {
      await send(frame, gated: true);
    } catch (_) {
      abandonRawSend();
      rethrow;
    }
    return answer.future;
  }

  Completer<MeshcoreInbound>? _rawAnswer;

  void _completeRawSend(MeshcoreInbound f) {
    final Completer<MeshcoreInbound>? c = _rawAnswer;
    _rawAnswer = null;
    if (c != null && !c.isCompleted) c.complete(f);
  }

  /// No answer came for a [sendRawCommand]: drop its marker so the next OK
  /// goes to the right message, and forget the completer nobody can satisfy.
  void abandonRawSend() {
    _rawAnswer = null;
    _dropPending(_rawSendMarker);
  }

  // --- Radio configuration: the radio's own answer, attributed ---

  /// Marker id in [_ledger] for a radio-config command (frequency, bandwidth,
  /// TX power, path-hash size) waiting for its bare `OK`/`ERR`.
  static const String _configMarker = '\u0000cfg';
  static const String _contactAddMarker = '\u0000cadd';

  /// How long a config write waits for the radio's answer.
  static const Duration _configAnswerTimeout = Duration(seconds: 5);
  final Duration? _radioConfigTimeoutOverride;

  Completer<RadioAnswer>? _configAnswer;

  /// The command [_configAnswer] belongs to, so its reply can teach the
  /// capability record which command the radio just accepted or refused.
  MeshcoreCommand? _configCommand;

  /// One config write at a time: the answer carries no tag, so two in flight
  /// could not be told apart.
  Future<void> _configTail = Future<void>.value();

  /// What this connected radio has been shown to support. A capability is a
  /// fact about the radio (D8.15), so it lives with the link.
  final RadioCapabilities _capabilities = RadioCapabilities();
  RadioCapabilities get capabilities => _capabilities;

  /// Send one radio-config frame and return the radio's own answer.
  ///
  /// [send] returns when the bytes were accepted, which is how the app used
  /// to report "sent" for a command the radio had refused. The three setters
  /// answer with a bare `OK`/`ERR(ERR_CODE_ILLEGAL_ARG)`
  /// (`MyMesh.cpp:1386-1478`), so the answer is attributed through the ledger
  /// like any other untagged reply.
  Future<RadioAnswer> sendRadioConfig(Uint8List frame) {
    final Future<RadioAnswer> result =
        _configTail.then((_) => _sendRadioConfigOnce(frame));
    _configTail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<RadioAnswer> _sendRadioConfigOnce(Uint8List frame) async {
    if (!isReady || frame.isEmpty) return const RadioAnswer.silent();
    final MeshcoreCommand command = MeshcoreCommand(frame[0]);
    // Refuse locally what this radio already said it cannot do. Unknown is
    // not refused: the command is sent and the reply teaches the state.
    if (_capabilities.stateOf(command) == CapabilityState.absent) {
      return RadioAnswer.refused(MeshcoreErrorCode.unsupportedCmd.code);
    }
    final Completer<RadioAnswer> answer = Completer<RadioAnswer>();
    _configAnswer = answer;
    _configCommand = command;
    _registerMarker(_configMarker, CommandAnswer.ok);
    try {
      await send(frame);
      return await answer.future
          .timeout(_radioConfigTimeoutOverride ?? _configAnswerTimeout);
    } on TimeoutException {
      _dropPending(_configMarker);
      return const RadioAnswer.silent();
    } catch (_) {
      _dropPending(_configMarker);
      _emitTaskError('sendRadioConfig');
      return const RadioAnswer.silent();
    } finally {
      if (identical(_configAnswer, answer)) {
        _configAnswer = null;
        _configCommand = null;
      }
    }
  }

  void _completeRadioConfig(RadioAnswer answer) {
    final MeshcoreCommand? command = _configCommand;
    if (command != null) {
      if (answer.isAccepted) {
        _capabilities.observeReply(command);
      } else if (answer.status == RadioAnswerStatus.refused) {
        final int? code = answer.errorCode;
        if (code != null) _capabilities.observeError(command, code);
      }
    }
    final Completer<RadioAnswer>? c = _configAnswer;
    if (c != null && !c.isCompleted) c.complete(answer);
  }

  /// Ask the radio for its device info again (the path-hash size and the
  /// firmware build live there). Used after applying radio parameters, where
  /// the reply is also the evidence that the write took effect.
  void refreshDeviceInfo() => _requestDeviceInfo();

  int _backgroundHolds = 0;

  /// The firmware keeps ONE pending remote request; each new one
  /// clears the last. While a tool measures, hold the background
  /// telemetry poller so it cannot steal the slot. Nested holds count;
  /// pair every `true` with a `false`.
  void holdBackgroundRequests(bool hold) {
    _backgroundHolds = hold
        ? _backgroundHolds + 1
        : (_backgroundHolds - 1).clamp(0, 1 << 20);
  }

  bool get backgroundRequestsHeld => _backgroundHolds > 0;

  // --- Discovery: nodes "in the area" (contacts + adverts) ---

  final Map<String, DiscoveredNode> _nodes = <String, DiscoveredNode>{};

  /// Discovered nodes, most-recently-heard first.
  List<DiscoveredNode> get nodes {
    final List<DiscoveredNode> v = _nodes.values.toList()
      ..sort((DiscoveredNode a, DiscoveredNode b) =>
          b.lastHeardUnix.compareTo(a.lastHeardUnix));
    return v;
  }

  /// R49 — resolved topology chain for a peer, ordered from the
  /// first hop *from us* to the last hop *before the peer*. Each
  /// entry is the known repeater whose pubkey starts with the
  /// matching first-byte hash from `outPathHashes`.
  ///
  /// Returns:
  /// - **`[]` (empty)** when the peer is a known direct neighbour
  ///   (contact-synced with `out_path_len == 0`).
  /// - **`List<DiscoveredNode>`** when every hash resolved to a
  ///   single known repeater.
  /// - **`null`** when **any** of:
  ///   - the peer's `outPathHashes` is `null` (advert-only-heard,
  ///     no path info available — the common case);
  ///   - a hop is unresolved (no repeater heard with that first
  ///     byte);
  ///   - a hop is ambiguous (two known repeaters share the same
  ///     first byte).
  ///
  /// Caller decides whether to fall back to a direct line.
  ///
  /// Resolver scope: only nodes of `type == 2` (repeater) are
  /// candidates, so a chat node that happens to share a first byte
  /// with a repeater hash won't be falsely matched.
  List<DiscoveredNode>? topologyChainFor(String pubKeyHex) {
    final DiscoveredNode? peer = _nodes[pubKeyHex.toLowerCase()];
    if (peer == null) return null;
    final List<int>? hashes = peer.outPathHashes;
    if (hashes == null) return null; // advert-only — no path info
    if (hashes.isEmpty) return const <DiscoveredNode>[];

    // Build a hash → repeater map. O(n) per call — n is small (tens
    // to low hundreds in practice). Tracks duplicates to flag
    // ambiguous hops.
    final Map<int, DiscoveredNode> byFirstByte = <int, DiscoveredNode>{};
    final Set<int> ambiguous = <int>{};
    for (final DiscoveredNode n in _nodes.values) {
      if (n.type != kAdvTypeRepeater) continue;
      if (n.pubKeyHex.length < 2) continue;
      final int firstByte =
          int.parse(n.pubKeyHex.substring(0, 2), radix: 16);
      if (byFirstByte.containsKey(firstByte)) {
        ambiguous.add(firstByte);
      } else {
        byFirstByte[firstByte] = n;
      }
    }

    final List<DiscoveredNode> chain = <DiscoveredNode>[];
    for (final int hash in hashes) {
      if (ambiguous.contains(hash)) return null; // collision
      final DiscoveredNode? hop = byFirstByte[hash];
      if (hop == null) return null; // unresolved
      chain.add(hop);
    }
    return List<DiscoveredNode>.unmodifiable(chain);
  }

  // --- Recent activity feed (Dashboard) ---

  final List<MeshEvent> _events = <MeshEvent>[];
  static const int _eventsCap = 40;

  /// Recent decoded events, newest first.
  List<MeshEvent> get recentEvents => _events.reversed.toList();

  void _logEvent(MeshcoreInbound f) {
    MeshEvent? ev;
    if (f is AdvertFrame) {
      final Advert a = f.advert;
      ev = MeshEvent(kind: MeshEventKind.advert, args: <String, String>{
        'name': a.name ?? _hex(a.publicKey).substring(0, 8),
      });
    } else if (f is ChannelMessageFrame) {
      final ChannelMessage m = f.message;
      ev = MeshEvent(
          kind: MeshEventKind.channelMsg,
          args: <String, String>{
            'channel': '${m.channelIdx}',
            'text': m.text,
          });
    } else if (f is ContactMessageFrame) {
      ev = MeshEvent(kind: MeshEventKind.dm, args: <String, String>{
        'text': f.message.text,
      });
    } else if (f is ContactFrame) {
      ev = MeshEvent(kind: MeshEventKind.contact, args: <String, String>{
        'name': f.contact.name,
      });
    } else if (f is OneKeyRejectedFrame) {
      // The radio dropped a message from a key it does not hold a contact for
      // (`PUSH_CODE_ONE_KEY_DM_REJECTED`, 0x91). Without this line the sender
      // simply never appears and the reader cannot tell a stranger's attempt
      // from silence, which is the one thing a busy mesh should say out loud.
      ev = MeshEvent(
          kind: MeshEventKind.oneKeyRejected,
          args: <String, String>{
            'key': _hex(f.publicKey).substring(0, 8),
          });
    } else if (f is DisabledFrame) {
      ev = MeshEvent(kind: MeshEventKind.radioRefused);
    } else if (f is BatteryStorageFrame) {
      ev = MeshEvent(kind: MeshEventKind.battery, args: <String, String>{
        'volts': f.battery.batteryVolts.toStringAsFixed(2),
      });
    } else if (f is ErrorFrame) {
      // Squelch the recent-activity surface for ERRs we know we
      // caused with a probing setCustomVar (e.g. writing
      // `gps_interval` on firmware where the sensors module
      // doesn't accept it returns ILLEGAL_ARG). Logging-only
      // — the codec error is still observable to anyone watching
      // the raw inbound stream.
      if (_squelchNextDeviceError > 0) {
        _squelchNextDeviceError--;
        meshLog('meshcore',
            'squelching expected device ERR code=${f.code}');
        return;
      }
      ev = MeshEvent(
          kind: MeshEventKind.deviceError,
          args: <String, String>{
            'code': '${f.code ?? '?'}',
            'reason': deviceErrorReason(f.code),
          });
      // Surface notable errors to the UI (not just the activity feed) so
      // the user understands a silent failure — most importantly a full
      // contact table, which blocks adding a re-homed key.
      if (f.code == 3) _emitTaskError('contactsFull');
    } else if (f is CurrentTimeFrame) {
      final int skew = _deviceClockOffsetSec.abs();
      ev = skew > 5
          ? MeshEvent(
              kind: MeshEventKind.deviceClockSkew,
              args: <String, String>{
                'seconds': '$_deviceClockOffsetSec',
              })
          : MeshEvent(kind: MeshEventKind.deviceClockSynced);
    } else if (f is MsgSentFrame) {
      ev = MeshEvent(kind: MeshEventKind.msgSent, args: <String, String>{
        'ack': '${f.sent.expectedAck}',
      });
    } else if (f is DeviceInfoFrame) {
      ev = MeshEvent(
          kind: MeshEventKind.deviceInfo,
          args: <String, String>{'version': f.info.firmwareVersion});
    } else if (f is SelfInfoFrame) {
      final SelfInfo si = f.selfInfo;
      // Through `meshLog`, which prints so the line routes to I/flutter on
      // Android and is captured by `flutter logs`, and is compiled out of a
      // release build because it carries a position.
      meshLog('meshcore.loc', 'SelfInfoFrame in: '
          'lat=${si.latitude} lon=${si.longitude} '
          'pol=${si.advertLocPolicy} name=${si.name}');
      ev = MeshEvent(kind: MeshEventKind.selfInfo, args: <String, String>{
        'name': si.name,
      });
    }
    if (ev == null) return;
    _pushEvent(ev);
  }

  /// Kinds that describe a state rather than an occurrence. The radio reports
  /// its battery and its own info on a timer, and a node advertises every so
  /// often, so the same event arrives unchanged again and again.
  static const Set<MeshEventKind> _stateKinds = <MeshEventKind>{
    MeshEventKind.battery,
    MeshEventKind.selfInfo,
    MeshEventKind.deviceInfo,
    MeshEventKind.deviceClockSynced,
    MeshEventKind.advert,
    MeshEventKind.contact,
  };

  /// Append an event to the rolling RECENT-feed buffer.
  ///
  /// A repeated state refreshes the row that already says it instead of
  /// appending a twin. On the bench the feed read "battery 4.03V",
  /// "self-info · WIOld", "battery 4.03V", "self-info · WIOld" … — one line
  /// per poll interval, which taught a reader to skip the feed. A state that
  /// CHANGES is still a new row, because that is the part worth reading.
  /// Messages and faults always append: two identical messages are two
  /// messages, and a repeated fault is a repeated fault.
  void _pushEvent(MeshEvent ev) {
    if (_events.isNotEmpty && _stateKinds.contains(ev.kind)) {
      final MeshEvent last = _events.last;
      if (last.kind == ev.kind && _sameArgs(last.args, ev.args)) {
        _events[_events.length - 1] =
            MeshEvent(kind: ev.kind, args: ev.args, at: ev.at);
        return;
      }
    }
    _events.add(ev);
    if (_events.length > _eventsCap) _events.removeAt(0);
  }

  static bool _sameArgs(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final MapEntry<String, String> e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }

  String _hex(List<int> b) =>
      b.map((int x) => x.toRadixString(16).padLeft(2, '0')).join();

  // --- Channel chat (R6) ---

  final List<ChatMessage> _messages = <ChatMessage>[];
  /// One cap, not two: the store truncates at `ChatStore.cap` when it writes,
  /// so a second number here would silently cut rows the store would have
  /// kept (or keep rows it will drop) depending on which ran first.
  static const int _messagesCap = ChatStore.cap;

  /// Rows the cap has already dropped, per thread (`ch:<idx>` / `dm:<peer>`).
  ///
  /// The 250-row cap used to truncate in silence, which made "where did it
  /// go" unanswerable. The count is persisted beside the history so the
  /// notice survives the restart that made the rows disappear.
  final Map<String, int> _dropped = <String, int>{};

  /// How many older rows this thread has lost to the cap.
  int droppedForChannel(int idx) => _dropped['ch:$idx'] ?? 0;

  /// Same, for a DM thread (keyed by the 12-hex prefix the row stores).
  int droppedForPeer(String peerPubKeyHex) {
    final String prefix = peerPubKeyHex.length >= 12
        ? peerPubKeyHex.substring(0, 12)
        : peerPubKeyHex;
    return _dropped['dm:$prefix'] ?? 0;
  }

  /// Count [m] as a row the cap dropped, and persist the tally.
  void _noteDropped(ChatMessage m) {
    final String k = ChatStore.threadKeyOf(m);
    _dropped[k] = (_dropped[k] ?? 0) + 1;
    unawaited(ChatStore.saveDropped(Map<String, int>.from(_dropped)));
  }

  Future<void> _loadDropped() async {
    final Map<String, int> loaded = await ChatStore.loadDropped();
    if (loaded.isEmpty) return;
    _dropped
      ..clear()
      ..addAll(loaded);
    notifyListeners();
  }

  /// Delete everything this app kept of the conversation: every stored row,
  /// and the per-thread tally of rows the cap had already dropped.
  ///
  /// The radio's own copy is untouched, and so is anything already on air: this
  /// removes what the phone held, not what was said. The in-memory rows go
  /// first, because `ChatStore.clear()` alone would leave them on screen and the
  /// next persist would write them back — a delete that reports success and then
  /// resurrects the history is worse than no delete at all.
  ///
  /// Read markers (`DmReadStore`) are left alone deliberately: they are timestamps
  /// keyed by peer, they carry no message content, and a peer whose thread is
  /// re-created would otherwise have its newest row look unread.
  Future<void> clearAllHistory() async {
    _messages.clear();
    _invalidateMessagesCache();
    if (_dropped.isNotEmpty) {
      _dropped.clear();
      await ChatStore.saveDropped(<String, int>{});
    }
    await ChatStore.clear();
    notifyListeners();
  }

  /// Known channels by index → name. Channel 0 ("Public") always
  /// exists; the rest are filled in from `CHANNEL_INFO` replies.
  final Map<int, String> _channels = <int, String>{0: 'Public'};

  /// Cache of the **per-slot 16-byte PSK** as reported by the device
  /// (RESP_CODE_CHANNEL_INFO). Lets the Edit dialog reveal the
  /// current key for a slot without a second device round-trip.
  /// Slot 0 (Public) is pre-seeded so we never have to ask the
  /// device for the well-known key.
  final Map<int, List<int>> _channelPsks = <int, List<int>>{
    0: List<int>.unmodifiable(kPublicChannelPsk),
  };

  /// 16-byte AES-128 PSK currently set on [idx], or null if we
  /// haven't observed a `ChannelInfoFrame` for that slot yet.
  /// The list is unmodifiable; copy if you need to mutate.
  List<int>? channelPsk(int idx) => _channelPsks[idx];

  /// Slots to probe before `DEVICE_INFO` says how many the radio actually has.
  /// Four is the pessimistic count: most boards hold 40, small ones 8, and the
  /// exact number arrives with the device query that follows the handshake.
  static const int _channelProbeCount = 4;

  /// How long a slot may take to answer before the walk moves on. The reply is
  /// one short frame the radio writes immediately, so a second is generous.
  static const Duration _channelProbeIdle = Duration(seconds: 1);

  Timer? _channelProbeIdleTimer;
  int _channelProbeCursor = 0;
  bool _channelProbeOutstanding = false;
  final Duration? _channelProbeIdleOverride;

  /// Slots asked for since the last link-up, so a repeated reply cannot make
  /// the walk ask twice.
  final Set<int> _channelsProbed = <int>{};

  int _activeChannel = 0;

  /// Currently selected chat channel index.
  int get activeChannel => _activeChannel;

  /// Cached sorted view of `_channels`. Invalidated whenever the
  /// underlying map mutates, so `context.select<MC, channels>` can
  /// short-circuit rebuilds when the channel list is unchanged.
  List<MapEntry<int, String>>? _channelsCache;

  void _invalidateChannelsCache() => _channelsCache = null;

  /// Known channels, ascending by index.
  List<MapEntry<int, String>> get channels {
    final List<MapEntry<int, String>>? cached = _channelsCache;
    if (cached != null) return cached;
    final List<MapEntry<int, String>> v = _channels.entries.toList()
      ..sort((MapEntry<int, String> a, MapEntry<int, String> b) =>
          a.key.compareTo(b.key));
    _channelsCache = v;
    return v;
  }

  /// Name of the active channel (falls back to its index).
  String get activeChannelName =>
      _channels[_activeChannel] ?? 'CH $_activeChannel';

  void setActiveChannel(int idx) {
    if (idx == _activeChannel) return;
    _activeChannel = idx;
    notifyListeners();
  }

  // R33 — user-preferred default channel slot to land on at app
  // launch. `_appliedDefaultChannel` latches so we only apply the
  // preference once per controller lifetime (i.e. once per cold
  // launch); mid-session reconnects keep whatever the user has
  // since switched to.
  int? _defaultChannelIdx;
  bool _appliedDefaultChannel = false;

  int? get defaultChannelIdx => _defaultChannelIdx;

  /// True iff [idx] is the user-saved default slot.
  bool isDefaultChannel(int idx) => _defaultChannelIdx == idx;

  /// Persist [idx] as the default slot. Pass `null` to clear the
  /// preference. Does not change the active slot live; the new
  /// default applies on the next cold launch (when the device
  /// reaches `ready` and `_applyDefaultChannel` runs).
  Future<void> setDefaultChannelIdx(int? idx) async {
    if (idx == _defaultChannelIdx) return;
    _defaultChannelIdx = idx;
    notifyListeners();
    await DefaultChannelStore.write(idx);
  }

  /// Pre-load the saved default so the Channels-mgmt UI can show
  /// the "★ default" indicator before the device has connected.
  Future<void> _loadDefaultChannel() async {
    _defaultChannelIdx = await DefaultChannelStore.read();
    notifyListeners();
  }

  /// One-shot at first reach-ready: if a default slot has been
  /// saved, switch the active channel to it. No-op if the
  /// preference is unset or already matches.
  Future<void> _applyDefaultChannel() async {
    final int? saved = _defaultChannelIdx ?? await DefaultChannelStore.read();
    if (saved == null) return;
    if (saved != _activeChannel) setActiveChannel(saved);
  }

  /// Create/overwrite a channel slot (`SET_CHANNEL` 0x20) then refresh
  /// it (`GET_CHANNEL`). [psk] is the 16-byte channel key. No-op if
  /// not connected.
  Future<void> setChannel({
    required int idx,
    required String name,
    required List<int> psk,
  }) async {
    if (!isReady) return;
    await send(MeshcoreFrameCodec.setChannel(
        channelIdx: idx, name: name, psk: psk));
    if (name.isNotEmpty) {
      _channels[idx] = name; // optimistic
      _invalidateChannelsCache();
    }
    // Optimistic PSK cache — the GET_CHANNEL below will confirm.
    _channelPsks[idx] = List<int>.unmodifiable(psk);
    notifyListeners();
    unawaited(send(MeshcoreFrameCodec.getChannel(idx)).catchError((_) {}));
  }

  /// "Clear" a slot. The companion protocol has no destructive
  /// `CLEAR_CHANNEL` opcode, so the pragmatic implementation is to
  /// overwrite the slot back to the well-known Public defaults
  /// (`"Public"` + `kPublicChannelPsk`). For slot 0 this is a no-op
  /// since that's already the Public channel; for higher slots it
  /// makes them indistinguishable from a fresh device and lets the
  /// shared Public channel work through that slot too.
  Future<void> clearChannel(int idx) async {
    if (!isReady) return;
    await setChannel(
      idx: idx,
      name: 'Public',
      psk: List<int>.from(kPublicChannelPsk),
    );
  }

  /// Per-channel cache of the filtered message list. Filled lazily on
  /// `messagesFor`; invalidated on every `_messages` mutation. Returning
  /// a stable list ref lets `Selector` / `context.select` short-circuit
  /// rebuilds when nothing on that channel changed.
  final Map<int, List<ChatMessage>> _messagesByChannel =
      <int, List<ChatMessage>>{};

  void _invalidateMessagesCache([int? idx]) {
    if (idx == null) {
      _messagesByChannel.clear();
    } else {
      _messagesByChannel.remove(idx);
    }
  }

  /// Messages for [idx] (default: the active channel), oldest first.
  /// Cached per channel; the cache is invalidated whenever the
  /// underlying `_messages` list mutates.
  List<ChatMessage> messagesFor([int? idx]) {
    final int c = idx ?? _activeChannel;
    return _messagesByChannel.putIfAbsent(
        c,
        () => _messages
            .where((ChatMessage m) => m.channelIdx == c)
            .toList(growable: false));
  }

  final StreamController<ChatMessage> _incomingCh =
      StreamController<ChatMessage>.broadcast();

  /// Inbound channel messages (for TTS / notifications). Outgoing
  /// messages are not emitted here.
  Stream<ChatMessage> get incomingChannelMessages => _incomingCh.stream;

  /// Operations that failed (send / advert / scan / set-* throws).
  /// `CueBridge` listens to this and fires `CueKind.taskError`.
  /// Emitted as the operation name (e.g. "sendChannel", "sendDm",
  /// "scan", "advert") so callers can label snackbars too.
  final StreamController<String> _taskErrors =
      StreamController<String>.broadcast();
  Stream<String> get taskErrors => _taskErrors.stream;

  /// An advert was heard over the air (AdvertFrame / RF-log) and folded
  /// into the fabric. The bool is `true` when it's a node we'd never
  /// heard before (→ `CueKind.discovery`, the Geiger tick) and `false`
  /// for a re-advert from a node we already knew (→ `CueKind.advert`,
  /// the ambient mesh ping). Only fires for *live* adverts — the
  /// post-connect contact-sync dump goes through a different path and
  /// deliberately stays silent.
  final StreamController<bool> _adverts = StreamController<bool>.broadcast();
  Stream<bool> get incomingAdverts => _adverts.stream;

  /// Convenience for code paths that want to flag a failure without
  /// throwing into the void.
  void _emitTaskError(String op) {
    if (!_taskErrors.isClosed) _taskErrors.add(op);
  }

  void _addMessage(ChatMessage m) {
    _messages.add(m);
    if (_messages.length > _messagesCap) {
      _noteDropped(_messages.removeAt(0));
      // The cap-eviction may have removed a row from any channel,
      // not just `m.channelIdx`. Conservative: clear the whole cache
      // when we evict; otherwise just invalidate the affected slot.
      _invalidateMessagesCache();
    } else {
      _invalidateMessagesCache(m.channelIdx);
    }
    _persistChat();
    // Feed the Meshbook accumulator (channel messages only; idempotent).
    if (m.channelIdx >= 0 && _meshbook.ingest(m)) _saveMeshbookSoon();
  }

  // --- Outgoing delivery tracking (QoL: per-message status glyph) ---
  //
  // Lifecycle: sending → sent → (DM only) delivered, or → failed.
  // - sending: we issued the BLE send command; a watchdog catches a
  //   device that never confirms.
  // - sent: the device confirmed. Channel text is confirmed by a bare
  //   RESP_CODE_OK (firmware `MyMesh.cpp` CMD_SEND_CHANNEL_TXT_MSG; the
  //   official meshcore.js / meshcore_py clients wait for OK too) and
  //   stops here — flood routing yields no recipient receipt. A DM is
  //   confirmed by RESP_CODE_SENT (MsgSentFrame), which carries the
  //   expectedAck tag and the device's timeout estimate. Each pending
  //   send records which reply it expects and is matched oldest-first
  //   within that kind (sends are serialised over BLE).
  // - ERR: RESP_CODE_ERR fails the oldest in-flight send at once, with
  //   the device's reason (`deviceErrorReason`).
  // - delivered: a DM's PUSH_CODE_ACK arrived carrying the same
  //   expectedAck tag.
  // - unknown: a send the app cannot vouch for. A timer expired without
  //   the radio's answer, or the link went away mid-send; nothing on the
  //   phone can say whether the frame was transmitted. It is deliberately
  //   not `failed` (APP-C3).
  // - failed: the BLE send threw (the frame never left the app), the
  //   radio answered `ERR` with a reason (an explicit rejection), or a
  //   direct message passed its ack timeout *and* the 30 s grace with no
  //   ACK.
  //
  // APP-C2's four rules bind the timeouts, and each one is a branch below:
  //  1. a sync-poll timeout never fails a row — [_expireCommands] moves it
  //     to `unknown`;
  //  2. a channel send never fails from a timeout — channel data has no
  //     ACK — the confirm watchdog moves it to `unknown`;
  //  3. a DM fails only from an explicit `ERR`, or after the grace;
  //  4. the 30 s grace lets a late ACK still resolve to delivered, so the
  //     ack timeout moves the row to `unknown` first and only the grace
  //     timer fails it.
  //
  // Ordering: some firmware pushes the PUSH_CODE_ACK *before* the
  // RESP_CODE_SENT confirmation (the ACK can't be matched yet — we
  // don't learn the expectedAck tag until the SENT frame). So an
  // unmatched ACK is cached briefly and reconciled when the SENT
  // frame lands; otherwise the message would (wrongly) time out as
  // failed despite having been delivered.

  /// Bumped on every delivery-state change of an outgoing message.
  /// `context.select<..., List<ChatMessage>>(messagesFor)` cannot see
  /// those changes: provider compares selected lists with
  /// `DeepCollectionEquality`, and the elements are the same mutable
  /// [ChatMessage] objects, so a state flip inside one is "equal". A
  /// screen that selects this counter as well repaints the row glyph.
  int get deliveryRevision => _deliveryRevision;
  int _deliveryRevision = 0;

  /// Commands awaiting the device's reply, oldest first. Each entry says
  /// which reply it expects, because the firmware does not answer every
  /// command the same way; [CommandLedger] decides which entry a reply
  /// belongs to and refuses to credit one out of order.
  final CommandLedger _ledger = CommandLedger(
    timeout: const Duration(seconds: 20),
  );

  /// Replies that arrived with nothing at the head to take them: a late
  /// answer to a command that had timed out, a duplicate, or an answer to a
  /// command this app never registered. Each one used to be credited to
  /// whatever happened to be waiting.
  int get unclaimedReplies => _ledger.unclaimed;

  /// Commands that reached the ledger's timeout without an answer.
  int get unansweredCommands => _ledger.unanswered;

  void _dropPending(String id) => _ledger.drop(id);

  /// Retire every command that has waited past the ledger's timeout, so a
  /// silent radio cannot hold the head of the queue and misroute the next
  /// reply. A marker (tool, raw, advert) has no message to fail; its
  /// removal is the whole effect.
  ///
  /// APP-C2 rule 1: a wait that ran out is not evidence the send failed —
  /// the frame may still be queued on the radio — so the row becomes
  /// `unknown`, never `failed`.
  void _expireCommands() => _resolveExpired(_ledger.expire());

  /// Resolves ids the ledger swept while a reply was being claimed.
  ///
  /// `claim` and `takeHead` expire first, so a command that reached its
  /// deadline between two ticks of the expiry timer is swept there rather
  /// than here. Draining is what keeps those rows from waiting forever.
  void _resolveSwept() => _resolveExpired(_ledger.drainSwept());

  void _resolveExpired(List<String> ids) {
    for (final String id in ids) {
      if (id == _toolSendMarker ||
          id == _advertSendMarker ||
          id == _rawSendMarker ||
          id == _cliMarker ||
          id == _configMarker ||
          id == _channelDataMarker) {
        continue;
      }
      _uncertainOutgoing(id, 'the radio did not answer');
    }
  }

  void _completeChannelData(MeshcoreInbound reply) {
    final Completer<MeshcoreInbound>? c = _channelDataAnswer;
    if (c != null && !c.isCompleted) c.complete(reply);
  }

  /// Fail a message that is still in flight, with a reason. Monotonic: only
  /// a row in one of [from] moves, so a late watchdog or ERR never overwrites
  /// a terminal state. The caller narrows [from]: an explicit rejection
  /// fails a `sending` row, and the end of the ack grace fails an `unknown`
  /// one.
  void _failOutgoing(String id, String reason,
      {Set<MessageDelivery> from = const <MessageDelivery>{
        MessageDelivery.sending
      },
      FailureCause? cause}) {
    _dropPending(id);
    _deliveryTimers.remove(id)?.cancel();
    final ChatMessage? m = _messageById(id);
    if (m == null || m.delivery == null || !from.contains(m.delivery)) return;
    m
      ..delivery = MessageDelivery.failed
      ..failReason = reason
      ..failCause = cause;
    _deliveryRevision++;
    _persistChat();
  }

  /// Mark a send the app cannot vouch for: a timer expired with no answer,
  /// or the link went away before the radio confirmed. Monotonic like
  /// [_failOutgoing] — only an in-flight row moves — and it keeps the
  /// reason so the row can say why it cannot be vouched for.
  void _uncertainOutgoing(String id, String reason) {
    _dropPending(id);
    _deliveryTimers.remove(id)?.cancel();
    final ChatMessage? m = _messageById(id);
    if (m == null || m.delivery == null) return;
    if (m.delivery != MessageDelivery.sending &&
        m.delivery != MessageDelivery.sent) {
      return;
    }
    m
      ..delivery = MessageDelivery.unknown
      ..failReason = reason;
    _deliveryRevision++;
    _persistChat();
  }

  /// Per-message lifecycle timers (confirm watchdog, then DM ack
  /// timeout), keyed by message id.
  final Map<String, Timer> _deliveryTimers = <String, Timer>{};

  /// ACK tags seen *before* their RESP_CODE_SENT (tag → epoch ms).
  /// Consumed when the matching SENT confirmation arrives. Pruned by
  /// age so a never-matched ACK can't accumulate.
  final Map<int, int> _recentAcks = <int, int>{};
  static const int _recentAckTtlMs = 30000;

  /// APP-C2 rule 4: how long an unanswered DM stays `unknown` before it is
  /// failed. A late ACK anywhere in this window still resolves to delivered.
  static const Duration _lateAckGrace = Duration(seconds: 30);

  /// The radio's own send-to-ACK time for the newest confirmed message, in
  /// milliseconds, or null until one has arrived.
  ///
  /// `PUSH_CODE_SEND_CONFIRMED` carries it, and it is the one round-trip
  /// number this app cannot compute for itself: the phone's clock stops at
  /// the radio's door. A firmware that omits the field leaves this null
  /// rather than showing a zero.
  int? _lastAckTripMs;

  /// See [_lastAckTripMs].
  int? get lastAckTripMs => _lastAckTripMs;

  /// How long to wait for the device's send confirmation before
  /// giving up on an outgoing message.
  static const Duration _confirmWatchdog = Duration(seconds: 15);

  /// Test seam: when set, overrides BOTH the confirm watchdog and the
  /// DM ack-timeout so delivery-state transitions can be exercised
  /// without real-time waits. Null in production.
  final Duration? _deliveryTimeoutOverride;

  ChatMessage? _messageById(String id) {
    for (final ChatMessage m in _messages) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// A command that is not a chat message (a tool request, a raw send, a
  /// self-advert) still has to hold its place in the answer order, or the
  /// next reply lands on whatever is waiting. Re-registering an id that is
  /// already in flight is a no-op: the old entry still owns its answer.
  void _registerMarker(String id, CommandAnswer answer) {
    if (_ledger.isPending(id)) return;
    _ledger.register(id, answer);
  }

  void _registerOutgoing(ChatMessage m, CommandAnswer expect) {
    if (_ledger.isPending(m.id)) _ledger.drop(m.id);
    _ledger.register(m.id, expect);
    _deliveryTimers[m.id]?.cancel();
    _deliveryTimers[m.id] =
        Timer(_deliveryTimeoutOverride ?? _confirmWatchdog, () {
      // APP-C2 rule 2: a channel send never fails from a timeout — the
      // radio's `OK` is its only receipt and channel data has no ACK. A DM
      // that never got its `RESP_CODE_SENT` is equally unprovable (rule 3
      // allows failure only from an explicit rejection or past the grace).
      _uncertainOutgoing(m.id, 'no confirmation from the radio');
      notifyListeners();
    });
  }

  void _markOutgoingFailed(String id, [String reason = 'send failed']) =>
      _failOutgoing(id, reason,
          from: const <MessageDelivery>{
            MessageDelivery.sending,
            MessageDelivery.sent
          });

  /// DM ack-timeout = the device's estimate, padded 50 % for OTA
  /// jitter, clamped so a tiny or absurd estimate can't make the glyph
  /// flap or hang.
  Duration _ackTimeoutFor(int estMs) {
    final Duration? override = _deliveryTimeoutOverride;
    if (override != null) return override;
    final int padded = (estMs * 1.5).round();
    final int clamped = padded.clamp(5000, 120000);
    return Duration(milliseconds: clamped);
  }

  void _recordRecentAck(int tag) {
    final int now = DateTime.now().millisecondsSinceEpoch;
    _recentAcks.removeWhere((_, int ts) => now - ts > _recentAckTtlMs);
    _recentAcks[tag] = now;
  }

  /// True if [tag] was acked within the TTL; consumes it.
  bool _consumeRecentAck(int tag) {
    final int? ts = _recentAcks.remove(tag);
    if (ts == null) return false;
    return DateTime.now().millisecondsSinceEpoch - ts <= _recentAckTtlMs;
  }

  /// Take [answer] if it belongs to the command at the head of the queue.
  ///
  /// The wire carries no correlation tag, so order is the only evidence
  /// there is. A reply for the other kind is therefore *not* skipped past
  /// the head: the ledger counts it as unclaimed and the caller gets null.
  CommandEntry? _takePending(CommandAnswer answer) => _ledger.claim(answer);

  void _trackDelivery(MeshcoreInbound f) {
    _trackDeliveryInner(f);
    _resolveSwept();
  }

  void _trackDeliveryInner(MeshcoreInbound f) {
    if (f is OkFrame) {
      // Channel text, raw data, channel datagrams and the self-advert are
      // acknowledged with a bare OK.
      final CommandEntry? p = _takePending(CommandAnswer.ok);
      if (p == null) return;
      if (p.id == _configMarker) {
        _completeRadioConfig(const RadioAnswer.accepted());
        return;
      }
      if (p.id == _channelDataMarker) {
        _completeChannelData(f);
        return;
      }
      if (p.id == _rawSendMarker) {
        _completeRawSend(f);
        return;
      }
      if (p.id == _cliMarker) {
        _completeCli(f);
        return;
      }
      if (p.id == _advertSendMarker) {
        return;
      }
      if (p.id == _contactAddMarker) {
        _clearContactsFull();
        notifyListeners();
        return;
      }
      final ChatMessage? m = _messageById(p.id);
      _deliveryTimers.remove(p.id)?.cancel();
      if (m == null || m.delivery != MessageDelivery.sending) return;
      // Flood channel text has no recipient receipt: sent is terminal.
      m.delivery = MessageDelivery.sent;
      _deliveryRevision++;
      _persistChat();
    } else if (f is ErrorFrame) {
      // ERR answers the command at the head, whatever kind it is: an ERR
      // for a raw send must not fail a chat message that happens to be
      // older. A probe whose ERR is expected (see [_squelchNextDeviceError])
      // is not a send.
      if (_squelchNextDeviceError > 0) return;
      final CommandEntry? p = _ledger.takeHead();
      if (p == null) return;
      if (p.id == _configMarker) {
        _completeRadioConfig(RadioAnswer.refused(f.code));
        return;
      }
      if (p.id == _channelDataMarker) {
        _completeChannelData(f);
        return;
      }
      if (p.id == _rawSendMarker) {
        _completeRawSend(f);
        return;
      }
      if (p.id == _cliMarker) {
        _completeCli(f);
        return;
      }
      if (p.id == _contactAddMarker) {
        // The radio refused the add. `ERR_CODE_TABLE_FULL` is the one that a
        // user can act on, so it becomes state rather than a silent refusal.
        if (f.code == kErrTableFull) _contactsFull = true;
        _emitTaskError('addContact');
        notifyListeners();
        return;
      }
      if (p.id == _toolSendMarker || p.id == _advertSendMarker) {
        return;
      }
      _failOutgoing(p.id, deviceErrorReason(f.code),
          cause: Failure.causeForDeviceError(f.code),
          from: const <MessageDelivery>{MessageDelivery.sending});
    } else if (f is DisabledFrame) {
      // `RESP_CODE_DISABLED` (0x0F) is an answer, not silence: the command
      // exists and is switched off on this radio. Claiming the head here turns
      // a 15-second timeout into the truth, and the copy says it is the radio's
      // setting rather than the link's fault.
      final CommandEntry? p = _ledger.takeHead();
      if (p == null) return;
      if (p.id == _contactAddMarker) {
        _emitTaskError('addContact');
        notifyListeners();
        return;
      }
      if (p.id == _configMarker ||
          p.id == _channelDataMarker ||
          p.id == _rawSendMarker ||
          p.id == _toolSendMarker ||
          p.id == _advertSendMarker) {
        return;
      }
      _failOutgoing(p.id, 'the radio has that command switched off',
          cause: FailureCause.commandDisabled,
          from: const <MessageDelivery>{MessageDelivery.sending});
    } else if (f is MsgSentFrame) {
      final CommandEntry? p = _takePending(CommandAnswer.sent);
      if (p == null) return;
      final String id = p.id;
      if (id == _toolSendMarker) return; // a tool's request, not a message
      final ChatMessage? m = _messageById(id);
      if (m == null || m.delivery != MessageDelivery.sending) return;
      m
        ..delivery = MessageDelivery.sent
        ..expectedAck = f.sent.expectedAck;
      _deliveryTimers.remove(id)?.cancel();
      if (_consumeRecentAck(f.sent.expectedAck)) {
        // The ACK raced ahead of this SENT confirmation (firmware
        // ordering). Reconcile now — delivered, no timeout.
        m.delivery = MessageDelivery.delivered;
      } else if (f.sent.expectedAck == 0 && !f.sent.isFlood) {
        // The radio said no acknowledgement will come for this send (it reports
        // `expected_ack = 0` when none is expected). `sent` is then the last
        // word there will ever be, so waiting out an ACK watchdog would turn a
        // successful send into `unknown` and then `failed`.
      } else if (!f.sent.isFlood) {
        // Direct message: wait for the recipient ACK, bounded by the
        // device's own estimate (`estTimeoutMs`).
        _deliveryTimers[id] = Timer(_ackTimeoutFor(f.sent.estTimeoutMs), () {
          // APP-C2 rule 4: the device's estimate running out is not the
          // end of the story — a late ACK still resolves to delivered, so
          // the row first becomes `unknown`, and only the grace timer below
          // fails it.
          _uncertainOutgoing(id, 'no acknowledgement yet from the recipient');
          notifyListeners();
          _deliveryTimers[id] =
              Timer(_deliveryTimeoutOverride ?? _lateAckGrace, () {
            _failOutgoing(id, 'no acknowledgement from the recipient',
                from: const <MessageDelivery>{MessageDelivery.unknown});
            notifyListeners();
          });
        });
      }
      _deliveryRevision++;
      _persistChat();
    } else if (f is AckFrame) {
      if (f.roundTripMs != null && f.roundTripMs! > 0) {
        _lastAckTripMs = f.roundTripMs;
      }
      // Match the ack tag to the most recent still-sent message. Tags
      // are 32-bit; collisions are unlikely within a handful of
      // in-flight messages, and matching newest-first is the safe
      // choice.
      for (int i = _messages.length - 1; i >= 0; i--) {
        final ChatMessage m = _messages[i];
        // A row inside the grace window has already moved to `unknown`;
        // a late ACK there is exactly what rule 4 exists for.
        if (m.outgoing &&
            (m.delivery == MessageDelivery.sent ||
                m.delivery == MessageDelivery.unknown) &&
            m.expectedAck == f.ackCrc) {
          m.delivery = MessageDelivery.delivered;
          _deliveryTimers.remove(m.id)?.cancel();
          _deliveryRevision++;
          _persistChat();
          return;
        }
      }
      // No matching sent message yet — the ACK arrived before the
      // RESP_CODE_SENT confirmation. Remember it so the SENT frame can
      // reconcile to delivered instead of timing out.
      _recordRecentAck(f.ackCrc);
    }
  }

  // --- Direct messages (P2P) ---

  final StreamController<ChatMessage> _incomingDm =
      StreamController<ChatMessage>.broadcast();

  /// Inbound DMs (broadcast). Outgoing DMs are NOT emitted here.
  Stream<ChatMessage> get incomingDirectMessages => _incomingDm.stream;

  /// Every stored row, channels and direct messages together, oldest first.
  ///
  /// The whole-history export needs the whole list, and it must not be a
  /// mutable view: the backup encodes what was there when the passphrase was
  /// accepted, not what a frame arriving mid-encode would add.
  List<ChatMessage> get allMessages => List<ChatMessage>.unmodifiable(_messages);

  /// All DM messages for a peer (by full pubkey hex, or 12-hex
  /// prefix when only the prefix was resolvable on receive), oldest
  /// first.
  List<ChatMessage> dmHistoryFor(String peerPubKeyHex) {
    final String prefix = peerPubKeyHex.length >= 12
        ? peerPubKeyHex.substring(0, 12)
        : peerPubKeyHex;
    return _messages
        .where((ChatMessage m) =>
            m.peerPubKeyHex != null &&
            (m.peerPubKeyHex == peerPubKeyHex ||
                m.peerPubKeyHex == prefix))
        .toList(growable: false);
  }

  /// Total count of DM messages exchanged with a peer (incoming +
  /// outgoing). Used by the Nodes screen to render the per-row
  /// "💬 N" badge — Option D DM-presence surfacing.
  int dmCountFor(String peerPubKeyHex) =>
      dmHistoryFor(peerPubKeyHex).length;

  // --- Identity reconcile (R56): a contact deleted + re-added on the
  // other device returns with a NEW pubkey but the SAME name. We never
  // auto-migrate on a name match — names aren't unique, so that would let
  // an impostor (or a coincidental same-name node) silently inherit your
  // star/tags/DM history. Instead we *detect* the likely supersession and
  // let the user confirm it (see NodeDetailSheet).

  bool _hasMigratableIdentityData(String pk) =>
      _favorites.contains(pk) ||
      _known.contains(pk) ||
      (_tags[pk]?.isNotEmpty ?? false) ||
      dmHistoryFor(pk).isNotEmpty ||
      _contacts.containsKey(pk);

  /// True if [pubKeyHex] holds user data worth preserving (favourite /
  /// known / tags / DM history / synced contact). Drives the manual
  /// key-link direction in NodeDetailSheet.
  bool hasReconcileData(String pubKeyHex) =>
      _hasMigratableIdentityData(pubKeyHex);

  /// Manual key-link: re-home a contact onto a key the user supplies (or
  /// picks) — robust when the new key isn't in the fabric yet (chat-only,
  /// out of range, or wrongly retired). Un-retires the target if it was
  /// superseded, ensures a node entry exists for it (so it's listable +
  /// messageable), then reconciles [fromPubKeyHex] → the target.
  Future<void> linkIdentityToKey({
    required String fromPubKeyHex,
    required String toPubKeyHex,
    String? name,
  }) async {
    final String to = toPubKeyHex.toLowerCase();
    if (to == fromPubKeyHex.toLowerCase()) return;
    // Recover a key a botched earlier reconcile may have retired.
    if (_superseded.remove(to)) {
      unawaited(SupersededStore.save(_superseded));
    }
    // Make sure the target is a first-class node, even if never heard, so
    // it shows in lists and the DM/Message path can reach it.
    if (!_nodes.containsKey(to)) {
      final int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      _nodes[to] = DiscoveredNode(
        pubKeyHex: to,
        name: (name == null || name.trim().isEmpty)
            ? to.substring(0, to.length < 8 ? to.length : 8)
            : name.trim(),
        type: 1, // chat node
        lastHeardUnix: now,
        viaAdvert: false,
      );
    }
    await reconcileIdentity(fromPubKeyHex: fromPubKeyHex, toPubKeyHex: to);
    // Make the radio able to route DMs to the new key (channel already
    // works without a contact; DMs don't). Best-effort, full keys only.
    if (isReady && to.length == kPubKeySize * 2) {
      await addNodeAsDeviceContact(to, name: name);
    }
  }

  /// Clear ALL superseded-key suppressions — recovery if the prune logic
  /// hid a key it shouldn't have. Heard adverts for those keys will then
  /// surface normally again.
  Future<void> clearSuperseded() async {
    if (_superseded.isEmpty) return;
    _superseded.clear();
    await SupersededStore.save(_superseded);
    notifyListeners();
  }

  /// If [pubKeyHex] participates in a likely "returning contact" pair —
  /// a same-name node where one key carries your data (a saved/synced
  /// contact) and the other is a different key — return the pair (else
  /// null). Works whether you're looking at the old or the new key.
  ///
  /// Identity is keyed off **which side holds your data**, NOT timing: a
  /// re-added peer's old key keeps getting refreshed by contact-sync, so
  /// a "stale key is older" heuristic misses the real case. The data side
  /// is the stale key; the other (the regenerated key) is the live one to
  /// move to. Always user-confirmed — names aren't unique, so we only
  /// *suggest*; the user decides.
  IdentityMatch? identityMatchFor(String pubKeyHex) {
    final DiscoveredNode? a = _nodes[pubKeyHex];
    if (a == null || _superseded.contains(pubKeyHex)) return null;
    final String name = a.name.trim().toLowerCase();
    if (name.length < 2) return null; // too generic to match on

    final List<DiscoveredNode> sibs = <DiscoveredNode>[
      for (final DiscoveredNode b in _nodes.values)
        if (b.pubKeyHex != a.pubKeyHex &&
            !_superseded.contains(b.pubKeyHex) &&
            b.name.trim().toLowerCase() == name)
          b
    ];
    if (sibs.isEmpty) return null;

    DiscoveredNode? best(Iterable<DiscoveredNode> xs) {
      DiscoveredNode? m;
      for (final DiscoveredNode x in xs) {
        if (m == null || x.lastHeardUnix > m.lastHeardUnix) m = x;
      }
      return m;
    }

    DiscoveredNode stale;
    DiscoveredNode fresh;
    if (_hasMigratableIdentityData(a.pubKeyHex)) {
      // `a` is the saved contact → move it to the live (new) key. Prefer a
      // sibling that *doesn't* already hold data (the fresh regenerated
      // key); fall back to the most-recently-heard sibling.
      final List<DiscoveredNode> noData = <DiscoveredNode>[
        for (final DiscoveredNode b in sibs)
          if (!_hasMigratableIdentityData(b.pubKeyHex)) b
      ];
      final DiscoveredNode? f = best(noData.isNotEmpty ? noData : sibs);
      if (f == null) return null;
      stale = a;
      fresh = f;
    } else {
      // `a` has no data (likely the new key) → find the saved sibling.
      final List<DiscoveredNode> withData = <DiscoveredNode>[
        for (final DiscoveredNode b in sibs)
          if (_hasMigratableIdentityData(b.pubKeyHex)) b
      ];
      final DiscoveredNode? s = best(withData);
      if (s == null) return null; // nothing to migrate → no prompt
      stale = s;
      fresh = a;
    }
    if (stale.pubKeyHex == fresh.pubKeyHex) return null;
    return IdentityMatch(
      stale: stale,
      fresh: fresh,
      messageCount: dmHistoryFor(stale.pubKeyHex).length,
      hasStar: _favorites.contains(stale.pubKeyHex),
      hasTags: _tags[stale.pubKeyHex]?.isNotEmpty ?? false,
      hasKnown: _known.contains(stale.pubKeyHex),
    );
  }

  /// Move all user metadata + DM history from a stale key to the live
  /// key, then drop the stale node. User-confirmed (NEVER automatic).
  Future<void> reconcileIdentity({
    required String fromPubKeyHex,
    required String toPubKeyHex,
  }) async {
    if (fromPubKeyHex == toPubKeyHex) return;

    if (_favorites.remove(fromPubKeyHex)) {
      _favorites.add(toPubKeyHex);
      await FavoriteStore.save(_favorites);
    }
    if (_known.remove(fromPubKeyHex)) {
      _known.add(toPubKeyHex);
      await KnownStore.save(_known);
    }
    final List<String>? oldTags = _tags.remove(fromPubKeyHex);
    if (oldTags != null && oldTags.isNotEmpty) {
      final List<String> dst =
          List<String>.from(_tags[toPubKeyHex] ?? const <String>[]);
      for (final String t in oldTags) {
        if (!dst.contains(t)) dst.add(t);
      }
      _tags[toPubKeyHex] = dst;
      await NodeTagsStore.save(_tags);
    }
    final int readMs = _dmReadStore.lastReadAtMs(fromPubKeyHex);
    if (readMs > 0) {
      await _dmReadStore.markRead(toPubKeyHex,
          at: DateTime.fromMillisecondsSinceEpoch(readMs));
    }

    // Re-point DM history (messages are immutable — rebuild the rows,
    // preserving id/timestamps so ordering and per-row actions survive).
    final String fromPrefix = fromPubKeyHex.length >= 12
        ? fromPubKeyHex.substring(0, 12)
        : fromPubKeyHex;
    bool msgChanged = false;
    for (int i = 0; i < _messages.length; i++) {
      final ChatMessage m = _messages[i];
      if (m.peerPubKeyHex != null &&
          (m.peerPubKeyHex == fromPubKeyHex ||
              m.peerPubKeyHex == fromPrefix)) {
        _messages[i] = ChatMessage(
          id: m.id,
          channelIdx: m.channelIdx,
          text: m.text,
          outgoing: m.outgoing,
          at: m.at,
          snrDb: m.snrDb,
          isFlood: m.isFlood,
          peerPubKeyHex: toPubKeyHex,
          delivery: m.delivery,
          expectedAck: m.expectedAck,
        );
        msgChanged = true;
      }
    }
    if (msgChanged) {
      _invalidateMessagesCache();
      _persistChat();
    }

    // The stale identity is dead — drop it so it stops cluttering the
    // fabric and can't be messaged again. Remember it as superseded so the
    // re-synced old contact is pruned on every ingest from here on...
    _nodes.remove(fromPubKeyHex);
    _contacts.remove(fromPubKeyHex);
    _superseded.add(fromPubKeyHex);
    unawaited(SupersededStore.save(_superseded));
    notifyListeners();
    // ...and actively REMOVE it from the radio's contact table, freeing the
    // slot the dead key held (the table is finite — a full table is what
    // makes adding the new key fail with ERR_CODE_TABLE_FULL).
    if (isReady && fromPubKeyHex.length == kPubKeySize * 2) {
      unawaited(removeDeviceContact(fromPubKeyHex));
    }
  }

  /// Count of **inbound** DMs from this peer that arrived after the
  /// last time we marked the thread read. Drives the unread state of
  /// the Nodes-row DM badge.
  int unreadDmCountFor(String peerPubKeyHex) {
    final int last = _dmReadStore.lastReadAtMs(peerPubKeyHex);
    int n = 0;
    for (final ChatMessage m in dmHistoryFor(peerPubKeyHex)) {
      if (m.outgoing) continue;
      if (m.at.millisecondsSinceEpoch > last) n++;
    }
    return n;
  }

  /// Mark all current DM messages with [peerPubKeyHex] as read. Called
  /// from `DmScreen.initState` so opening a thread clears its unread
  /// badge. Fire-and-forget — never blocks the UI.
  void markDmRead(String peerPubKeyHex) {
    unawaited(_dmReadStore.markRead(peerPubKeyHex).then((_) {
      notifyListeners();
    }));
  }

  /// Send a DM (`CMD_SEND_TXT_MSG` 0x02, addressed by 6-byte pubkey
  /// prefix). Optimistically appends an outgoing line. No-op if not
  /// ready, text is blank, or the peer hex is shorter than 12 chars.
  /// Returns the outgoing row (so a caller can follow its delivery),
  /// or null when nothing was sent.
  /// [urgent] takes the frame out of the app's own duty-cycle refusal. An
  /// alarm or a check-in must never be silenced by a budget this app invented
  /// for itself, so those sends are always written; they are still charged, so
  /// the meter keeps telling the truth. The same reasoning as link maintenance
  /// in [send], for a stronger reason.
  /// True while a message to [peerPubKeyHex] has not settled.
  ///
  /// The firmware keeps eight pending ACKs in a circular table, and a second
  /// message to the same contact can overwrite the first one's entry, which
  /// loses the ability to attribute the ACK rather than the message. The
  /// published rule is therefore **one in-flight message per contact**; this is
  /// that rule, checked against the rows the app already tracks. `unknown`
  /// counts as unsettled because the radio may still be holding the entry; it
  /// resolves to `failed` on its own grace timer, so the block is bounded.
  /// How many outgoing messages are waiting for an answer, of any kind.
  ///
  /// Half the firmware's eight-entry ACK table: a message the radio cannot keep
  /// an entry for is a message whose ACK cannot be attributed, and a lost entry
  /// is worse than a refused send the caller can see.
  static const int kMaxInFlightMessages = 4;

  int get unsettledOutgoingCount {
    int n = 0;
    for (final ChatMessage m in _messages) {
      if (!m.outgoing) continue;
      if (m.delivery == MessageDelivery.sending ||
          m.delivery == MessageDelivery.sent ||
          m.delivery == MessageDelivery.unknown) {
        n++;
      }
    }
    return n;
  }

  bool hasUnsettledDmTo(String peerPubKeyHex) {
    final String peer = peerPubKeyHex.toLowerCase();
    for (final ChatMessage m in _messages) {
      if (!m.outgoing || m.peerPubKeyHex?.toLowerCase() != peer) continue;
      if (m.delivery == MessageDelivery.sending ||
          m.delivery == MessageDelivery.sent ||
          m.delivery == MessageDelivery.unknown) {
        return true;
      }
    }
    return false;
  }

  Future<ChatMessage?> sendDirectText(
      String peerPubKeyHex, String text, {bool urgent = false}) async {
    final String t = text.trim();
    if (t.isEmpty || !isReady || peerPubKeyHex.length < 12) return null;
    // The firmware keeps eight pending ACKs in one circular table, so a ninth
    // in-flight message evicts the oldest entry and that message can no longer
    // be attributed. The app keeps to half of it, leaving room for anything the
    // radio is doing itself. The composer additionally refuses a *second*
    // message to the same contact while one is unsettled ([hasUnsettledDmTo]),
    // which is the published client rule; this ceiling is the backstop for
    // callers that are not a composer.
    if (unsettledOutgoingCount >= kMaxInFlightMessages) return null;
    final List<int> prefix = <int>[
      for (int i = 0; i < 12; i += 2)
        int.parse(peerPubKeyHex.substring(i, i + 2), radix: 16),
    ];
    final int ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    // Optimistic row first (status: sending) so the user sees the
    // message and its in-flight glyph immediately; promote it as the
    // device confirm / recipient ack arrive.
    final ChatMessage m = ChatMessage(
      channelIdx: -1,
      text: t,
      outgoing: true,
      peerPubKeyHex: peerPubKeyHex,
      delivery: MessageDelivery.sending,
    );
    _addMessage(m);
    _registerOutgoing(m, CommandAnswer.sent);
    notifyListeners();
    try {
      await send(gated: !urgent, MeshcoreFrameCodec.sendTextMessage(
        pubKeyPrefix: prefix,
        timestamp: ts,
        text: t,
      ));
    } catch (_) {
      _emitTaskError('sendDm');
      _markOutgoingFailed(m.id);
      notifyListeners();
    }
    return m;
  }

  /// Re-send an outgoing message whose delivery did not settle in its
  /// favour (same text, same channel or peer), reusing its row so the
  /// history does not fill with copies. Re-arms the same delivery tracking
  /// as a first send. Returns false when the row is not a `failed` or
  /// `unknown` outgoing message or the radio is not ready.
  ///
  /// `unknown` retries too, and that is the point of keeping it distinct
  /// from `failed`: a send the app could not vouch for is exactly the row a
  /// user wants to try again, and refusing to retry it would leave a
  /// timed-out message with no action at all. The text may already have
  /// reached the mesh, so it can arrive twice; the user chose that by
  /// tapping Retry.
  Future<bool> retryMessage(String id) async =>
      await retryMessageOutcome(id) != RetryOutcome.refused;

  /// A retry, with what it did, so the screen can say it.
  ///
  /// A direct message that timed out was addressed down the radio's stored
  /// route. The firmware replaces that route wholesale with whatever the newest
  /// path return said and never ages it out, so a route that has died stays
  /// dead: retrying down it fails again in exactly the same way. Clearing it
  /// (`CMD_RESET_PATH` 0x0D) makes this attempt go out flooded, which is also
  /// how the radio learns a fresh route from the reply. The row is reused, so
  /// the user sees one message retried rather than a duplicate.
  Future<RetryOutcome> retryMessageOutcome(String id) async {
    final ChatMessage? m = _messageById(id);
    if (m == null ||
        !m.outgoing ||
        (m.delivery != MessageDelivery.failed &&
            m.delivery != MessageDelivery.unknown) ||
        !isReady) {
      return RetryOutcome.refused;
    }
    final int ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final bool dm = m.peerPubKeyHex != null;
    final String? peer = m.peerPubKeyHex;
    if (dm && peer!.length < 12) return RetryOutcome.refused;
    bool resetRoute = false;
    if (dm) {
      final Contact? c = _contacts[peer!];
      // `directPath == null` means flood/unknown, where a reset changes
      // nothing; a non-null path is a route that just failed to deliver.
      if (c != null && c.directPath != null) {
        try {
          await send(MeshcoreFrameCodec.resetPath(c.publicKey));
          resetRoute = true;
          // Re-read the record so the app's copy says "no route" like the
          // radio now does, instead of holding a path that no longer exists.
          unawaited(send(MeshcoreFrameCodec.getContactByKey(c.publicKey))
              .catchError((Object _) => Uint8List(0)));
        } catch (_) {
          // The retry is still worth sending down the old route.
        }
      }
    }
    m
      ..delivery = MessageDelivery.sending
      ..failReason = null
      ..expectedAck = null;
    _registerOutgoing(m, dm ? CommandAnswer.sent : CommandAnswer.ok);
    _deliveryRevision++;
    _persistChat();
    notifyListeners();
    try {
      await send(
          dm
          ? MeshcoreFrameCodec.sendTextMessage(
              pubKeyPrefix: <int>[
                for (int i = 0; i < 12; i += 2)
                  int.parse(peer!.substring(i, i + 2), radix: 16),
              ],
              timestamp: ts,
              text: m.text,
            )
          : MeshcoreFrameCodec.sendChannelTextMessage(
              channelIdx: m.channelIdx,
              timestamp: ts,
              text: m.text,
            ),
          gated: true);
    } on AirtimeRefused {
      _failOutgoing(m.id, 'airtime budget',
          cause: FailureCause.airtimeBudget);
      notifyListeners();
    } catch (_) {
      _emitTaskError(dm ? 'sendDm' : 'sendChannel');
      _markOutgoingFailed(m.id);
      notifyListeners();
    }
    return resetRoute ? RetryOutcome.sentAfterPathReset : RetryOutcome.sent;
  }

  /// Ingest an inbound DM into the message store + emit on the
  /// stream. Resolves the 6-byte sender prefix to a known fabric
  /// node's full pubkey if possible; falls back to storing under
  /// the 12-hex prefix.
  /// Keys of the inbound messages just ingested, so a re-delivery is not a
  /// second row.
  ///
  /// The protocol has no message identifier. A received message is identified
  /// by its sender's prefix, the sender's own timestamp and its text, and the
  /// radio's queue re-sends anything it never saw acknowledged: after a crash
  /// or a dropped link the same message is delivered again, and appending it
  /// puts the same words on screen twice with no way for the reader to tell a
  /// duplicate from a repeat. Two genuinely identical messages inside one
  /// second are indistinguishable in the protocol itself, and dropping the
  /// second is the cheaper error than a guaranteed duplicate on every drain.
  ///
  /// Bounded, because it is a memory of the last few drains, not a history.
  final List<String> _recentInbound = <String>[];
  static const int _recentInboundCap = 64;

  bool _seenInbound(String key) {
    if (_recentInbound.contains(key)) return true;
    _recentInbound.add(key);
    if (_recentInbound.length > _recentInboundCap) _recentInbound.removeAt(0);
    return false;
  }

  void _ingestDm(MeshcoreInbound f) {
    if (f is! ContactMessageFrame) return;
    final ContactMessage cm = f.message;
    final String prefixHex = _hex(cm.pubKeyPrefix);
    if (_seenInbound('d|$prefixHex|${cm.timestamp}|${cm.text}')) return;
    String? peer;
    for (final DiscoveredNode n in _nodes.values) {
      if (n.pubKeyHex.startsWith(prefixHex)) {
        peer = n.pubKeyHex;
        break;
      }
    }
    final ChatMessage m = ChatMessage(
      channelIdx: -1,
      text: cm.text,
      outgoing: false,
      snrDb: cm.snrDb,
      isFlood: cm.isFlood,
      peerPubKeyHex: peer ?? prefixHex,
    );
    _addMessage(m);
    if (!_incomingDm.isClosed) _incomingDm.add(m);
  }

  /// On a received DM (`ContactMessageFrame`), mark any fabric node
  /// whose pubkey starts with the sender's 6-byte prefix as **known**
  /// (R18: direct/attributable comms → pulse on the grid). If no
  /// matching node yet exists, the mark won't apply until the contact
  /// is surfaced (a future polish could queue pending prefixes).
  void _ingestKnown(MeshcoreInbound f) {
    if (f is! ContactMessageFrame) return;
    final String prefix = _hex(f.message.pubKeyPrefix);
    bool changed = false;
    for (final DiscoveredNode n in _nodes.values) {
      if (n.pubKeyHex.startsWith(prefix) &&
          !_known.contains(n.pubKeyHex)) {
        _known.add(n.pubKeyHex);
        changed = true;
      }
    }
    if (changed) unawaited(KnownStore.save(_known));
  }

  void _ingestChat(MeshcoreInbound f) {
    if (f is ChannelMessageFrame) {
      final ChannelMessage cm = f.message;
      // Same rule as a direct message: the queue can deliver one twice, and a
      // channel row is no less a duplicate for having no key on it.
      if (_seenInbound('c|${cm.channelIdx}|${cm.timestamp}|${cm.text}')) return;
      final ChatMessage m = ChatMessage(
        channelIdx: cm.channelIdx,
        text: cm.text,
        outgoing: false,
        snrDb: cm.snrDb,
        isFlood: cm.isFlood,
      );
      _addMessage(m);
      if (!_incomingCh.isClosed) _incomingCh.add(m);
    } else if (f is ChannelInfoFrame) {
      final ChannelInfo ci = f.info;
      if (ci.name.isNotEmpty) {
        _channels[ci.channelIdx] = ci.name;
        _invalidateChannelsCache();
      }
      // Cache the PSK so the Edit dialog can offer "Show current
      // key" without re-querying the device every time. The codec
      // carries 16 bytes — the AES-128 key. We store a defensive
      // copy because Uint8List can be a view.
      _channelPsks[ci.channelIdx] = List<int>.unmodifiable(ci.psk);
      // The next slot is only asked for once this one has answered: the
      // firmware serialises replies, so a burst would overtake itself. The walk
      // skips slots it has already asked for, so a late or repeated reply
      // cannot make it ask twice.
      _channelProbeAnswered();
    }
  }

  // -------------------------------------------------------------------
  // R51 — social activity heat (sns-cells view). Buckets observed
  // messages into geographic cells and scores them by time-decayed
  // density. DMs land at the (located) sender's cell; channel
  // messages are anonymous in MeshCore so they land at our own cell
  // (the message reached us *here*).
  // -------------------------------------------------------------------

  final MessageHeatTracker _heat = MessageHeatTracker();

  /// cellKey → hotness in [0, 1] over the last hour. Pruned on read.
  Map<String, double> messageHeatScores() => _heat.scores();

  /// cellKey → raw message count over the last hour. Pruned on read.
  Map<String, int> messageHeatCounts() => _heat.counts();

  /// Most recently observed message (drives the sns-cells toast).
  HeatPing? get lastHeatPing => _heat.lastPing;

  /// Wipe all accumulated social heat (sns-cells "clear" control).
  void clearMessageHeat() {
    _heat.clear();
    notifyListeners();
  }

  // -------------------------------------------------------------------
  // R54 — place names in messages. A channel's messages are scanned for
  // place names and a row that names one offers to report it. Nothing is
  // plotted and no position is derived from the words: the offer carries a
  // name, and the pin comes from the user's own position when they accept.
  // Per-channel opt-in (default on for the public channel).
  // -------------------------------------------------------------------

  final PlaceInferenceEngine _placeEngine;
  Map<int, bool> _placeInferOverrides = <int, bool>{};

  Future<void> _loadPlaceInferPrefs() async {
    // The read wins over the defaults, never over a choice the user already
    // made in this session: the load is asynchronous, so a switch flipped
    // while it was in flight would otherwise be silently undone by the file.
    _placeInferOverrides = <int, bool>{
      ...await PlaceInferencePrefs.overrides(),
      ..._placeInferOverrides,
    };
    _dismissedSuggestions = <String>{
      ...await PlaceSuggestionDismissals.load(),
      ..._dismissedSuggestions,
    };
    notifyListeners();
  }

  /// Whether place inference is enabled for [channelIdx] (explicit
  /// override, else the default: on only for the public channel).
  bool placeInferenceEnabled(int channelIdx) =>
      _placeInferOverrides[channelIdx] ??
      PlaceInferencePrefs.defaultFor(channelIdx);

  Future<void> setPlaceInferenceEnabled(int channelIdx, bool enabled) async {
    _placeInferOverrides = <int, bool>{
      ..._placeInferOverrides,
      channelIdx: enabled,
    };
    notifyListeners();
    await PlaceInferencePrefs.save(_placeInferOverrides);
  }

  /// The place a chat row may offer to report, or null.
  ///
  /// This is what the per-channel inference switch actually controls now. It
  /// names a place and stops there: no coordinates are derived, nothing is
  /// drawn on a map, and the row offers the name to the person who can put a
  /// position on it. A name the user already dismissed for these words is not
  /// offered again.
  String? placeSuggestionFor(ChatMessage m) {
    if (m.outgoing) return null;
    if (!placeInferenceEnabled(m.channelIdx)) return null;
    if (_dismissedSuggestions
        .contains(PlaceSuggestionDismissals.keyFor(m.channelIdx, m.text))) {
      return null;
    }
    if (_placeNameMemo.containsKey(m.text)) return _placeNameMemo[m.text];
    final List<String> names = _placeEngine.placeNames(m.text);
    final String? name = names.isEmpty ? null : names.first;
    // The chat rebuilds rows constantly; the scan is a set of regexes plus a
    // gazetteer lookup, so one answer per distinct text is cached and the
    // cache is thrown away rather than grown without bound.
    if (_placeNameMemo.length >= 500) _placeNameMemo.clear();
    _placeNameMemo[m.text] = name;
    return name;
  }

  /// Remember that these words are not a place, so the row stops offering it.
  Future<void> dismissPlaceSuggestion(ChatMessage m) async {
    _dismissedSuggestions = <String>{
      ..._dismissedSuggestions,
      PlaceSuggestionDismissals.keyFor(m.channelIdx, m.text),
    };
    notifyListeners();
    await PlaceSuggestionDismissals.save(_dismissedSuggestions);
  }

  Set<String> _dismissedSuggestions = <String>{};
  final Map<String, String?> _placeNameMemo = <String, String?>{};

  // --- Microclimate / wx (P2): located weather observations -----------
  // Microclimates are *reprocessed from persisted chat history* (a rolling
  // 24h window) rather than only tracked live, so a summary is available the
  // moment the grid is reopened — including last night's chatter — without
  // background collection. Per-message location resolution is memoised by
  // message id so re-scanning each notify stays cheap.
  static const Duration _wxWindow = Duration(hours: 24);
  final Map<String, WxObservation?> _wxLocateMemo = <String, WxObservation?>{};

  /// Resolve one chat message to a *located* weather observation, or null
  /// when it carries no (confident) weather or can't be placed. Memoised by
  /// message id. Placement: (1) an explicit place in the text (reuse place
  /// inference against our origin), else (2) the sender's node GPS.
  WxObservation? _locatedObsFor(ChatMessage m) {
    return _wxLocateMemo.putIfAbsent(m.id, () {
      final WxObservation? obs = WeatherInferenceEngine.scanAny(m.text,
          at: m.at, sourceMsgId: m.id);
      if (obs == null || obs.confidence < 0.5) return null;

      double? lat, lon;
      String? name;
      final OwnLocation? own = ownLocation;
      if (own != null) {
        final List<InferredPlace> hits = _placeEngine.infer(m.text,
            originLat: own.latitude, originLon: own.longitude);
        if (hits.isNotEmpty) {
          lat = hits.first.latitude;
          lon = hits.first.longitude;
          name = hits.first.displayName;
        }
      }
      if (lat == null) {
        final DiscoveredNode? sender = _resolveChannelSender(m.text);
        if (sender != null && sender.hasLocation) {
          lat = sender.latitude;
          lon = sender.longitude;
          name = sender.name;
        }
      }
      if (lat == null || lon == null) return null; // unlocated → ambient-only
      return obs.locatedAt(lat, lon, name);
    });
  }

  /// Per-place microclimates mined from [channelIdx]'s located weather
  /// chatter over the rolling 24h window (P2), rebuilt from chat history so
  /// it survives a reopen. P3 — each place is cross-referenced against real
  /// sensor telemetry: when a node *at* that place reports an environment
  /// temp, it's preferred and the bubble is flagged `measured`.
  List<Microclimate> microclimatesFor(int channelIdx) {
    final DateTime cutoff = DateTime.now().subtract(_wxWindow);
    final List<WxObservation> located = <WxObservation>[];
    for (final ChatMessage m in messagesFor(channelIdx)) {
      if (m.at.isBefore(cutoff)) continue;
      final WxObservation? o = _locatedObsFor(m);
      if (o != null) located.add(o);
    }
    if (located.isEmpty) return const <Microclimate>[];
    final List<Microclimate> base = aggregateMicroclimates(located);
    return <Microclimate>[
      for (final Microclimate m in base)
        () {
          final double? t = _measuredTempNear(m.lat, m.lon);
          return t == null ? m : m.withMeasured(t);
        }()
    ];
  }

  // --- Meshbook (MBk P3): persisted per-channel daily analysis --------
  final MeshbookStore _meshbook = MeshbookStore();
  Timer? _meshbookSaveTimer;

  void _saveMeshbookSoon() {
    _meshbookSaveTimer?.cancel();
    _meshbookSaveTimer =
        Timer(const Duration(seconds: 3), () => unawaited(_meshbook.save()));
  }

  /// Rolling last-24h channel-activity analysis for [channelIdx] — top
  /// voices, hourly volume, reply rate, topics. Backed by [MeshbookStore]
  /// (per channel, persisted, rolling 24h window); seeds from history on
  /// each launch then accumulates live, so a morning reopen still shows last
  /// night's activity even though collection doesn't run in the background.
  MbkDay meshbookFor(int channelIdx) {
    _meshbook.seed(channelIdx, messagesFor(channelIdx));
    return _meshbook.build(channelIdx);
  }

  bool meshbookHasData(int channelIdx) =>
      _meshbook.channelHasData(channelIdx);

  /// Clear stored Meshbook data — one channel, or all when null.
  Future<void> clearMeshbook({int? channelIdx}) async {
    if (channelIdx == null) {
      _meshbook.clearAll();
    } else {
      _meshbook.clearChannel(channelIdx);
    }
    await _meshbook.save();
    notifyListeners();
  }

  /// Nearest sensor-reported temperature (°C) to ([lat],[lon]) within
  /// ~5 km, or null. Bridges to the (otherwise shelved) environment
  /// telemetry path without depending on it.
  double? _measuredTempNear(double lat, double lon) {
    const double maxMeters = 5000;
    double? best;
    double bestDist = maxMeters;
    for (final DiscoveredNode n in _nodes.values) {
      if (!n.hasLocation) continue;
      final NodeTelemetry? t = telemetryFor(n.pubKeyHex);
      if (t == null || !t.hasEnvironment || t.temperatureC == null) continue;
      final double d =
          geo.haversineMeters(lat, lon, n.latitude!, n.longitude!);
      if (d < bestDist) {
        bestDist = d;
        best = t.temperatureC;
      }
    }
    return best;
  }

  // --- Channel datagrams (`CMD_SEND_CHANNEL_DATA` / `0x1B`) ---
  //
  // The frame has decoded for a while; nothing consumed it. Every media and
  // place payload will arrive this way, and the data type is the only thing
  // that says which layer owns the bytes. The firmware forwards a type it
  // does not know (`MyMesh.cpp:592-625`), so an unrecognised type is kept
  // and counted rather than dropped: a dropped datagram looks exactly like
  // one that never arrived.

  static const int _channelDatagramCap = 32;
  final List<ChannelDatagram> _channelDatagrams = <ChannelDatagram>[];
  final StreamController<ChannelDatagram> _channelDatagramStream =
      StreamController<ChannelDatagram>.broadcast();
  int _channelDatagramsUnrecognised = 0;

  /// Recent channel datagrams, oldest first, capped at
  /// [_channelDatagramCap].
  List<ChannelDatagram> get channelDatagrams =>
      List<ChannelDatagram>.unmodifiable(_channelDatagrams);

  /// Every channel datagram as it arrives, for the layers that own a type.
  Stream<ChannelDatagram> get channelDatagramStream =>
      _channelDatagramStream.stream;

  /// Datagrams whose type this build does not interpret. They are still
  /// delivered; the count exists so diagnostics can show that a payload
  /// arrived and was not understood, instead of the two cases looking alike.
  int get channelDatagramsUnrecognised => _channelDatagramsUnrecognised;

  void _ingestChannelData(MeshcoreInbound f) {
    if (f is! ChannelDataFrame) return;
    final ChannelDatagram d = ChannelDatagram(
      channelIndex: f.channelIndex,
      dataType: f.dataType,
      blob: f.data,
      rxVia: f.via,
      snrDb: f.snrDb,
      pathLen: f.pathLen,
      receivedAt: DateTime.now(),
    );
    if (d.dataType != kChannelDataTypeDev) _channelDatagramsUnrecognised++;
    _channelDatagrams.add(d);
    if (_channelDatagrams.length > _channelDatagramCap) {
      _channelDatagrams.removeAt(0);
    }
    if (!_channelDatagramStream.isClosed) _channelDatagramStream.add(d);
  }

  void _trackMessageHeat(MeshcoreInbound f) {
    if (f is ContactMessageFrame) {
      // DM: resolve sender by 6-byte prefix; place heat at the
      // sender's known location when we have one.
      final ContactMessage cm = f.message;
      final String prefixHex = _hex(cm.pubKeyPrefix);
      DiscoveredNode? sender;
      for (final DiscoveredNode n in _nodes.values) {
        if (n.pubKeyHex.startsWith(prefixHex)) {
          sender = n;
          break;
        }
      }
      _heat.record(
        text: cm.text,
        atUnix: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        lat: sender?.hasLocation == true ? sender!.latitude : null,
        lon: sender?.hasLocation == true ? sender!.longitude : null,
        pubKeyHex: sender?.pubKeyHex,
        isChannel: false,
      );
    } else if (f is ChannelMessageFrame) {
      // Channel messages have no sender *field*, but MeshCore
      // firmware prepends the sender's name to the text as
      // "name: message" (sprintf "%s: " in sendGroupMessage). So we
      // can attribute by name: parse the prefix, match it to a
      // single known node, and place the heat at *that* node — same
      // as a DM. Falls back to our own cell when the name is
      // missing, unmatched, ambiguous, or the matched node has no
      // location. Attribution is advisory (channel text isn't
      // per-sender signed), which is fine for a social heat map.
      final ChannelMessage cm = f.message;
      final DiscoveredNode? sender = _resolveChannelSender(cm.text);
      final bool located = sender?.hasLocation == true;
      final OwnLocation? own = ownLocation;
      _heat.record(
        text: cm.text,
        atUnix: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        lat: located ? sender!.latitude : own?.latitude,
        lon: located ? sender!.longitude : own?.longitude,
        pubKeyHex: located ? sender!.pubKeyHex : null,
        isChannel: true,
      );
    }
  }

  /// Parse the "name: …" prefix MeshCore prepends to channel text and
  /// resolve it to a single known node. Returns null when there's no
  /// prefix, no match, or an ambiguous (>1) match — name strings
  /// aren't unique or authenticated, so we only attribute on an
  /// unambiguous hit.
  DiscoveredNode? _resolveChannelSender(String text) {
    final String? name = parseChannelSenderName(text);
    if (name == null) return null;
    final String want = name.toLowerCase();
    DiscoveredNode? hit;
    for (final DiscoveredNode n in _nodes.values) {
      if (n.name.toLowerCase() == want) {
        if (hit != null) return null; // ambiguous — bail
        hit = n;
      }
    }
    return hit;
  }

  /// Set the device clock to the phone's wall clock so device-sourced
  /// timestamps (contact `lastAdvertTimestamp`, message times) are
  /// comparable to "now" — fixes nodes showing "known" but never
  /// "in range". Best-effort.
  ///
  /// The firmware only moves its clock forward (`MyMesh.cpp:1247-1257`,
  /// `CMD_SET_DEVICE_TIME`: `secs >= curr` else `ERR_CODE_ILLEGAL_ARG`). A
  /// radio whose clock already leads the phone therefore refuses every write,
  /// which is a normal state after a reboot onto a device that kept time, not
  /// a fault. The ERR is expected, so it is squelched exactly like a probing
  /// `setCustomVar`; without this every connect ended with "device error (code
  /// illegal argument)" in the activity feed, which reads as a fault and is
  /// the kind of noise that teaches a user to ignore the feed.
  void _syncDeviceTime() {
    final int nowUnix = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    _squelchNextDeviceError++;
    unawaited(
        send(MeshcoreFrameCodec.setDeviceTime(nowUnix)).catchError((_) {}));
  }

  /// Phone-clock minus device-clock, in seconds. 0 until a CURR_TIME
  /// reply is seen; once known it translates device-sourced
  /// timestamps (contact `lastAdvertTimestamp`) to phone "now" so
  /// "in range" is correct even when SET_DEVICE_TIME was rejected.
  int _deviceClockOffsetSec = 0;

  void _requestDeviceTime() {
    unawaited(
        send(MeshcoreFrameCodec.getDeviceTime()).catchError((_) {}));
  }

  /// True once this session has offered the phone's clock to the device.
  /// One offer is enough: the write either moved the device forward or the
  /// firmware refused it for being behind, and repeating it would only
  /// produce the same answer and the same noise.
  bool _clockOffered = false;

  void _trackDeviceClock(MeshcoreInbound f) {
    if (f is! CurrentTimeFrame || f.unixSeconds <= 0) return;
    final int phoneNow = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    _deviceClockOffsetSec = phoneNow - f.unixSeconds;
    // The device is a couple of seconds behind: offer the phone's clock. A
    // device that is ahead is left alone, because the firmware would refuse.
    if (!_clockOffered && _deviceClockOffsetSec > 2) {
      _clockOffered = true;
      _syncDeviceTime();
    }
    // Re-derive freshness for contacts that arrived before we knew
    // the offset (GET_CONTACTS reply can precede CURR_TIME).
    for (final DiscoveredNode n in _nodes.values) {
      final int? adv = n.deviceAdvertUnix;
      if (adv != null && adv != 0) {
        n.lastHeardUnix = adv + _deviceClockOffsetSec;
      }
    }
  }

  // --- Battery (R16) ---

  BatteryStorage? _battery;
  final List<List<int>> _battSamples = <List<int>>[]; // [mv, atUnix]
  static const int _battSampleCap = 6;
  bool? _charging;
  Timer? _battTimer;

  /// Latest battery/storage reading, null until the first GET_BATTERY.
  BatteryStorage? get battery => _battery;
  int? get batteryMillivolts => _battery?.batteryMillivolts;
  double? get batteryVolts => _battery?.batteryVolts;

  /// Approx single-cell Li-ion charge (3.30 V→0 %, 4.20 V→100 %).
  /// Indicative only — the companion protocol exposes voltage, not a
  /// fuel gauge.
  int? get batteryPercent {
    final int? mv = batteryMillivolts;
    if (mv == null) return null;
    return ((mv - 3300) / (4200 - 3300) * 100).clamp(0, 100).round();
  }

  /// True only on a clear, sustained voltage rise; false on a clear
  /// fall; null when steady/unknown. companion-v1.15.0 has no
  /// charge-state bit, so this never asserts charging on ADC noise
  /// (R16: never show a false charging state).
  bool? get charging => _charging;

  void _requestBattery() {
    unawaited(
        send(MeshcoreFrameCodec.getBatteryStorage()).catchError((_) {}));
  }

  void _startBatteryPolling() {
    _battTimer?.cancel();
    _requestBattery();
    _battTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (isReady && _visible) _requestBattery();
    });
  }

  // --- Battery-life estimation (per-device history + spec) ---
  //
  // The companion protocol only gives us pack voltage, so runtime is
  // estimated from voltage-over-time (observed drain) plus a per-
  // device nameplate cross-check. History is persisted per device so
  // the estimate survives restarts; see [BatteryHistoryStore] and
  // [estimateBattery].

  final Map<String, List<BatterySample>> _battHistory =
      <String, List<BatterySample>>{};
  bool _battHistoryDirty = false;
  Timer? _battHistorySaveTimer;
  DevicePowerSpecs _powerSpecs = DevicePowerSpecs.builtin;

  /// Own 12-hex-char pubkey prefix (pub6), or null before SelfInfo.
  String? get _ownPub6 {
    final String? hex = ownPubKeyHex;
    if (hex == null || hex.length < kPubKeyPrefixSize * 2) return null;
    return hex.substring(0, kPubKeyPrefixSize * 2);
  }

  Future<void> _loadBatteryHistory() async {
    final Map<String, List<BatterySample>> v =
        await BatteryHistoryStore.load();
    if (v.isEmpty) return;
    _battHistory
      ..clear()
      ..addAll(v);
    notifyListeners();
  }

  Future<void> _loadPowerSpecs() async {
    try {
      final String raw =
          await rootBundle.loadString('assets/data/device_power_specs.json');
      _powerSpecs = DevicePowerSpecs.parse(raw);
      notifyListeners();
    } catch (_) {
      // No asset bundle (e.g. a plain unit test) — keep the built-in
      // generic fallback. The estimator still works, observed-only.
      _powerSpecs = DevicePowerSpecs.builtin;
    }
  }

  /// Power spec resolved for the connected device, matched on the
  /// DeviceInfo manufacturer / firmware strings. Always non-null (the
  /// generic single-cell Li-ion fallback when nothing matches).
  DevicePowerSpec get resolvedPowerSpec => _powerSpecs.resolve(
        manufacturer: _deviceInfo?.manufacturer,
        firmware: _deviceInfo?.firmwareVersion,
      );

  /// Persisted voltage history for the connected device, oldest
  /// first. Empty before any reading (or before SelfInfo identifies
  /// us).
  List<BatterySample> get batteryHistory {
    final String? pub = _ownPub6;
    if (pub == null) return const <BatterySample>[];
    return List<BatterySample>.unmodifiable(
        _battHistory[pub] ?? const <BatterySample>[]);
  }

  /// Current battery-life estimate for the connected device. Folds
  /// the persisted voltage history, the resolved device spec, and the
  /// charging trend into a single [BatteryEstimate].
  BatteryEstimate get batteryEstimate {
    final List<BatterySample> hist = batteryHistory;
    if (hist.isEmpty) {
      // Fall back to the latest live reading even before it's been
      // decimated into the persisted history, so the screen isn't
      // blank on a fresh connect.
      final int? mv = batteryMillivolts;
      if (mv == null) return BatteryEstimate.empty;
      final int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      return estimateBattery(
        samples: <BatterySample>[(atUnix: now, millivolts: mv)],
        spec: resolvedPowerSpec,
        charging: _charging,
      );
    }
    return estimateBattery(
      samples: hist,
      spec: resolvedPowerSpec,
      charging: _charging,
      nowUnix: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
  }

  void _recordBatterySample(int millivolts, int nowUnix) {
    final String? pub = _ownPub6;
    if (pub == null) return; // can't attribute without SelfInfo yet
    final List<BatterySample> list =
        _battHistory.putIfAbsent(pub, () => <BatterySample>[]);
    // Decimate: keep at most one stored sample per minInterval.
    if (list.isNotEmpty &&
        nowUnix - list.last.atUnix < BatteryHistoryStore.minIntervalSec) {
      return;
    }
    list.add((atUnix: nowUnix, millivolts: millivolts));
    while (list.length > BatteryHistoryStore.maxSamplesPerDevice) {
      list.removeAt(0);
    }
    // Evict the least-recently-updated device when over the cap.
    while (_battHistory.length > BatteryHistoryStore.maxDevices) {
      String? oldestPub;
      int oldestTs = 1 << 62;
      _battHistory.forEach((String k, List<BatterySample> s) {
        final int t = s.isEmpty ? 0 : s.last.atUnix;
        if (t < oldestTs) {
          oldestTs = t;
          oldestPub = k;
        }
      });
      if (oldestPub == null || oldestPub == pub) break;
      _battHistory.remove(oldestPub);
    }
    _battHistoryDirty = true;
    _battHistorySaveTimer ??=
        Timer(const Duration(seconds: 10), _flushBatteryHistory);
    // No notify here: this runs inside the frame pipeline, and that pipeline
    // notifies once per frame (coalesced during a burst). A second notify
    // from in here rebuilt every watcher twice for one battery push.
  }

  Future<void> _flushBatteryHistory() async {
    _battHistorySaveTimer = null;
    if (!_battHistoryDirty) return;
    _battHistoryDirty = false;
    await BatteryHistoryStore.save(_battHistory);
  }

  /// Wipe the persisted battery history (all devices). Exposed for a
  /// "reset" affordance on the battery screen + tests.
  Future<void> resetBatteryHistory() async {
    _battHistory.clear();
    _battHistoryDirty = false;
    _battHistorySaveTimer?.cancel();
    _battHistorySaveTimer = null;
    await BatteryHistoryStore.clear();
    notifyListeners();
  }

  /// SelfInfo refresh timer. The MeshCore companion protocol doesn't
  /// auto-push fresh SelfInfo when the device's onboard GPS updates,
  /// so a long-running session with `advertLocPolicy = Device GPS`
  /// would show a frozen location on the dashboard. Earlier we
  /// re-sent `appStart` here, but field testing showed the firmware
  /// returns a **cached** SelfInfo to appStart — the lat/lon only
  /// refreshes when the device actually **builds an outbound
  /// advert** (which is when it reads GPS into the advert payload).
  ///
  /// The refresh sequence is now: zero-hop `sendSelfAdvert`
  /// (forces firmware to read GPS into the just-built advert) +
  /// `appStart` (pulls the freshly-updated SelfInfo back). Cadence
  /// is 60 s — bigger than the old 30 s because the advert is
  /// actual OTA traffic (single zero-hop frame, no flood, low
  /// impact but real).
  ///
  /// R62 — that advert is the periodic *beacon*, and it is now opt-in
  /// ([periodicAdvertEnabled], default off). The poll itself keeps
  /// running, because the dashboard's device-GPS readout needs it, but
  /// with the beacon off a tick sends only `appStart`: one BLE request
  /// to the paired radio, nothing over the air. Companion firmware
  /// builds SELF_INFO from the live `sensors.node_lat/lon`
  /// (`MyMesh.cpp:1059-1063`, tag companion-v1.17.1), so that is enough
  /// to see a moving GPS. Whether real GPS hardware refreshes without
  /// an advert has NOT been verified on a device; the manual refresh
  /// button on the dashboard still does the full advert + appStart.
  /// `appStart` on connect is a separate, wanted exchange and is
  /// untouched.
  Timer? _selfInfoTimer;
  final Duration _selfInfoPollInterval;

  bool _periodicAdvert = false;

  /// R62 — whether the 60 s poll also sends a position-bearing
  /// zero-hop self-advert. Persisted; default off.
  bool get periodicAdvertEnabled => _periodicAdvert;

  Future<void> _loadPeriodicAdvertPref() async {
    _periodicAdvert = await PeriodicAdvertPrefs.enabled();
    notifyListeners();
  }

  Future<void> setPeriodicAdvertEnabled(bool v) async {
    if (v == _periodicAdvert) return;
    _periodicAdvert = v;
    notifyListeners();
    await PeriodicAdvertPrefs.setEnabled(v);
  }

  void _startSelfInfoPolling() {
    _selfInfoTimer?.cancel();
    _selfInfoTimer = Timer.periodic(_selfInfoPollInterval, (_) {
      if (!isReady) return;
      if (_periodicAdvert) {
        unawaited(refreshSelfInfo());
      } else {
        unawaited(_pollSelfInfoQuietly());
      }
    });
  }

  /// `appStart` only: pull SelfInfo from the radio, transmit nothing.
  Future<void> _pollSelfInfoQuietly() async {
    try {
      await send(MeshcoreFrameCodec.appStart(appName: _connection.appName));
    } catch (_) {
      // link dropped mid-poll — best-effort, like refreshSelfInfo.
    }
  }

  /// Public API for forcing a SelfInfo refresh from the device.
  /// Sends a **zero-hop self-advert** to force the firmware to
  /// re-read its GPS into the advert payload, then `appStart` to
  /// pull the refreshed SelfInfoFrame back through the inbound
  /// listener. Safe to call repeatedly; errors are swallowed.
  Future<void> refreshSelfInfo() async {
    if (!isReady) return;
    final SelfInfo? before = selfInfo;
    meshLog('meshcore.loc', 'refreshSelfInfo fired '
        '(before: ${before == null ? 'null' : 'lat=${before.latitude} '
            'lon=${before.longitude} pol=${before.advertLocPolicy}'})');
    // **Option B** — re-send the *existing* advertLocPolicy as a
    // no-op `setOtherParams` call. The v37 trace showed the
    // firmware returning byte-identical SelfInfo across multiple
    // sendSelfAdvert+appStart cycles, suggesting the advert build
    // doesn't actually re-read GPS. Some firmware variants do
    // refresh GPS into selfInfo when handling `setOtherParams`
    // though — sending the same policy back as a no-op may shake
    // the cache loose without changing any state.
    // Wrapped in try/catch: the link can drop mid-refresh (these are
    // multiple awaited round-trips), and `send` throws *synchronously*
    // when disconnected — which a per-future `.catchError` can't
    // intercept. Swallow it; a refresh is always best-effort.
    try {
      if (before != null) {
        await setAdvertLocPolicy(before.advertLocPolicy);
      }
      // 1) Zero-hop advert triggers firmware GPS read + state update
      //    (theoretically — confirmed by the v37 capture that this
      //    alone wasn't enough).
      await sendSelfAdvert(flood: false);
      // 2) appStart re-fetches the SelfInfo response.
      await send(MeshcoreFrameCodec.appStart(
        appName: _connection.appName,
      ));
    } catch (_) {
      // link dropped or device busy — best-effort, ignore.
    }
  }

  // --- Device info + identity/advert (R7) ---

  DeviceInfo? _deviceInfo;

  /// Decoded DEVICE_INFO (firmware/build/manufacturer/limits), null
  /// until the DEVICE_QUERY reply arrives.
  DeviceInfo? get deviceInfo => _deviceInfo;

  void _requestDeviceInfo() {
    unawaited(
        send(MeshcoreFrameCodec.deviceQuery()).catchError((_) {}));
  }

  void _trackDeviceInfo(MeshcoreInbound f) {
    if (f is! DeviceInfoFrame) return;
    final bool grew = _deviceInfo == null ||
        _deviceInfo!.maxGroupChannels != f.info.maxGroupChannels;
    _deviceInfo = f.info;
    // The walk starts before the device query answers, so it begins with the
    // pessimistic four. Once the radio says how many slots it holds, carry on
    // from where the walk stopped rather than starting over.
    if (grew && state == MeshcoreConnectionState.ready) _probeNextChannel();
  }

  // --- R38: device custom variables (gps, gps_interval, …) ---
  //
  // The companion-radio firmware stores a handful of string-keyed
  // settings outside the SelfInfo bundle, queried via
  // `CMD_GET_CUSTOM_VARS` (0x28) and written one at a time with
  // `CMD_SET_CUSTOM_VAR` (0x29). The two we care about today are
  // `gps` (0/1, powers the on-board GPS module) and `gps_interval`
  // (seconds 0..86400, how often the module is polled into
  // `sensors.node_lat/lon`). Other names are surfaced verbatim so
  // future firmware additions show up in the diagnostics panel
  // without code changes.

  Map<String, String> _customVars = const <String, String>{};

  /// Counter: when > 0, the next inbound ErrorFrame is dropped from
  /// the recent-activity feed (still surfaced in raw inbound + logs).
  /// Used to absorb known-rejectable probes like setting
  /// `gps_interval` on firmware that doesn't expose the key.
  int _squelchNextDeviceError = 0;

  /// Latest device-reported custom vars (e.g. `{gps: "1",
  /// gps_interval: "30"}`). Empty until the first
  /// `CMD_GET_CUSTOM_VARS` reply.
  Map<String, String> get customVars =>
      Map<String, String>.unmodifiable(_customVars);

  /// True iff the device reports `gps=1`. Null when the device hasn't
  /// answered the custom-var query yet (or doesn't have the key).
  bool? get deviceGpsEnabled {
    final String? v = _customVars['gps'];
    if (v == null) return null;
    return v.trim() == '1';
  }

  /// Device GPS polling interval (seconds), or null if unknown.
  int? get deviceGpsIntervalSec {
    final String? v = _customVars['gps_interval'];
    if (v == null) return null;
    return int.tryParse(v.trim());
  }

  /// True if the firmware build advertises `gps_interval` as a
  /// settable custom var. Some hardware (notably the T1000-E
  /// v1.15.0 sensors implementation) only exposes `gps` and rejects
  /// writes to `gps_interval` with ERR_CODE_ILLEGAL_ARG; the
  /// polling cadence on those builds is fixed by the firmware.
  /// Null when the device hasn't replied to the initial query yet.
  bool? get supportsGpsInterval {
    if (_customVars.isEmpty) return null;
    return _customVars.containsKey('gps_interval');
  }

  void _requestCustomVars() {
    unawaited(
        send(MeshcoreFrameCodec.getCustomVars()).catchError((Object _) {}));
  }

  /// Write a single custom var. No-op if not ready. Refreshes the
  /// local cache afterwards so getters reflect the new state.
  ///
  /// If the firmware build doesn't expose [name] as a settable
  /// sensors-module key, the device replies with `ERR_CODE_ILLEGAL_ARG`
  /// (6). Set [absorbErrorFromUserFeed] to keep that ERR out of the
  /// dashboard's recent-activity feed (probing path).
  Future<void> setCustomVar({
    required String name,
    required String value,
    bool absorbErrorFromUserFeed = false,
  }) async {
    if (!isReady) return;
    if (absorbErrorFromUserFeed) _squelchNextDeviceError++;
    await send(MeshcoreFrameCodec.setCustomVar(name: name, value: value));
    // The device acknowledges with OK on accept, ERR on reject;
    // either way re-query so getters reflect the canonical state
    // (firmware constrains gps_interval to 0..86400, etc.).
    _requestCustomVars();
  }

  bool _autoEnabledGpsOnce = false;

  /// One-shot auto-heal: if the user has chosen the **live/GPS** advert
  /// policy but the firmware reports `gps=0`, push `gps=1` so the GPS
  /// module actually starts updating `sensors.node_lat/lon`. Without
  /// this, picking the live-position option in our Device Config screen
  /// has no effect — the firmware just keeps broadcasting whatever
  /// cached lat/lon it last had.
  ///
  /// The policy integer follows MeshCore's shared definition
  /// (`src/helpers/CommonCLI.h`: NONE 0 / SHARE 1 / PREFS 2) and our
  /// "Device GPS" label is 1. The companion firmware itself only tests
  /// `== ADVERT_LOC_NONE` (`MyMesh.cpp:1252,1336,2251` at
  /// `companion-v1.17.1`), so policy 2 also advertises the live
  /// `sensors.node_lat/lon`; this auto-heal deliberately keys off the
  /// user's explicit "Device GPS" choice only.
  Future<void> _maybeAutoEnableGps() async {
    if (_autoEnabledGpsOnce) return;
    final SelfInfo? si = selfInfo;
    if (si == null) return;
    if (si.advertLocPolicy != 1) return; // user hasn't asked for live GPS
    final bool? on = deviceGpsEnabled;
    if (on != false) return; // already on, or unknown — leave alone
    _autoEnabledGpsOnce = true;
    meshLog('meshcore.loc', 'auto-enabling on-board GPS '
        '(advertLocPolicy=1/SHARE but gps=0)');
    await setCustomVar(name: 'gps', value: '1');
    // We intentionally don't write `gps_interval` here. On at least
    // the T1000-E v1.15.0 build the sensors module only exposes
    // `gps` and rejects `gps_interval` with ERR_CODE_ILLEGAL_ARG —
    // the firmware then surfaces a confusing "device error 6" to
    // the user. Polling cadence on hardware that doesn't accept
    // `gps_interval` is fixed by the firmware build; on hardware
    // that does accept it, the user can pick a value from the
    // Device Config screen's interval picker (only shown when the
    // device advertises the key).
  }

  void _trackCustomVars(MeshcoreInbound f) {
    if (f is! CustomVarsFrame) return;
    _customVars = Map<String, String>.from(f.values);
    meshLog('meshcore.loc', 'CustomVarsFrame in: $_customVars');
    // Defer auto-enable to the microtask queue so SelfInfo (which
    // tells us the policy) has likely landed already on a fresh
    // connect.
    unawaited(Future<void>.microtask(_maybeAutoEnableGps));
  }

  /// Set this node's advertised name (`SET_ADVERT_NAME`). No-op if not
  /// ready or blank.
  ///
  /// After the write we kick a [refreshSelfInfo] so the change takes
  /// effect end-to-end: the zero-hop self-advert pushes the new name
  /// onto the mesh immediately (rather than waiting for the next
  /// scheduled advert), and the follow-up appStart re-reads SelfInfo
  /// so the app's own surfaces (dashboard, Device config) reflect the
  /// rename without a reconnect. Fire-and-forget so callers can toast
  /// right after the name write.
  Future<void> setAdvertName(String name) async {
    final String n = name.trim();
    if (n.isEmpty || !isReady) return;
    await send(MeshcoreFrameCodec.setAdvertName(n));
    unawaited(refreshSelfInfo());
  }

  /// Set this node's advertised location (`SET_ADVERT_LATLON`), in
  /// degrees. No-op if not ready.
  ///
  /// R44 — accepts an optional [altitudeMeters]. The codec sends a
  /// 3rd i32 (alt × 1e6) when present; firmware stores it for
  /// future use. As of the v1.15.0 advert wire-format the device
  /// does **not** rebroadcast altitude in adverts (the
  /// `ADV_LATLON` block is still 2×i32), so this is forward-
  /// compatibility plumbing: when firmware grows an altitude slot,
  /// our nodes' adverts will populate it for free without an app
  /// update.
  Future<void> setAdvertLatLon({
    required double latitude,
    required double longitude,
    double? altitudeMeters,
  }) async {
    if (!isReady) return;
    await send(MeshcoreFrameCodec.setAdvertLatLon(
      latitudeMicros: (latitude * 1e6).round(),
      longitudeMicros: (longitude * 1e6).round(),
      altitudeMicros: altitudeMeters == null
          ? null
          : (altitudeMeters * 1e6).round(),
    ));
  }

  /// Set the device's **advert location policy** via `CMD_SET_OTHER_PARAMS`
  /// (`0x26`). The policy determines what the device broadcasts:
  ///   `0` = no location, `1` = pinned (manual), `2` = live GPS.
  /// (Exact integer values vary by firmware revision — the codec
  /// passes the byte through.)
  ///
  /// `SET_OTHER_PARAMS` is a *bundle* command: it always carries the
  /// first two fields (manualAddContacts, telemetryModePacked) so the
  /// device doesn't reset them. We read those + `multiAcks` back from
  /// the cached `SelfInfo` to avoid clobbering unrelated settings.
  /// No-op if not ready or if SelfInfo hasn't been received yet.
  Future<void> setAdvertLocPolicy(int policy) async {
    if (!isReady) return;
    final SelfInfo? si = selfInfo;
    if (si == null) return;
    await send(MeshcoreFrameCodec.setOtherParams(
      manualAddContacts: si.manualAddContacts ? 1 : 0,
      telemetryModePacked: si.telemetryModeRaw,
      advertLocPolicy: policy,
      multiAcks: si.multiAcks,
    ));
  }

  /// Toggle whether the device requires the user to **manually add**
  /// heard nodes as contacts (instead of auto-promoting every advert).
  /// Wraps `CMD_SET_OTHER_PARAMS` (0x26); preserves the other three
  /// fields by reading them off the cached `SelfInfo`.
  Future<void> setManualAddContacts(bool v) async {
    if (!isReady) return;
    final SelfInfo? si = selfInfo;
    if (si == null) return;
    await send(MeshcoreFrameCodec.setOtherParams(
      manualAddContacts: v ? 1 : 0,
      telemetryModePacked: si.telemetryModeRaw,
      advertLocPolicy: si.advertLocPolicy,
      multiAcks: si.multiAcks,
    ));
  }

  /// Set the device's **telemetry mode** byte. The protocol packs
  /// several flags into this single byte; semantics are firmware-
  /// dependent (env/battery/location reporting cadence + format).
  /// We expose it as a raw int so power users can match what their
  /// MeshCore docs say. 0 = telemetry off.
  Future<void> setTelemetryMode(int packed) async {
    if (!isReady) return;
    final SelfInfo? si = selfInfo;
    if (si == null) return;
    await send(MeshcoreFrameCodec.setOtherParams(
      manualAddContacts: si.manualAddContacts ? 1 : 0,
      telemetryModePacked: packed & 0xFF,
      advertLocPolicy: si.advertLocPolicy,
      multiAcks: si.multiAcks,
    ));
  }

  /// Set the device's **multi-acks** count. The radio can be asked
  /// to expect up to N additional acks before considering a send
  /// confirmed; typical range 0–3. 0 = single ack (default).
  Future<void> setMultiAcks(int n) async {
    if (!isReady) return;
    final SelfInfo? si = selfInfo;
    if (si == null) return;
    final int clamped = n.clamp(0, 7);
    await send(MeshcoreFrameCodec.setOtherParams(
      manualAddContacts: si.manualAddContacts ? 1 : 0,
      telemetryModePacked: si.telemetryModeRaw,
      advertLocPolicy: si.advertLocPolicy,
      multiAcks: clamped,
    ));
  }

  // -------------------------------------------------------------------
  // Telemetry — CMD_SEND_TELEMETRY_REQ (0x27) / PUSH_CODE_TELEMETRY_RESPONSE
  // (0x8B). Keyed by 6-byte pubkey-prefix (12-char hex). Self-telemetry
  // is the entry under our own pubkey6; peer telemetry is everything
  // else (populated only when the app explicitly queries a peer, which
  // is out of scope for v1).
  // -------------------------------------------------------------------

  final Map<String, NodeTelemetry> _telemetry = <String, NodeTelemetry>{};

  /// Telemetry for our own device, if a 0x8B push has arrived. Null
  /// before the first self-telemetry round-trip completes.
  NodeTelemetry? get selfTelemetry {
    final String? own = ownPubKeyHex;
    if (own == null) return null;
    return _telemetry[own.substring(0, kPubKeyPrefixSize * 2)];
  }

  /// Telemetry for an arbitrary node, looked up by 6-byte pubkey
  /// prefix. Accepts either the 12-char prefix or the full 64-char
  /// pubkey hex — the controller always keys by the first 6 bytes.
  NodeTelemetry? telemetryFor(String pubKeyHex) {
    final String hex = pubKeyHex.toLowerCase();
    if (hex.length < kPubKeyPrefixSize * 2) return null;
    return _telemetry[hex.substring(0, kPubKeyPrefixSize * 2)];
  }

  /// Fire a one-shot self-telemetry request. The device replies
  /// immediately (no OTA) with a 0x8B push that lands on the inbound
  /// stream and gets ingested by [_trackTelemetry]. Public so views
  /// (e.g. the elevation profile) can re-poll our own altitude on
  /// demand.
  void requestSelfTelemetry() {
    unawaited(send(MeshcoreFrameCodec.sendTelemetryReq()).catchError((_) {}));
  }

  /// Per-peer telemetry query. Sends `CMD_SEND_TELEMETRY_REQ` (0x27)
  /// with the 32-byte pubkey appended — the device unicasts the
  /// request over the air; the peer's eventual response arrives
  /// asynchronously as a `PUSH_CODE_TELEMETRY_RESPONSE` (0x8B) and is
  /// stored against the matching 6-byte prefix.
  ///
  /// Behaviour:
  /// - No-op when we have a cached entry younger than [cacheFor].
  /// - No-op when a query is already in flight for the same peer
  ///   (the inflight flag is cleared on response or [inflightTimeout]).
  /// - Accepts either the full 64-char pubkey hex or just the 12-char
  ///   prefix — the prefix is enough for cache lookup, but the full
  ///   32 bytes are needed to actually address the peer over the air.
  ///   When only a prefix is given the call is a cache-hit no-op (we
  ///   can't reach the peer without the rest of the key).
  Future<void> requestPeerTelemetry(
    String pubKeyHex, {
    Duration cacheFor = const Duration(minutes: 5),
    Duration inflightTimeout = const Duration(seconds: 45),
    int maxAttempts = 0, // 0 = no cap
  }) async {
    if (!isReady) return;
    final String hex = pubKeyHex.toLowerCase();
    if (hex.length < kPubKeyPrefixSize * 2) return;
    final String pub6 = hex.substring(0, kPubKeyPrefixSize * 2);
    final NodeTelemetry? cached = _telemetry[pub6];
    if (cached != null &&
        DateTime.now().difference(cached.receivedAt) < cacheFor) {
      return; // fresh enough
    }
    if (_telemetryInflight.contains(pub6)) return;
    // Per-session attempt cap. Lives on the controller (not the
    // view) so swapping views or restarting the elevation/auto-
    // query screen doesn't reset the count and rebombard a peer
    // that already ignored us N times.
    if (maxAttempts > 0 &&
        (_telemetryAttempts[pub6] ?? 0) >= maxAttempts) {
      return;
    }
    if (hex.length != kPubKeySize * 2) {
      // Only a prefix — can't address the peer.
      return;
    }
    final Uint8List pubKey = Uint8List(kPubKeySize);
    for (int i = 0; i < kPubKeySize; i++) {
      pubKey[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    _telemetryInflight.add(pub6);
    _telemetryAttempts[pub6] = (_telemetryAttempts[pub6] ?? 0) + 1;
    notifyListeners();
    // Auto-clear if the peer never answers (OTA loss, peer offline,
    // or peer's privacy policy denies the request).
    Timer(inflightTimeout, () {
      if (_telemetryInflight.remove(pub6)) notifyListeners();
    });
    try {
      await send(
          MeshcoreFrameCodec.sendTelemetryReq(peerPubKey: pubKey));
    } catch (_) {
      _telemetryInflight.remove(pub6);
      notifyListeners();
    }
  }

  /// True while a peer-telemetry query is awaiting response. Drives
  /// "querying…" spinners in the UI.
  bool isQueryingTelemetry(String pubKeyHex) {
    final String hex = pubKeyHex.toLowerCase();
    if (hex.length < kPubKeyPrefixSize * 2) return false;
    return _telemetryInflight
        .contains(hex.substring(0, kPubKeyPrefixSize * 2));
  }

  /// Number of telemetry-query attempts made for this peer this
  /// process session. Survives view re-mounts (state lives on the
  /// controller, not the view). Reset on a successful telemetry
  /// receipt — see [_trackTelemetry] — so a peer that finally
  /// answers becomes eligible for fresh polling again.
  int telemetryAttemptsFor(String pubKeyHex) {
    final String hex = pubKeyHex.toLowerCase();
    if (hex.length < kPubKeyPrefixSize * 2) return 0;
    return _telemetryAttempts[
            hex.substring(0, kPubKeyPrefixSize * 2)] ??
        0;
  }

  /// Total telemetry requests sent this session (incremented once
  /// per actual outbound frame, not per call). Useful for the
  /// observability chip in the elevation view.
  int get telemetrySendCount =>
      _telemetryAttempts.values.fold(0, (int a, int b) => a + b);

  /// Reset the per-peer attempt counters so the auto-query loop
  /// gives every peer a fresh set of attempts. Used by the
  /// "tap to restart" affordance on the Fujiさん view — handy after
  /// a peer flips its telemetry mode on, or just to retry.
  void resetTelemetryAttempts() {
    _telemetryAttempts.clear();
    notifyListeners();
  }

  final Set<String> _telemetryInflight = <String>{};
  final Map<String, int> _telemetryAttempts = <String, int>{};

  // --- Background peer-telemetry poller (opt-in, airtime-conscious) ---
  //
  // Politely cycles through synced *contacts*, requesting telemetry one
  // at a time so temperature / altitude populate across the fabric
  // without the user tapping each node. Rate-limited (one request per
  // interval), tiered by hop/distance, and attempt-capped — once every
  // eligible contact has answered or hit its cap, it goes quiet (and
  // re-polls only after the refresh window). Off → no OTA traffic.

  Timer? _telemPollTimer;
  bool _telemPollEnabled = true;
  final Duration? _telemPollIntervalOverride; // test seam
  static const Duration _telemPollInterval = Duration(seconds: 10);
  static const int _telemPollMaxAttempts = 3;
  static const Duration _telemPollRefreshAfter = Duration(minutes: 15);
  static const int _telemPollMaxHopsAlways = 1;
  static const int _telemPollMaxHopsWithDistance = 2;
  static const double _telemPollMaxDistanceMeters = 100000; // 100 km

  /// Whether background telemetry polling is enabled (App settings).
  bool get telemetryPollEnabled => _telemPollEnabled;

  Future<void> _loadTelemetryPollPref() async {
    _telemPollEnabled = await TelemetryPollPrefs.enabled();
    if (_telemPollEnabled) {
      if (isReady) _startTelemetryPolling();
    } else {
      _telemPollTimer?.cancel();
      _telemPollTimer = null;
    }
    notifyListeners();
  }

  Future<void> setTelemetryPollEnabled(bool v) async {
    if (v == _telemPollEnabled) return;
    _telemPollEnabled = v;
    notifyListeners();
    await TelemetryPollPrefs.setEnabled(v);
    if (v) {
      if (isReady) _startTelemetryPolling();
    } else {
      _telemPollTimer?.cancel();
      _telemPollTimer = null;
    }
  }

  void _startTelemetryPolling() {
    _telemPollTimer?.cancel();
    if (!_telemPollEnabled) return;
    _telemPollTimer = Timer.periodic(
        _telemPollIntervalOverride ?? _telemPollInterval,
        (_) => _stepTelemetryPoll());
  }

  /// Query tier for the poller (mirrors the elevation view's old loop):
  /// 0 = direct, 1 = 1-hop, 2 = 2-hop within 100 km, -1 = skip
  /// (advert-only / no path / too far / too many hops).
  int _telemPollTierFor(DiscoveredNode n) {
    final List<int>? hops = n.outPathHashes;
    if (hops == null) return -1;
    final int hopCount = hops.length;
    if (hopCount == 0) return 0;
    if (hopCount <= _telemPollMaxHopsAlways) return 1;
    if (hopCount <= _telemPollMaxHopsWithDistance && n.hasLocation) {
      final double? d = distanceMetersTo(n.latitude!, n.longitude!);
      if (d != null && d < _telemPollMaxDistanceMeters) return 2;
    }
    return -1;
  }

  void _stepTelemetryPoll() {
    if (!isReady || !_telemPollEnabled || !_visible) return;
    if (backgroundRequestsHeld) return;
    final String? own = ownPubKeyHex;
    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    DiscoveredNode? target;
    int bestTier = 99;
    for (final DiscoveredNode n in _nodes.values) {
      if (n.pubKeyHex == own) continue;
      if (isQueryingTelemetry(n.pubKeyHex)) continue;
      if (telemetryAttemptsFor(n.pubKeyHex) >= _telemPollMaxAttempts) {
        continue;
      }
      final int tier = _telemPollTierFor(n);
      if (tier < 0) continue;
      // Need telemetry if we have none, or it's older than the refresh
      // window. (A successful receipt clears the attempt cap, so a
      // refreshed peer becomes eligible again here.)
      final NodeTelemetry? t = telemetryFor(n.pubKeyHex);
      final bool needs = t == null ||
          (nowMs - t.receivedAt.millisecondsSinceEpoch) >
              _telemPollRefreshAfter.inMilliseconds;
      if (!needs) continue;
      // Prefer the cheapest tier; tie-break on most-recently-heard.
      if (tier < bestTier ||
          (tier == bestTier &&
              target != null &&
              n.lastHeardUnix > target.lastHeardUnix)) {
        bestTier = tier;
        target = n;
      }
    }
    if (target == null) return;
    unawaited(requestPeerTelemetry(target.pubKeyHex,
        maxAttempts: _telemPollMaxAttempts));
  }

  void _trackTelemetry(MeshcoreInbound f) {
    if (f is! TelemetryResponseFrame) return;
    final StringBuffer hex = StringBuffer();
    for (final int b in f.pubKeyPrefix) {
      hex.write(b.toRadixString(16).padLeft(2, '0'));
    }
    String pub6 = hex.toString();
    // A self-telemetry reply may echo the *request's* all-zero pubkey
    // instead of the device's own prefix, landing under a zero key
    // where selfTelemetry / telemetryFor(self) can't find it. Re-key
    // it to our own prefix so every consumer sees self telemetry.
    final String? ownHex = ownPubKeyHex;
    final String? ownPub6 =
        (ownHex != null && ownHex.length >= kPubKeyPrefixSize * 2)
            ? ownHex.substring(0, kPubKeyPrefixSize * 2)
            : null;
    if (pub6 == '0' * (kPubKeyPrefixSize * 2) && ownPub6 != null) {
      pub6 = ownPub6;
    }
    final List<LppEntry> entries = decodeCayenneLpp(f.lppPayload);
    final NodeTelemetry nt = NodeTelemetry.fromFrame(
      pubKeyPrefixHex: pub6,
      receivedAt: DateTime.now(),
      entries: entries,
    );
    // Diagnostic so we can see exactly what a node reports (run
    // `flutter logs`): which LPP types arrived + the decoded env/alt.
    meshLog('telem', 'key=$pub6 '
        'types=${entries.map((LppEntry e) => '0x${e.type.toRadixString(16)}').join(',')} '
        'temp=${nt.temperatureC} hum=${nt.humidityPct} '
        'press=${nt.pressureHpa} alt=${nt.altitudeMeters}');
    _telemetry[pub6] = nt;
    _telemetryInflight.remove(pub6);
    // Reset the per-peer attempt cap on a successful receipt — a
    // peer that just answered is fair game for periodic refresh
    // later, without inheriting the failed-attempts count from
    // before they flipped telemetry on.
    _telemetryAttempts.remove(pub6);
  }

  void _trackBattery(MeshcoreInbound f) {
    if (f is! BatteryStorageFrame) return;
    _battery = f.battery;
    final int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    _battSamples.add(<int>[f.battery.batteryMillivolts, now]);
    if (_battSamples.length > _battSampleCap) _battSamples.removeAt(0);
    if (_battSamples.length >= 2) {
      final int newest = _battSamples.last[0];
      final int oldest = _battSamples.first[0];
      const int margin = 40; // mV — above ADC / temperature noise
      _charging = (newest - oldest) >= margin
          ? true
          : (oldest - newest) >= margin
              ? false
              : null;
    }
    _recordBatterySample(f.battery.batteryMillivolts, now);
  }

  /// Read the radio's channel table, one slot at a time.
  ///
  /// The published rule is to fetch **every** slot, including past an empty
  /// one, because a radio with five configured channels and a gap at two still
  /// holds channels the user may need. This used to fire four blind requests
  /// and stop, so a table beyond slot three was invisible in the picker.
  ///
  /// One slot is asked for at a time and the next waits for its answer or for
  /// the idle window: the firmware serialises its replies, and a burst of forty
  /// requests would have them overtake one another. The count comes from
  /// `DEVICE_INFO`'s `max_group_channels` once known (8 on the small boards, 40
  /// on most), and [_channelProbeCount] is the pessimistic count for the window
  /// before that answer arrives.
  void _probeChannels() {
    _channelProbeIdleTimer?.cancel();
    _channelProbeIdleTimer = null;
    _channelsProbed.clear();
    _channelProbeCursor = 0;
    _channelProbeOutstanding = false;
    _probeNextChannel();
  }

  void _probeNextChannel() {
    // One slot in flight: the firmware keeps a single reply buffer, so a second
    // request would have its answer overtake the first.
    if (_channelProbeOutstanding) return;
    if (state != MeshcoreConnectionState.ready) return;
    final int limit = _channelProbeLimit;
    while (_channelProbeCursor < limit &&
        _channelsProbed.contains(_channelProbeCursor)) {
      _channelProbeCursor++;
    }
    if (_channelProbeCursor >= limit) return;
    final int idx = _channelProbeCursor;
    _channelProbeCursor++;
    _channelsProbed.add(idx);
    _channelProbeOutstanding = true;
    unawaited(send(MeshcoreFrameCodec.getChannel(idx)).catchError((_) {}));
    _channelProbeIdleTimer =
        Timer(_channelProbeIdleOverride ?? _channelProbeIdle, () {
      // A slot that never answers is either unconfigured or refused; either
      // way the table continues, so the walk does rather than stopping at the
      // first gap.
      _channelProbeOutstanding = false;
      _probeNextChannel();
    });
  }

  void _channelProbeAnswered() {
    _channelProbeOutstanding = false;
    _channelProbeIdleTimer?.cancel();
    _channelProbeIdleTimer = null;
    _probeNextChannel();
  }

  /// How many slots to ask about, once the radio has said how many it has.
  int get _channelProbeLimit {
    final int? reported = _deviceInfo?.maxGroupChannels;
    if (reported == null || reported <= 0) return _channelProbeCount;
    return reported;
  }

  /// Send a text message on the active channel (`SEND_CHANNEL_TXT_MSG`,
  /// 0x03). The radio does the OTA channel encryption; we append an
  /// optimistic outgoing line. No-op if not ready or text is blank.
  Future<void> sendChannelText(String text) =>
      sendChannelTextTo(_activeChannel, text);

  /// Send on a **specific** channel slot rather than the active one.
  ///
  /// The bot (R59) needs this: it may be bound to a private slot while
  /// the user is looking at another channel entirely, and routing its
  /// reply to whatever happens to be on screen would put private
  /// traffic somewhere it was never meant to go.
  /// Returns the outgoing row, or null when nothing was sent.
  /// See [sendDirectText] for [urgent]: an alarm is written even when the
  /// app's duty-cycle window is full, and is charged all the same.
  Future<ChatMessage?> sendChannelTextTo(int channelIdx, String text,
      {bool urgent = false}) async {
    final String t = text.trim();
    if (t.isEmpty || !isReady) return null;
    // A capability the radio has denied is a local refusal with its own
    // sentence, not an ERR that arrives after the row was written. Unknown is
    // not refused: the first send is how the state gets learned.
    if (_capabilities.stateOf(MeshcoreCommand.sendChannelMessage) ==
        CapabilityState.absent) {
      final ChatMessage refused = ChatMessage(
        channelIdx: channelIdx,
        text: t,
        outgoing: true,
        delivery: MessageDelivery.failed,
        failReason: 'this radio has no channel send',
        failCause: FailureCause.unsupportedCommand,
      );
      _addMessage(refused);
      notifyListeners();
      return refused;
    }
    final int ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final ChatMessage m = ChatMessage(
      channelIdx: channelIdx,
      text: t,
      outgoing: true,
      delivery: MessageDelivery.sending,
    );
    _addMessage(m);
    _registerOutgoing(m, CommandAnswer.ok);
    notifyListeners();
    try {
      await send(gated: !urgent, MeshcoreFrameCodec.sendChannelTextMessage(
        channelIdx: channelIdx,
        timestamp: ts,
        text: t,
      ));
    } on AirtimeRefused {
      // The radio never saw this frame, so it is not a link failure: the row
      // says why it did not go, and the copy names the budget.
      _failOutgoing(m.id, 'airtime budget',
          cause: FailureCause.airtimeBudget);
      notifyListeners();
    } catch (_) {
      // APP-C2 rule 2: a channel send never reads `failed`. A write that
      // threw may have reached the radio's buffer before the link went, so
      // the honest state is "cannot vouch for this one", not "did not send".
      _emitTaskError('sendChannel');
      _uncertainOutgoing(m.id, 'link dropped while sending');
      notifyListeners();
    }
    return m;
  }

  // --- Inbound queue drain (CMD_SYNC_NEXT_MESSAGE) ---
  //
  // The companion firmware does NOT push every received item in real
  // time. When it has queued inbound items (newly heard contacts /
  // adverts AND received text messages) it sends
  // `PUSH_CODE_MSGS_WAITING` (0x83); the app must then pull them one
  // at a time with `CMD_SYNC_NEXT_MESSAGE` until the device replies
  // `RESP_CODE_NO_MORE_MESSAGES`. Without this loop, discovered nodes
  // and incoming messages never reach the app.

  bool _draining = false;
  int _drainSteps = 0;
  static const int _drainStepCap = 512; // runaway guard

  /// Watchdog for a drain that never finishes.
  ///
  /// The step cap only advances when frames *arrive*. If the radio goes
  /// quiet after we send a SYNC — link wedged, firmware busy, unit out
  /// of range mid-drain — nothing ever calls `_maybeDrain` again and
  /// `_draining` stays true forever. That is worse than it sounds:
  /// `CueBridge` mutes advert cues while draining and R59's bot
  /// declines to answer, so a stuck drain silently disables both with
  /// no visible symptom. Time-box it instead.
  Timer? _drainWatchdog;
  static const Duration _drainStall = Duration(seconds: 20);

  /// True while the controller is in the middle of a SYNC drain
  /// (post-handshake: pulling queued contacts/adverts/messages off the
  /// radio). Exposed so the Dashboard can flag the initial 1–3 s
  /// post-connect lag as "syncing…" rather than letting it feel like
  /// a freeze.
  bool get isDraining => _draining;

  void _setDraining(bool v) {
    if (_draining == v) return;
    _draining = v;
    notifyListeners();
  }

  /// True while the current drain is replaying a **backlog** — traffic
  /// the device queued before we were listening (link-up, resume,
  /// reconnect) rather than a message that just arrived.
  ///
  /// The distinction matters because the firmware does **not** push
  /// text messages in real time: every inbound message reaches us
  /// through a drain, so "skip everything drained" would skip
  /// everything, full stop. A drain kicked off by a live
  /// `MSGS_WAITING` push while we were already connected is delivering
  /// fresh traffic and must be treated as such.
  bool get isBacklogDrain => _draining && _drainIsBacklog;
  bool _drainIsBacklog = false;

  void _drainStart({bool backlog = false}) {
    if (_draining) return;
    _drainIsBacklog = backlog;
    _drainRetried = false;
    _setDraining(true);
    _drainSteps = 0;
    _drainStep();
  }

  /// Whether the current drain has already been restarted once after a stall.
  ///
  /// The MSGS_WAITING push is what starts a drain, and a push lost on the link
  /// left the queued messages sitting until the next push or reconnect. One
  /// restart is enough to cover a dropped push; a second would loop forever on
  /// a radio that cannot answer.
  bool _drainRetried = false;

  void _drainStep() {
    if (++_drainSteps > _drainStepCap) {
      _endDrain();
      return;
    }
    _armDrainWatchdog();
    unawaited(send(MeshcoreFrameCodec.syncNextMessage()).catchError((_) {
      _endDrain();
    }));
  }

  /// Restart the stall timer — called on every SYNC we send, so the
  /// window is "silence since the last request", not total drain time.
  /// A long but healthy drain must not be cut short.
  void _armDrainWatchdog() {
    _drainWatchdog?.cancel();
    _drainWatchdog = Timer(_drainStall, () {
      if (!_draining) return;
      _emitTaskError('drainStalled');
      if (!_drainRetried) {
        // One restart: the push that started this drain may simply have been
        // lost, and the queued messages would otherwise wait for the next one.
        _drainRetried = true;
        _drainSteps = 0;
        _drainStep();
        return;
      }
      _endDrain();
    });
  }

  void _endDrain() {
    _drainWatchdog?.cancel();
    _drainWatchdog = null;
    _setDraining(false);
  }

  void _maybeDrain(MeshcoreInbound f) {
    if (f is MessagesWaitingFrame) {
      _pushEvent(MeshEvent(
        kind: MeshEventKind.queuedWaiting,
        args: f.count == null
            ? const <String, String>{}
            : <String, String>{'count': '${f.count}'},
      ));
      _drainStart();
      return;
    }
    if (!_draining) return;
    if (f is NoMoreMessagesFrame) {
      _endDrain(); // queue emptied
    } else {
      // The frame we just received was the reply to our SYNC (a
      // queued contact/advert/message); pull the next one.
      _drainStep();
    }
  }

  // --- The radio's own add policy (`CMD_GET/SET_AUTOADD_CONFIG`) --------
  //
  // Whether a newly heard node becomes a contact is the radio's decision, not
  // the app's: the firmware adds by node type, may overwrite the oldest
  // non-favourite when the 350-row table is full, and can limit how far away a
  // node may be. Left unread, the table fills under a policy the user cannot
  // see, and the first symptom is that a contact the app offered to add is
  // refused. The reply is `RESP_CODE_AUTOADD_CONFIG` (0x19).

  AutoAddConfig? _autoAddConfig;

  /// The radio's add policy, or null while it has not answered.
  AutoAddConfig? get autoAddConfig => _autoAddConfig;

  void _trackAutoAddConfig(MeshcoreInbound f) {
    if (f is! AutoAddConfigFrame) return;
    _autoAddConfig = f.config;
  }

  /// Ask the radio what its add policy is. Cheap, and the reply is the only
  /// way to know: the app cannot infer it from a table that may already be
  /// full.
  Future<void> requestAutoAddConfig() async {
    if (!isReady) return;
    try {
      await send(MeshcoreFrameCodec.getAutoAddConfig());
    } catch (_) {
      _emitTaskError('getAutoAddConfig');
    }
  }

  /// Change part of the radio's add policy. Every field is optional and the
  /// rest is carried through, because the command replaces the whole byte.
  ///
  /// Refused when the current policy is unknown: writing from zero would
  /// silently switch auto-add off for every node type, which is a setting the
  /// user did not choose. [requestAutoAddConfig] has to land first.
  Future<bool> setAutoAddConfig({
    bool? overwriteOldest,
    bool? chat,
    bool? repeater,
    bool? roomServer,
    bool? sensor,
    int? maxHops,
  }) async {
    final AutoAddConfig? cur = _autoAddConfig;
    if (!isReady || cur == null) return false;
    int flags = cur.flags;
    void bit(int mask, bool? value) {
      if (value == null) return;
      flags = value ? (flags | mask) : (flags & ~mask);
    }

    bit(kAutoAddOverwriteOldest, overwriteOldest);
    bit(kAutoAddChat, chat);
    bit(kAutoAddRepeater, repeater);
    bit(kAutoAddRoomServer, roomServer);
    bit(kAutoAddSensor, sensor);
    final int hops = maxHops ?? cur.maxHops;
    try {
      await send(MeshcoreFrameCodec.setAutoAddConfig(flags, maxHops: hops));
      // The radio is the source of truth; read it back rather than assuming
      // the write was taken as sent (it clamps and may refuse).
      await requestAutoAddConfig();
      return true;
    } catch (_) {
      _emitTaskError('setAutoAddConfig');
      return false;
    }
  }

  // --- The route the last advert took (`CMD_GET_ADVERT_PATH`) -----------
  //
  // A trace reports the route a packet took *now*; this answers the route the
  // contact's last advertisement arrived by, from the radio's own record. It
  // sends no mesh traffic, so it is the cheap way to answer "which repeaters
  // hear this node at all".
  //
  // The reply carries no key, so only one request can be outstanding: a second
  // answer could not be told apart from the first.

  bool _pathDiscoveryInFlight = false;

  /// Ask the mesh for the route to a node (`CMD_SEND_PATH_DISCOVERY_REQ` 0x34).
  ///
  /// This is the active counterpart to [advertPathFor]: the radio floods a
  /// request, and whichever repeaters hear it answer with the outbound and
  /// inbound paths they found, so it can return a route that did not exist a
  /// minute ago. It costs airtime, so it is a deliberate action rather than
  /// something a screen does on open. The reply carries the node's prefix, so
  /// only one request is in flight and a stale answer cannot be mis-attributed.
  Future<PathDiscoveryResult?> discoverPathFor(String pubKeyHex,
      {Duration timeout = const Duration(seconds: 8)}) async {
    if (!isReady || _pathDiscoveryInFlight) return null;
    final String hex = pubKeyHex.toLowerCase();
    if (hex.length < kPubKeyPrefixSize * 2) return null;
    final String prefix = hex.substring(0, kPubKeyPrefixSize * 2);
    final Uint8List key = Uint8List.fromList(<int>[
      for (int i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]);
    _pathDiscoveryInFlight = true;
    try {
      final Future<MeshcoreInbound> reply = inboundFrames
          .firstWhere((MeshcoreInbound f) =>
              f is PathDiscoveryFrame &&
              _hex(f.result.pubKeyPrefix) == prefix)
          .timeout(timeout);
      await send(MeshcoreFrameCodec.sendPathDiscoveryReq(key));
      final MeshcoreInbound f = await reply;
      return f is PathDiscoveryFrame ? f.result : null;
    } catch (_) {
      return null;
    } finally {
      _pathDiscoveryInFlight = false;
    }
  }

  bool _advertPathInFlight = false;

  /// The route the contact's last advert took, or null when the radio could
  /// not answer inside [timeout] or another request is already waiting.
  Future<AdvertPath?> advertPathFor(String pubKeyHex,
      {Duration timeout = const Duration(seconds: 4)}) async {
    if (!isReady || _advertPathInFlight) return null;
    final String hex = pubKeyHex.toLowerCase();
    if (hex.length != kPubKeySize * 2) return null;
    final Uint8List key = Uint8List.fromList(<int>[
      for (int i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]);
    _advertPathInFlight = true;
    try {
      final Future<MeshcoreInbound> reply = inboundFrames
          .firstWhere((MeshcoreInbound f) => f is AdvertPathFrame)
          .timeout(timeout);
      await send(MeshcoreFrameCodec.getAdvertPath(key));
      final MeshcoreInbound f = await reply;
      return f is AdvertPathFrame ? f.advertPath : null;
    } catch (_) {
      return null;
    } finally {
      _advertPathInFlight = false;
    }
  }

  /// The radio's own changes to its contact table.
  ///
  /// The table is the radio's, and the app's mirror is a cache of it. The
  /// firmware pushes four events that change the table without the app asking:
  /// it evicted a contact (0x8F, `PUSH_CODE_CONTACT_DELETED` — either the user
  /// removed it or auto-add overwrote the oldest non-favourite), it stored a
  /// newly advertised contact automatically (0x8A), it learned a new route
  /// (0x81), or it could not store a new contact at all (0x90,
  /// `PUSH_CODE_CONTACTS_FULL`). Ignoring them leaves the app showing contacts
  /// the radio no longer has, missing ones it does, sending down routes the
  /// radio replaced, and quietly failing to add anything because the table is
  /// full.
  void _trackContactLifecycle(MeshcoreInbound f) {
    if (f is ContactDeletedFrame) {
      final String hex = _hex(f.publicKey);
      final Contact? gone = _contacts.remove(hex);
      _saveContactsSoon();
      if (_deviceContactCount != null && _deviceContactCount! > 0) {
        _deviceContactCount = _deviceContactCount! - 1;
      }
      // A deleted contact may still be heard on air, so the node entry stays;
      // it simply stopped being a synced contact, which is what makes it
      // unaddressable for a DM or a telemetry request.
      _pushEvent(MeshEvent(
        kind: MeshEventKind.contact,
        args: <String, String>{
          'name': gone?.name.isNotEmpty == true
              ? gone!.name
              : hex.substring(0, 8),
        },
      ));
    } else if (f is NewAdvertFrame) {
      // Auto-add stored this node on the radio. Mirror it exactly as a
      // streamed contact, or the app holds a contact the radio has and cannot
      // offer it anywhere.
      _ingestNode(ContactFrame(f.contact));
    } else if (f is PathUpdatedFrame) {
      // The radio replaced this contact's out_path. Re-read the record rather
      // than guessing: the app draws routes and addresses sends by it.
      final String hex = _hex(f.publicKey);
      for (final Contact c in _contacts.values) {
        if (_hex(c.publicKey) == hex) {
          unawaited(send(MeshcoreFrameCodec.getContactByKey(c.publicKey))
              .catchError((Object _) => Uint8List(0)));
          break;
        }
      }
    } else if (f is ContactsFullFrame) {
      _contactsFull = true;
    }
  }

  /// True while the radio has told us its contact table is full and it is not
  /// overwriting the oldest entry, so every new advert is being dropped.
  bool _contactsFull = false;
  bool get contactsFull => _contactsFull;

  void _clearContactsFull() {
    if (!_contactsFull) return;
    _contactsFull = false;
  }

  void _ingestNode(MeshcoreInbound f) {
    final int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (f is ContactFrame) {
      final Contact c = f.contact;
      // R56 — a key the user reconciled away. The radio is asked to remove
      // it (`CMD_REMOVE_CONTACT` 0x0F), but a sync can still deliver it before
      // that lands, so it is dropped on arrival rather than reappearing as a
      // duplicate of the live key.
      if (_superseded.contains(_hex(c.publicKey))) return;
      // Retain the raw contact record (path, flags, lastMod) so we can
      // re-send it byte-exactly via ADD_UPDATE_CONTACT when changing
      // per-contact telemetry permissions (R54 follow-on).
      _contacts[_hex(c.publicKey)] = c;
      _saveContactsSoon();
      _nodes[_hex(c.publicKey)] = _nodeFromContact(c, now: now);
    } else if (f is AdvertFrame) {
      _upsertAdvert(f.advert);
    } else if (f is RfLogFrame) {
      // RF-log captures carry the raw OTA packet *with* SNR/RSSI —
      // the signal needed to judge "what's in my area".
      final Advert? a = f.log.packet?.advert;
      if (a != null) {
        _upsertAdvert(a, snr: f.log.snrDb, rssi: f.log.rssi);
      }
    }
  }

  /// The node entry a synced contact describes.
  ///
  /// One mapping, used when the radio streams a contact and when the persisted
  /// table is read back at startup: a restart has to land on the same fabric the
  /// previous session ended with, or the tools offer only the nodes that
  /// happened to advertise since the app started, and a contact the radio can
  /// still reach from its stored path becomes unpingable.
  ///
  /// A contact sync REBUILDS the node entry, so anything the contact record
  /// does not carry is preserved from the previous entry: the record has no
  /// RSSI/SNR/altitude, and it reports (0,0) for a node that hides its position.
  /// `lastAdvertTimestamp` is in the device clock, so it is translated through
  /// the learned offset (0 until `CURR_TIME`).
  DiscoveredNode _nodeFromContact(Contact c, {int? now}) {
    final String hex = _hex(c.publicKey);
    final DiscoveredNode? prev = _nodes[hex];
    final int stamp =
        now ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final int adv = c.lastAdvertTimestamp;
    return DiscoveredNode(
      pubKeyHex: hex,
      name: c.name,
      type: c.type,
      lastHeardUnix: adv == 0 ? stamp : adv + _deviceClockOffsetSec,
      deviceAdvertUnix: adv == 0 ? null : adv,
      latitude:
          c.latitudeMicros == 0 ? prev?.latitude : c.latitudeMicros / 1e6,
      longitude:
          c.longitudeMicros == 0 ? prev?.longitude : c.longitudeMicros / 1e6,
      snrDb: prev?.snrDb,
      rssi: prev?.rssi,
      altitudeMeters: prev?.altitudeMeters,
      viaAdvert: false,
      // R49 — preserve the outbound repeater chain for topology drawing.
      // A flood-routed contact reports the flood sentinel, which `activePath`
      // would clamp to a bogus 64-byte chain reading as a 64-hop peer, so it
      // is an UNKNOWN route (null) rather than a path.
      outPathHashes: c.outPathLen == kPathLenFlood
          ? null
          : List<int>.unmodifiable(c.activePath),
      viaFlood: c.outPathLen == kPathLenFlood,
    );
  }

  void _upsertAdvert(Advert a, {double? snr, int? rssi}) {
    final int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final String k = _hex(a.publicKey);
    if (_superseded.contains(k)) return; // R56 — reconciled-away key
    final DiscoveredNode? prev = _nodes[k];
    _nodes[k] = DiscoveredNode(
      pubKeyHex: k,
      name: a.name ?? prev?.name ?? k.substring(0, 8),
      type: a.type,
      // Receiving an advert push (0x80) or RF-log (0x88) means we
      // heard this node *now*. `a.timestamp` is the sender's clock at
      // advert creation — often unset/stale/skewed vs. the phone — so
      // it must NOT drive the "in range" freshness check.
      lastHeardUnix: now,
      latitude: a.latitude ?? prev?.latitude,
      longitude: a.longitude ?? prev?.longitude,
      // R44 — forward-compat: today a.altitudeMeters is always null
      // because the advert payload doesn't carry altitude over the
      // wire. Kept in the propagation path so UIs depending on
      // DiscoveredNode.altitudeMeters Just Work once firmware adds
      // an alt slot.
      altitudeMeters: a.altitudeMeters ?? prev?.altitudeMeters,
      snrDb: snr ?? prev?.snrDb,
      rssi: rssi ?? prev?.rssi,
      viaAdvert: true,
      // Advert pushes don't carry the outbound repeater path; only
      // ContactFrame does. Preserve whatever the contact sync gave
      // us (may be null for advert-only-heard peers, which is the
      // signal the topology resolver uses to draw dashed).
      outPathHashes: prev?.outPathHashes,
      viaFlood: prev?.viaFlood ?? false,
    );
    // F8 — peer's advertised position is a "the mesh extends to
    // here" observation. Same coverage bucket as own-location
    // samples; the FabricSurveyView shades both.
    if (a.latitude != null && a.longitude != null) {
      _recordCoverage(a.latitude!, a.longitude!);
    }
    // Cue signal — new node (Geiger) vs re-advert (ambient ping). Read
    // `prev` (captured before the upsert above) for the new/known split.
    if (!_adverts.isClosed) _adverts.add(prev == null);
  }

  /// Ask the radio for its synced contact list (`CMD_GET_CONTACTS`).
  Future<void> requestContacts({int? since}) =>
      send(MeshcoreFrameCodec.getContacts(since: since));

  // --- Device-contacts probe (diagnostic) ---------------------------
  // The app's `_contacts` hides keys the user superseded, and the
  // "contacts" UI surfaces only favourites — so neither reflects what the
  // radio actually stores. This captures the RAW device contact list so
  // the user can SEE every entry (and free a full table). Populated by
  // every CMD_GET_CONTACTS sync.

  final List<Contact> _probedContacts = <Contact>[];
  bool _probing = false;
  int? _deviceContactCount;
  Completer<void>? _contactSyncDone;

  /// The radio's reported total contact count (from `CONTACTS_START`).
  int? get deviceContactCount => _deviceContactCount;

  /// The device's max contact capacity, when known (`DeviceInfo`).
  int? get maxContacts => _deviceInfo?.maxContacts;

  /// Every contact the radio returned on the last full sync — raw, incl.
  /// superseded keys the rest of the app hides.
  List<Contact> get probedContacts => List<Contact>.unmodifiable(_probedContacts);

  /// Trigger a fresh full contact sync (fills [probedContacts] +
  /// [deviceContactCount]); also refresh device info for [maxContacts].
  /// How long the radio may go quiet mid-stream before the app asks again.
  /// The radio streams one frame per contact, so the wait is for the next
  /// frame, not for the whole table.
  static const Duration contactIdleTimeout = Duration(seconds: 3);

  /// How many times a stalled stream is re-requested before the app keeps what
  /// arrived and says the table may be short.
  static const int contactSyncAttempts = 3;

  /// Overall ceiling for a caller waiting on a sync, derived from the watchdog
  /// rather than guessed: every attempt costs at most one idle window, and the
  /// caller gets a little slack on top.
  static const Duration contactSyncTimeout = Duration(seconds: 8);

  Timer? _contactIdleTimer;
  final Duration? _contactIdleOverride;
  int _contactSyncAttempt = 0;
  bool _contactsIncomplete = false;

  /// True when the last sync stopped before the radio's end-of-contacts frame:
  /// the app kept what arrived, and the table it holds may be missing entries.
  /// Cleared by the next end-of-contacts.
  bool get contactsIncomplete => _contactsIncomplete;

  void _armContactIdle() {
    _contactIdleTimer?.cancel();
    _contactIdleTimer =
        Timer(_contactIdleOverride ?? contactIdleTimeout, _onContactIdle);
  }

  void _onContactIdle() {
    if (!_probing) {
      _completeContactSync();
      return;
    }
    if (_contactSyncAttempt >= contactSyncAttempts) {
      // Give up rather than wait forever, and keep the entries that did arrive:
      // a partial table is more useful than none, and the flag says so instead
      // of presenting it as complete.
      _contactsIncomplete = true;
      _completeContactSync();
      return;
    }
    _contactSyncAttempt++;
    unawaited(requestContacts(since: _contactsSince).catchError((_) {}));
    _armContactIdle();
  }

  void _completeContactSync() {
    _contactIdleTimer?.cancel();
    _contactIdleTimer = null;
    _probing = false;
    final Completer<void>? done = _contactSyncDone;
    if (done != null && !done.isCompleted) done.complete();
  }

  /// Full contact sync, returning once the radio says the list ended.
  ///
  /// Callers that need a fresh table (BIND does) must not poll a fixed delay and
  /// hope: the count is in `CONTACTS_START` and the end is in
  /// `END_OF_CONTACTS`, so wait for that. A radio that never answers costs
  /// [contactSyncTimeout] rather than hanging.
  Future<void> refreshDeviceContacts() async {
    if (!isReady) return;
    if (_contactSyncDone != null) return _contactSyncDone!.future;
    final Completer<void> done = Completer<void>();
    _contactSyncDone = done;
    try {
      await send(MeshcoreFrameCodec.deviceQuery());
      await requestContacts();
      // A radio that honours the request answers CONTACTS_START at once. If it
      // never starts, waiting the whole timeout only delays the caller's
      // refusal, so give it a short window to begin and then wait for the end.
      for (int i = 0; i < 30 && _probing == false && !done.isCompleted; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      if (!_probing) return;
      // The watchdog owns the retries and completes `done` when it stops; the
      // outer ceiling is only a guard against a bug in it.
      await done.future.timeout(
          (_contactIdleOverride ?? contactIdleTimeout) *
              (contactSyncAttempts + 2),
          onTimeout: () {});
    } finally {
      if (identical(_contactSyncDone, done)) _contactSyncDone = null;
    }
  }

  /// The `lastmod` the radio reported when it last finished streaming its
  /// contact table. Sent back as `since` so a reconnect asks for changes
  /// rather than the whole table.
  int _contactsSince = 0;
  bool _contactsSyncRequested = false;

  /// The incremental-sync token, for the test that proves a reconnect asks for
  /// changes rather than the whole table.
  @visibleForTesting
  int get contactsSinceForTest => _contactsSince;
  static const String _kContactsSince = 'mm.contacts.since';

  Future<void> _persistContactsSince(int lastmod) async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    await Prefs.setInt(p, _kContactsSince, lastmod);
  }

  Future<void> _loadContactsSince() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    _contactsSince = p.getInt(_kContactsSince) ?? 0;
  }

  /// The in-flight load of the persisted table, so the first connect waits for
  /// it instead of reading an empty table as "we hold nothing".
  Future<void>? _contactsLoad;

  void _loadSyncedContacts() {
    _contactsLoad = () async {
      final List<Contact> rows = await ContactStore.load();
      if (rows.isEmpty) return;
      // The user's reconciled-away keys are stale rows on the radio too, so
      // they are dropped on the way in for the same reason `_ingestNode` drops
      // them: a persisted table can still carry a key the radio has since
      // removed.
      final Set<String> gone = await SupersededStore.load();
      bool added = false;
      for (final Contact c in rows) {
        final String hex = _hex(c.publicKey);
        if (gone.contains(hex) || _superseded.contains(hex)) continue;
        if (_contacts.containsKey(hex)) continue;
        _contacts[hex] = c;
        // The node entry too, through the same mapping a streamed contact uses:
        // otherwise the fabric starts empty on every launch and the pickers
        // offer only what has advertised since.
        _nodes.putIfAbsent(hex, () => _nodeFromContact(c));
        added = true;
      }
      if (added) notifyListeners();
    }();
  }

  Timer? _contactsSaveTimer;

  /// Persist the table once the burst settles: a sync streams one frame per
  /// contact, and sealing a 200-row document on every frame would cost more
  /// than the sync.
  void _saveContactsSoon() {
    _contactsSaveTimer?.cancel();
    _contactsSaveTimer = Timer(const Duration(seconds: 3), () {
      unawaited(ContactStore.save(_contacts.values));
    });
  }

  /// The radio's default flood scope name, or null while it is unknown and ''
  /// when the radio answered that none is set. A channel send inherits it, so
  /// "who receives this" cannot be answered without it.
  String? _floodScopeName;
  String? get floodScopeName => _floodScopeName;
  bool _floodScopeAsked = false;

  void _requestFloodScope() {
    if (_floodScopeAsked) return;
    _floodScopeAsked = true;
    unawaited(send(MeshcoreFrameCodec.getDefaultFloodScope())
        .catchError((Object _) => _floodScopeAsked = false));
  }

  // --- Sharing a contact as text ----------------------------------------
  //
  // `CMD_EXPORT_CONTACT` (0x11) answers with the contact's advert packet, which
  // is the same bytes the radio puts on air, so the link that carries it is
  // `meshcore://<hex>` and the receiving radio imports it as if it had heard the
  // advert. That is the whole point of the format: it is the radio's own packet,
  // not an app-specific record, so a contact shared from here can be imported by
  // any MeshCore client. The reply carries no key, so one export is in flight at
  // a time.

  static const String contactLinkPrefix = 'meshcore://';

  bool _exportContactInFlight = false;

  /// The contact as a shareable link, or null when the radio did not answer.
  Future<String?> exportContactLink(String pubKeyHex) async {
    if (!isReady || _exportContactInFlight) return null;
    final String hex = pubKeyHex.toLowerCase();
    if (hex.length != kPubKeySize * 2) return null;
    final Uint8List key = Uint8List.fromList(<int>[
      for (int i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]);
    _exportContactInFlight = true;
    try {
      final Future<MeshcoreInbound> reply = inboundFrames
          .firstWhere((MeshcoreInbound f) => f is ExportedContactFrame)
          .timeout(const Duration(seconds: 4));
      await send(MeshcoreFrameCodec.exportContact(pubKey: key));
      final MeshcoreInbound f = await reply;
      if (f is! ExportedContactFrame || f.advertPacket.isEmpty) return null;
      return '$contactLinkPrefix${_hex(f.advertPacket)}';
    } catch (_) {
      return null;
    } finally {
      _exportContactInFlight = false;
    }
  }

  /// Import a contact from a `meshcore://` link (or the bare hex of an advert
  /// packet). Returns false when the text is not a link, the packet is outside
  /// the size the firmware accepts, or the radio refuses it.
  ///
  /// The radio validates the packet itself and answers `ERR_CODE_ILLEGAL_ARG`
  /// for a bad advert, so a well-formed but wrong packet is its refusal to give.
  Future<bool> importContactLink(String text) async {
    if (!isReady) return false;
    final Uint8List? packet = parseContactLink(text);
    if (packet == null) return false;
    try {
      await send(MeshcoreFrameCodec.importContact(packet));
      // The radio stores it; read the table back so the app can offer it.
      await requestContacts();
      return true;
    } catch (_) {
      _emitTaskError('importContact');
      return false;
    }
  }

  /// The advert packet inside a contact link, or null. Accepts the `meshcore://`
  /// form and a bare even-length hex string, because a person may paste either.
  static Uint8List? parseContactLink(String text) {
    String t = text.trim();
    if (t.toLowerCase().startsWith(contactLinkPrefix)) {
      t = t.substring(contactLinkPrefix.length);
    }
    t = t.replaceAll(RegExp(r'[\s:,-]'), '');
    if (t.length.isOdd || t.length < kImportContactMin * 2) return null;
    if (t.length > kImportContactMax * 2) return null;
    if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(t)) return null;
    final Uint8List out = Uint8List(t.length ~/ 2);
    for (int i = 0; i < out.length; i++) {
      out[i] = int.parse(t.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  // --- A repeater session --------------------------------------------------
  //
  // `CMD_SEND_LOGIN` (0x1A) opens a session on a repeater or room server with a
  // shared secret, and the verdict arrives as `PUSH_CODE_LOGIN_SUCCESS` (0x85,
  // carrying the permission byte) or `_FAIL` (0x86). `CMD_LOGOUT` (0x1D) closes
  // it. Both replies name the node's prefix, so a session cannot be
  // mis-attributed to another repeater.
  //
  // What a session *permits* is the radio's business: this only reports what it
  // said. It is also the prerequisite for a command console, which is not built:
  // there is no `CMD_RUN_CLI_COMMAND` builder in the codec yet, so this is the
  // whole of the session and not a half-built console.

  /// Signs in to a repeater. Null when the radio never answered; a
  /// [LoginResult] with `success == false` is the repeater refusing.
  Future<LoginResult?> loginRepeater(String pubKeyHex, String password,
      {Duration timeout = const Duration(seconds: 10)}) async {
    if (!isReady) return null;
    final String hex = pubKeyHex.toLowerCase();
    if (hex.length != kPubKeySize * 2) return null;
    final String prefix = hex.substring(0, kPubKeyPrefixSize * 2);
    final Uint8List key = Uint8List.fromList(<int>[
      for (int i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]);
    try {
      final Uint8List frame =
          MeshcoreFrameCodec.sendLogin(key, password); // refuses a bad password
      final Future<MeshcoreInbound> reply = inboundFrames
          .firstWhere((MeshcoreInbound f) =>
              f is LoginResultFrame &&
              _hex(f.result.pubKeyPrefix) == prefix)
          .timeout(timeout);
      await send(frame);
      final MeshcoreInbound f = await reply;
      return f is LoginResultFrame ? f.result : null;
    } catch (_) {
      return null;
    }
  }

  /// Ends a repeater session. The radio answers OK even for an unknown key, so
  /// there is nothing to wait for.
  Future<void> logoutRepeater(String pubKeyHex) async {
    if (!isReady) return;
    final String hex = pubKeyHex.toLowerCase();
    if (hex.length != kPubKeySize * 2) return;
    try {
      await send(MeshcoreFrameCodec.logout(<int>[
        for (int i = 0; i < hex.length; i += 2)
          int.parse(hex.substring(i, i + 2), radix: 16),
      ]));
    } catch (_) {
      _emitTaskError('logout');
    }
  }

  // --- The radio's own alert outputs ------------------------------------
  //
  // `CMD_RUN_CLI_COMMAND` (0x42) is the radio's whole shell, which is why the
  // app never sends text through it. `packages/meshcore` already models a
  // closed whitelist of commands (`RadioCliCommand`, D8.24) and refuses
  // everything else, including `remote`; this is the half that reaches the
  // radio, and the only way to build a frame is one of those typed objects.
  //
  // Two things make the answer awkward. The reply is zero or more
  // `RESP_CODE_CLI_REPLY` (0x1D) frames and then a bare OK or ERR, so the text
  // and the verdict arrive separately. And the OK/ERR carries no tag, so it is
  // claimed through the ledger like every other command — the two-character
  // correlation prefix only tags the text lines.

  /// Marker id in [_ledger] for a CLI command waiting for its OK/ERR.
  static const String _cliMarker = '\u0000cli';

  bool _cliInFlight = false;
  Completer<MeshcoreInbound>? _cliAnswer;

  /// True while a CLI command is waiting for its answers.
  bool get cliBusy => _cliInFlight;

  /// Run one whitelisted CLI command and collect what the radio says.
  ///
  /// One command at a time: the reply text is matched only by the two-character
  /// prefix this call chose, and two overlapping calls would interleave their
  /// lines with no way to tell them apart. A second call while one is waiting is
  /// refused rather than queued, because the caller is a tap.
  Future<RadioCliResult> runRadioCli(
    RadioCliCommand command, {
    Duration timeout = const Duration(seconds: 6),
    String correlation = 'a1',
  }) async {
    if (!isReady) return const RadioCliUnavailable();
    if (_cliInFlight) return const RadioCliBusy();
    if (!RadioCliCommand.isCorrelationTag(correlation)) {
      throw ArgumentError.value(
          correlation, 'correlation', 'not a two-character tag');
    }
    _cliInFlight = true;
    final Completer<MeshcoreInbound> answer = Completer<MeshcoreInbound>();
    _cliAnswer = answer;
    final List<String> lines = <String>[];
    StreamSubscription<MeshcoreInbound>? watch;
    _registerMarker(_cliMarker, CommandAnswer.ok);
    try {
      watch = inboundFrames.listen((MeshcoreInbound f) {
        if (f is! CliReplyFrame) return;
        final String text = f.text;
        if (!text.startsWith(correlation)) return;
        final String line = text.substring(correlation.length).trim();
        if (line.isNotEmpty) lines.add(line);
      });
      await send(command.bytes(correlation: correlation), gated: true);
      final MeshcoreInbound verdict = await answer.future.timeout(timeout);
      final String said = lines.join('\n');
      if (verdict is ErrorFrame) {
        return RadioCliRejected(code: verdict.code, text: said);
      }
      return RadioCliAnswered(text: said);
    } on TimeoutException {
      // The text that did arrive is still worth showing: a radio that streams
      // half an answer and then goes quiet has told the reader something.
      return RadioCliSilent(partial: lines.join('\n'));
    } catch (e) {
      return RadioCliUnavailable(detail: '$e');
    } finally {
      // Not awaited: a broadcast subscription stops delivering the moment
      // `cancel` is called, and the returned future is a formality. Awaiting it
      // held the caller's continuation open in a widget test's zone until the
      // test ended, which made the screen look as if it never answered.
      unawaited(watch?.cancel());
      _cliAnswer = null;
      _dropPending(_cliMarker);
      _cliInFlight = false;
    }
  }

  void _completeCli(MeshcoreInbound f) {
    final Completer<MeshcoreInbound>? c = _cliAnswer;
    _cliAnswer = null;
    if (c != null && !c.isCompleted) c.complete(f);
  }

  // --- The radio's pairing PIN ------------------------------------------
  //
  // `CMD_SET_DEVICE_PIN` (0x25): 0 clears the PIN, otherwise exactly six digits.
  // It is the radio's own gate on a *new* Bluetooth pairing, separate from its
  // list of bonded devices; the app already shows the current value out of
  // `DEVICE_INFO`, so a setter is the missing half.

  Future<bool> setDevicePin(int pin) async {
    if (!isReady) return false;
    if (pin != 0 && (pin < 100000 || pin > 999999)) return false;
    try {
      await send(MeshcoreFrameCodec.setDevicePin(pin));
      // The answer is a bare OK; re-query device info so the readout is the
      // radio's value rather than the one just typed.
      await send(MeshcoreFrameCodec.deviceQuery());
      notifyListeners();
      return true;
    } catch (_) {
      _emitTaskError('setDevicePin');
      return false;
    }
  }

  // --- Which radio profile a frame arrived on ---------------------------
  //
  // A two-profile radio splits one antenna's transmit time between two channel
  // configurations, and tags each received frame with the profile that heard it
  // (`RxVia`). The app decodes that tag and, until this, only used it to label
  // one diagnostic line. It is the one honest thing the app can say about a
  // second profile: it cannot read that profile's parameters and will not write
  // them, because the second profile takes 96-99 % of the primary's airtime and
  // that is a decision for the radio's own configuration, not for a phone
  // gesture.

  DateTime? _radio2LastSeen;

  /// When a frame was last heard on the **second** radio profile, or null when
  /// none has been since this session started.
  DateTime? get radio2LastSeen => _radio2LastSeen;

  /// True when this radio is running a second profile, evidenced by a frame it
  /// carried. Absence is not evidence of a single profile: a quiet second
  /// profile looks the same as none.
  bool get radio2Seen => _radio2LastSeen != null;

  void _trackRadioProfiles(MeshcoreInbound f) {
    final RxVia via = switch (f) {
      RawDataFrame(:final RxVia via) => via,
      ChannelDataFrame(:final RxVia via) => via,
      _ => RxVia.unknown,
    };
    if (via != RxVia.secondary) return;
    _radio2LastSeen = DateTime.now();
  }

  // --- The radio's own airtime limit ------------------------------------
  //
  // `RESP_CODE_TUNING_PARAMS` (0x17) carries `rx_delay_base` and `airtime_factor`
  // as thousandths. `airtime_factor` is the radio's own duty-cycle rule: it may
  // transmit `1 / (1 + af)` of the time. The app's meter invents a budget of its
  // own, so showing the radio's actual figure is the only way the two can be
  // reconciled.

  TuningParams? _tuningParams;

  /// The radio's tuning, or null while it has not answered.
  TuningParams? get tuningParams => _tuningParams;

  void _trackTuningParams(MeshcoreInbound f) {
    if (f is! TuningParamsFrame) return;
    _tuningParams = f.params;
  }

  Future<void> requestTuningParams() async {
    if (!isReady) return;
    try {
      await send(MeshcoreFrameCodec.getTuningParams());
    } catch (_) {
      _emitTaskError('getTuningParams');
    }
  }

  // --- The frequency ranges the radio will repeat on -------------------
  //
  // `CMD_GET_ALLOWED_REPEAT_FREQ` (0x1A) is the radio's own rule about which
  // bands it may relay in, as a list of kHz ranges. It is read-only and worth
  // showing: it is the reason a radio hears a channel and will not repeat it,
  // which is otherwise indistinguishable from a range problem.

  List<({int lowerKhz, int upperKhz})>? _allowedRepeatFreq;

  /// The ranges the radio will repeat on, in kHz, or null while it has not
  /// answered. An empty list means it reported none.
  List<({int lowerKhz, int upperKhz})>? get allowedRepeatFreq =>
      _allowedRepeatFreq;

  void _trackAllowedRepeatFreq(MeshcoreInbound f) {
    if (f is! UnsupportedFrame) return;
    if (f.opcode != MeshcoreResponse.allowedRepeatFreq.code) return;
    _allowedRepeatFreq = MeshcoreFrameCodec.decodeAllowedRepeatFreq(f.raw);
  }

  Future<void> requestAllowedRepeatFreq() async {
    if (!isReady) return;
    try {
      await send(MeshcoreFrameCodec.getAllowedRepeatFreq());
    } catch (_) {
      _emitTaskError('getAllowedRepeatFreq');
    }
  }

  void _trackFloodScope(MeshcoreInbound f) {
    if (f is! UnsupportedFrame) return;
    if (f.opcode != MeshcoreResponse.defaultFloodScope.code) return;
    final ({String name, Uint8List key})? scope =
        MeshcoreFrameCodec.decodeDefaultFloodScope(f.raw);
    _floodScopeName = scope?.name ?? '';
    notifyListeners();
  }

  /// Ask for the table once per connection, incrementally when we know the
  /// radio's last `lastmod`.
  Future<void> _syncContactsOnConnect() async {
    if (!isReady || _contactsSyncRequested) return;
    _contactsSyncRequested = true;
    try {
      // `since` is only meaningful when the app still holds the table it
      // describes. With an empty table an incremental request answers with the
      // handful of contacts changed since the last session, so the app kept an
      // empty list while the radio reported 193 of 350: Ping, Trace and every
      // telemetry tool then said "no synced contacts yet".
      // Wait for the persisted table: asking for `since` is only right when the
      // table it describes is in memory, and the load is the only thing that
      // puts it there. A load that fails leaves the table empty, which the rule
      // below then reads as "ask for everything".
      final Future<void>? load = _contactsLoad;
      if (load != null) await load;
      await requestContacts(
          since: (_contactsSince == 0 || _contacts.isEmpty)
              ? null
              : _contactsSince);
    } catch (_) {
      // A refused or unsent request is not fatal: the device-contacts screen
      // can ask again, and the next connect retries.
      _contactsSyncRequested = false;
    }
  }

  void _trackContactProbe(MeshcoreInbound f) {
    if (f is ContactsStartFrame) {
      _deviceContactCount = f.count;
      _probedContacts.clear();
      _probing = true;
      _contactSyncAttempt = 0;
      _contactsIncomplete = false;
      _armContactIdle();
    } else if (f is ContactFrame && _probing) {
      _probedContacts.add(f.contact);
      // The wait is for the *next* frame, not for a fixed window: a full table
      // is hundreds of frames and a slow link can take longer than any single
      // timeout, so each arrival pushes the deadline out.
      _armContactIdle();
    } else if (f is EndOfContactsFrame) {
      // The radio finished the table, so whatever an earlier stalled attempt
      // missed is now supplied.
      _contactsIncomplete = false;
      _completeContactSync();
      // The radio states the newest `lastmod` it sent, so the next request can
      // be incremental. Persisted, because a reconnect after a restart is the
      // common case and re-streaming the whole table costs BLE seconds.
      final int lastmod = f.mostRecentLastMod;
      if (lastmod > _contactsSince) {
        _contactsSince = lastmod;
        unawaited(_persistContactsSince(lastmod));
      }
    }
  }

  // -------------------------------------------------------------------
  // Per-contact telemetry permissions (R54 follow-on). The radio answers
  // another node's telemetry scan itself (firmware `onContactRequest`);
  // when our telemetry mode is "Contacts" (ALLOW_FLAGS) it only replies
  // if that contact's flag bits grant it. We're the only place that can
  // set those bits, by re-sending the contact via ADD_UPDATE_CONTACT.
  // -------------------------------------------------------------------

  /// Raw synced contact records, keyed by pub-key hex. Populated as the
  /// device streams its contact list.
  final Map<String, Contact> _contacts = <String, Contact>{};

  /// The raw synced [Contact] for [pubKeyHex], or null if the node is
  /// only advert-heard (not a synced contact on the device).
  Contact? contactRecordFor(String pubKeyHex) => _contacts[pubKeyHex];

  /// Every contact the radio has synced, as the app sees them (superseded
  /// keys hidden). A snapshot, not a live view.
  List<Contact> get syncedContacts =>
      List<Contact>.unmodifiable(_contacts.values);

  /// True when the node is a synced contact — a prerequisite for any
  /// telemetry exchange (telemetry is contact-only).
  bool isSyncedContact(String pubKeyHex) => _contacts.containsKey(pubKeyHex);

  /// Push a node onto the **radio's** contact list (`CMD_ADD_UPDATE_CONTACT`)
  /// so DMs can route to it. The companion protocol only *pulls* contacts:
  /// an advert-heard node (incl. a manually re-homed key) lives only in the
  /// app's `_nodes` until we add it here, and the firmware can't address a
  /// DM to a 6-byte prefix it has no contact for — so the DM silently fails
  /// while *channel* messages (flooded, contact-free) still work. Uses a
  /// **flood** path (`out_path_len = 0xFF`): reachable immediately like a
  /// channel send; the device upgrades to a direct route once it learns
  /// one. Needs the FULL 32-byte key (a bare prefix can't form a contact).
  Future<bool> addNodeAsDeviceContact(String pubKeyHex,
      {String? name, int? type}) async {
    if (!isReady) return false;
    final String hex = pubKeyHex.toLowerCase();
    if (hex.length != kPubKeySize * 2) return false;
    if (!RegExp(r'^[0-9a-f]+$').hasMatch(hex)) return false;
    final DiscoveredNode? n = _nodes[hex];
    final Uint8List pub = Uint8List.fromList(<int>[
      for (int i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]);
    String nm = (name ?? n?.name ?? hex.substring(0, 8)).trim();
    if (nm.isEmpty) nm = hex.substring(0, 8);
    if (nm.length > 31) nm = nm.substring(0, 31);
    final int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final Contact c = Contact(
      publicKey: pub,
      type: type ?? n?.type ?? 1,
      flags: 0,
      outPathLen: kPathLenFlood, // flood; the device learns a direct path
      outPath: Uint8List(kMaxPathSize),
      name: nm,
      lastAdvertTimestamp: n?.deviceAdvertUnix ?? 0,
      latitudeMicros:
          n?.latitude != null ? (n!.latitude! * 1e6).round() : 0,
      longitudeMicros:
          n?.longitude != null ? (n!.longitude! * 1e6).round() : 0,
      lastMod: now,
    );
    // The radio answers OK or ERR, and a transport-level success is not an add:
    // `send` throwing only means the frame did not reach the link. The marker
    // puts the answer where every other command's answer goes, so `ERR_CODE_TABLE_FULL`
    // (3) becomes state the device page can show instead of a silent refusal,
    // and a caller is not blocked waiting for a reply that is normally immediate.
    _registerMarker(_contactAddMarker, CommandAnswer.ok);
    try {
      await send(MeshcoreFrameCodec.addUpdateContact(c));
      _contacts[hex] = c; // reflect locally; device confirms on next sync
      _saveContactsSoon();
      notifyListeners();
      return true;
    } catch (_) {
      _dropPending(_contactAddMarker);
      _emitTaskError('addContact');
      return false;
    }
  }

  /// Remove a contact from the **radio's** contact table
  /// (`CMD_REMOVE_CONTACT`), freeing a slot. Used to retire a dead key
  /// when re-homing a contact (the table is finite — `ERR_CODE_TABLE_FULL`
  /// is what blocks adding the new key otherwise). Needs the full key.
  Future<void> removeDeviceContact(String pubKeyHex) async {
    if (!isReady) return;
    final String hex = pubKeyHex.toLowerCase();
    if (hex.length != kPubKeySize * 2) return;
    if (!RegExp(r'^[0-9a-f]+$').hasMatch(hex)) return;
    final Uint8List pub = Uint8List.fromList(<int>[
      for (int i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]);
    try {
      await send(MeshcoreFrameCodec.removeContact(pub));
      _contacts.remove(hex);
      _clearContactsFull();
      _saveContactsSoon();
      notifyListeners();
    } catch (_) {
      _emitTaskError('removeContact');
    }
  }

  /// Wipe the radio's ENTIRE contact table (one `CMD_REMOVE_CONTACT` per
  /// entry). Channels don't need contacts, so this only affects DMs — the
  /// user re-adds just the people they actually want to direct-message.
  /// Returns the number removed. Re-probe afterwards to confirm.
  Future<int> removeAllDeviceContacts() async {
    if (!isReady) return 0;
    final List<Contact> all = List<Contact>.of(_probedContacts);
    int n = 0;
    for (final Contact c in all) {
      try {
        await send(MeshcoreFrameCodec.removeContact(c.publicKey));
        n++;
      } catch (_) {
        _emitTaskError('removeContact');
      }
    }
    _contacts.clear();
    _probedContacts.clear();
    _deviceContactCount = 0;
    _clearContactsFull();
    _saveContactsSoon();
    notifyListeners();
    return n;
  }

  bool _isFavOrKnown(String hex) =>
      _favorites.contains(hex) || _known.contains(hex);

  /// Is a probed contact a candidate for an "out of range" scrub? Never
  /// for favourites/known (protected). A contact **hiding its location**
  /// (lat/lon 0,0 — no GPS) counts as out of range by policy; one with a
  /// known location is out of range when it's farther than [radiusKm]
  /// from us (which needs [ownLocation]).
  bool _isOutOfRange(Contact c, double radiusKm) {
    if (_isFavOrKnown(_hex(c.publicKey))) return false;
    if (c.latitudeMicros == 0 && c.longitudeMicros == 0) return true;
    final double? d = distanceMetersTo(
        c.latitudeMicros / 1e6, c.longitudeMicros / 1e6);
    return d != null && d > radiusKm * 1000;
  }

  /// Is a probed contact "stale" — not heard in [days]? Never for
  /// favourites/known. A contact whose last-advert is unset (0) counts
  /// as never-heard → stale.
  bool _isStale(Contact c, int days) {
    if (_isFavOrKnown(_hex(c.publicKey))) return false;
    final int adv = c.lastAdvertTimestamp;
    final int lastHeard = adv == 0 ? 0 : adv + _deviceClockOffsetSec;
    final int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return (now - lastHeard) > days * 86400;
  }

  /// Preview counts for the scrub dialogs.
  int outOfRangeContactCount(double radiusKm) =>
      _probedContacts.where((Contact c) => _isOutOfRange(c, radiusKm)).length;
  int staleContactCount(int days) =>
      _probedContacts.where((Contact c) => _isStale(c, days)).length;

  /// Remove a set of probed contacts from the radio's table; returns the
  /// number removed. Shared by the out-of-range / stale / all scrubs.
  Future<int> _removeContactBatch(List<Contact> targets) async {
    if (!isReady || targets.isEmpty) return 0;
    int n = 0;
    for (final Contact c in targets) {
      try {
        await send(MeshcoreFrameCodec.removeContact(c.publicKey));
        _contacts.remove(_hex(c.publicKey));
        _probedContacts.remove(c);
        n++;
      } catch (_) {
        _emitTaskError('removeContact');
      }
    }
    if (n > 0) {
      if (_deviceContactCount != null) {
        _deviceContactCount = (_deviceContactCount! - n).clamp(0, 1 << 30);
      }
      notifyListeners();
    }
    return n;
  }

  /// Remove every out-of-range contact (far, or hiding its location).
  Future<int> removeOutOfRangeContacts(double radiusKm) =>
      _removeContactBatch(_probedContacts
          .where((Contact c) => _isOutOfRange(c, radiusKm))
          .toList(growable: false));

  /// Remove every contact not heard in [days].
  Future<int> removeStaleContacts(int days) =>
      _removeContactBatch(_probedContacts
          .where((Contact c) => _isStale(c, days))
          .toList(growable: false));

  /// Grant/revoke this contact's permission to request each telemetry
  /// class from us (used by the "Contacts" telemetry mode). Preserves
  /// the favourite bit and any bits we don't manage. No-op if the node
  /// isn't a synced contact or we aren't ready.
  Future<void> setContactTelemetryPermissions(
    String pubKeyHex, {
    bool? base,
    bool? location,
    bool? environment,
  }) async {
    final Contact? c = _contacts[pubKeyHex];
    if (c == null || !isReady) return;
    int flags = c.flags;
    int set(int flags, int bit, bool? on) {
      if (on == null) return flags;
      return on ? (flags | bit) : (flags & ~bit);
    }

    flags = set(flags, Contact.flagTelemBase, base);
    flags = set(flags, Contact.flagTelemLocation, location);
    flags = set(flags, Contact.flagTelemEnvironment, environment);
    if (flags == c.flags) return;
    final Contact updated = c.copyWith(flags: flags);
    _contacts[pubKeyHex] = updated; // optimistic
    notifyListeners();
    await send(MeshcoreFrameCodec.addUpdateContact(updated));
  }

  /// Broadcast our own advert so neighbours discover us.
  Future<void> sendSelfAdvert({bool flood = true}) async {
    // The firmware answers with OK; register it so that OK is not
    // credited to a channel message waiting for its own.
    _registerMarker(_advertSendMarker, CommandAnswer.ok);
    try {
      await send(gated: true, MeshcoreFrameCodec.sendSelfAdvert(flood: flood));
    } catch (_) {
      _dropPending(_advertSendMarker);
      rethrow;
    }
  }

  bool _scanning = false;
  Timer? _scanTimer;

  /// True while a [scan] is actively soliciting/collecting adverts.
  bool get isScanning => _scanning;

  /// Detect what's in the area: flood our advert (so neighbours
  /// respond) and pull the radio's contact list, then keep collecting
  /// inbound adverts. The window is just UI feedback — adverts keep
  /// arriving passively afterwards.
  Future<void> scan({
    Duration window = const Duration(seconds: 10),
  }) async {
    if (!isReady) return;
    _scanning = true;
    notifyListeners();
    _scanTimer?.cancel();
    _scanTimer = Timer(window, () {
      _scanning = false;
      notifyListeners();
    });
    try {
      await sendSelfAdvert(flood: true);
      await requestContacts();
      // Pull anything the device has already queued (heard adverts
      // may be sitting behind MSGS_WAITING, not pushed live). A scan
      // reaches back over whatever accumulated, so this is backlog.
      _drainStart(backlog: true);
    } catch (_) {
      // Surface via state/error elsewhere; scan window still elapses.
    }
  }

  /// Call when the app returns to the foreground (R17 — the app is
  /// usually backgrounded/screen-locked). If still linked, pull
  /// anything the radio queued while we were away; if the link
  /// dropped and a device is paired, bring it back (reaching `ready`
  /// auto-drains). Respects a user-initiated [disconnect].
  Future<void> onAppResumed() async {
    if (_manualDisconnect) return; // user chose to stay disconnected
    // A refused service start is retryable once the app is in the foreground,
    // which is the only place Android allows it.
    if (_bgKeepaliveEnabled && _keepaliveFailure != null && isReady) {
      unawaited(_startKeepalive());
    }
    if (isReady) {
      _drainStart(backlog: true); // buffered while backgrounded
      return;
    }
    if (_connecting) return; // a (re)connect is already in flight
    if (hasPairedDevice) await connect();
  }

  /// User-initiated disconnect. Latches off auto-reconnect until the
  /// next explicit [connect].
  ///
  /// Bug fix (post R41): explicitly flip [_state] → disconnected and
  /// notify listeners. The underlying [MeshcoreConnection] state
  /// stream may not emit a state change reliably when the transport
  /// is closed from above (it's designed to react to a remote drop,
  /// not a local one), so the dashboard would otherwise still read
  /// "READY" until something else triggered a rebuild. Setting
  /// state inline is idempotent with any later stream-driven update.
  Future<void> disconnect() async {
    _manualDisconnect = true;
    _reconnectGen++; // cancel any pending scheduled retry
    _battTimer?.cancel();
    _selfInfoTimer?.cancel();
    _telemPollTimer?.cancel();
    unawaited(_keepalive.stop());
    await _transport?.close();
    _transport = null;
    _state = MeshcoreConnectionState.disconnected;
    notifyListeners();
  }

  /// Label of the saved paired device (loaded lazily for the UI).
  String? get pairedName => _pairedName;
  String? _pairedName;
  bool get hasPairedDevice => _pairedName != null;

  /// Saved remote ID for the currently-paired device, or null when
  /// nothing is paired. Hydrated alongside [_pairedName]; used by
  /// the device-manager UI to highlight which history row is
  /// "current".
  String? get pairedRemoteId => _pairedRemoteId;
  String? _pairedRemoteId;

  /// R41+1 — rolling history of recently-paired devices (last 5).
  /// Populated from prefs at construction; mutates whenever the
  /// BLE layer records a successful pair or the user forgets an
  /// entry. UI reads via [pairedHistory].
  List<PairedDeviceHistoryEntry> _pairedHistory =
      const <PairedDeviceHistoryEntry>[];
  List<PairedDeviceHistoryEntry> get pairedHistory =>
      List<PairedDeviceHistoryEntry>.unmodifiable(_pairedHistory);

  Future<void> _refreshHistory() async {
    _pairedHistory = await PairedDeviceHistoryStore.load();
    notifyListeners();
  }

  /// Post R41 bug fix — re-read the persisted pairing into the
  /// cached `_pairedName` / `_pairedRemoteId` fields. Fired from the
  /// ready-state listener so a fresh scan-and-connect (which writes
  /// the pairing low in the BLE stack) also surfaces the device's
  /// name in the Device sheet. Also refreshes history so the new
  /// pairing appears at the top of "Recently paired".
  Future<void> _hydratePairedFromPrefs() async {
    final PairedDevice? p = await PairedDeviceStore.read();
    if (p == null) return;
    if (_pairedName == p.name && _pairedRemoteId == p.remoteId) return;
    _pairedName = p.name;
    _pairedRemoteId = p.remoteId;
    await _refreshHistory(); // also notifies
  }

  /// Call once at startup: if a device was previously paired,
  /// auto-reconnect to it (direct connect, scan fallback). Safe to
  /// call when nothing is paired (no-op).
  Future<void> autoConnectIfPaired() async {
    // Eagerly hydrate the history alongside the active pair so the
    // device-manager sheet has its "Recently paired" list ready on
    // first open — no second roundtrip needed.
    PairedDevice? p = await PairedDeviceStore.read();
    _pairedHistory = await PairedDeviceHistoryStore.load();
    // **A bond is a pairing, whichever menu made it.** Pairing a radio from
    // the phone's own Bluetooth settings writes the OS bond and nothing here,
    // so the app used to start saying "no device paired" for a radio Android
    // was already bonded to — two states for one pairing. Adopt the OS bond
    // and persist it, so from now on both routes read the same.
    p ??= await BleConnector.adoptableBond(
      historyIds: _pairedHistory
          .map((PairedDeviceHistoryEntry e) => e.remoteId)
          .toList(),
    );
    if (p == null) {
      notifyListeners();
      return;
    }
    if (p.remoteId != _pairedRemoteId) {
      await PairedDeviceStore.save(p.remoteId, p.name);
    }
    _pairedName = p.name;
    _pairedRemoteId = p.remoteId;
    notifyListeners();
    await connect();
  }

  /// Forget the saved radio and disconnect — no more auto-reconnect
  /// until the user pairs again. R41+1: also drops the current
  /// device's entry from the recently-paired history; the user
  /// chose "forget", we should not leave a one-tap reconnect
  /// breadcrumb pointing back at it.
  Future<void> forgetDevice() async {
    final String? rid = _pairedRemoteId;
    // The table and the token that describes it belong to the radio being
    // forgotten. Leaving them behind would let the next radio be searched with
    // a token from this one, which is the same empty-table bug by another road.
    _contactsSaveTimer?.cancel();
    _contacts.clear();
    _contactsSince = 0;
    _deviceContactCount = null;
    _contactsFull = false;
    await PairedDeviceStore.clear();
    // Not awaited: forgetting a radio must not depend on a sealed store that
    // may be unavailable. The in-memory table is already gone, and anything the
    // clear leaves behind is overwritten by the next radio's sync.
    unawaited(ContactStore.clear().catchError((Object _) {}));
    // Forget the OS bond too, not just our record of it. Leaving it behind
    // would let [autoConnectIfPaired] adopt the radio straight back on the
    // next start — the user pressed Forget and would see it return.
    await BleConnector.forgetBond(rid);
    if (rid != null) await PairedDeviceHistoryStore.remove(rid);
    _pairedName = null;
    _pairedRemoteId = null;
    await disconnect();
    await _refreshHistory();
  }

  /// R41+1 — drop a *specific* entry from the recently-paired list.
  /// When [remoteId] is the currently-active pair, this also
  /// triggers a full [forgetDevice] so the UI stays consistent.
  Future<void> forgetHistoryEntry(String remoteId) async {
    if (remoteId == _pairedRemoteId) {
      await forgetDevice();
      return;
    }
    await PairedDeviceHistoryStore.remove(remoteId);
    await _refreshHistory();
  }

  /// R41+1 — reconnect to a device the user previously paired with,
  /// looked up by remote ID in the rolling history. Same code path
  /// as [connectToPickedDevice]; the entry is also touched so it
  /// pops to the top of the history list.
  Future<void> connectFromHistory(String remoteId) async {
    for (final PairedDeviceHistoryEntry e in _pairedHistory) {
      if (e.remoteId == remoteId) {
        await connectToPickedDevice(
            remoteId: e.remoteId, name: e.name);
        return;
      }
    }
  }

  /// R41 — pair to (and connect to) a specific BLE device the user
  /// picked from the scan results. Tears down any existing link,
  /// writes the new pairing to [PairedDeviceStore] so auto-reconnect
  /// uses it from now on, clears the manual-disconnect latch, and
  /// kicks a fresh [connect]. The transport factory was set at
  /// construction time and reads the paired remote ID on each
  /// [BleConnector.autoConnect] call — so saving + reconnecting is
  /// all that's needed; we don't have to swap the factory.
  Future<void> connectToPickedDevice({
    required String remoteId,
    required String name,
  }) async {
    await disconnect();
    await PairedDeviceStore.save(remoteId, name);
    // R41+1 — touch eagerly so the manager sheet sees the chosen
    // device promoted to the top of history even if the BLE
    // discover/notify path that runs `BleConnector._finish` later
    // hasn't landed yet (UX latency improvement).
    await PairedDeviceHistoryStore.touch(remoteId, name);
    _pairedName = name;
    _pairedRemoteId = remoteId;
    _manualDisconnect = false;
    await _refreshHistory();
    await connect();
  }

  /// Frames where at least one tracker threw, so the frame arrived in part.
  ///
  /// The trackers below are functions of the frame plus the app's stores and
  /// none of them is sandboxed, so one throw used to discard every tracker
  /// after it *and* the notification at the end: a message could be recorded
  /// and never heat-mapped, or a delivery state left half-updated, with an
  /// uncaught async error as the only trace. Each tracker now runs on its own
  /// ([runFrameTrackers]); this counts the frames that lost one. Per session,
  /// and Diagnostics says nothing while it is zero, like every other counter
  /// there.
  int get framesDropped => _framesDropped;
  int _framesDropped = 0;

  /// One received frame, through every tracker, then one notification.
  ///
  /// `_expireCommands` runs first and inside the same isolation: a command
  /// whose reply waited past the ledger's timeout cannot hold the head of the
  /// answer order any more, and that matters more than the rest of the frame
  /// when a tracker is the thing that broke.
  void _processInbound(MeshcoreInbound f) {
    _lastFrame = f;
    final List<void Function(MeshcoreInbound)> trackers =
        <void Function(MeshcoreInbound)>[
      // A command that has waited past the ledger's timeout cannot hold the
      // head of the answer order any more.
      (MeshcoreInbound _) => _expireCommands(),
      _trackDeviceClock,
      _trackBattery,
      _trackDeviceInfo,
      _trackCustomVars,
      _trackFloodScope,
      _trackAllowedRepeatFreq,
      _trackTuningParams,
      _trackRadioProfiles,
      _trackTelemetry,
      // R25+1 — own movement trail. Every inbound frame might have bumped
      // ownLocation (SelfInfoFrame's lat/lon), so sample here. Deduped
      // internally by movement threshold.
      (MeshcoreInbound _) => _trackOwnLocationForTrail(),
      _ingestKnown,
      _trackContactProbe,
      _trackContactLifecycle,
      _trackAutoAddConfig,
      _ingestDm,
      _maybeDrain,
      _ingestNode,
      _ingestChat,
      _ingestChannelData,
      _trackMessageHeat,
      _trackDelivery,
      _logEvent,
    ];
    final int lost = runFrameTrackers(
      trackers,
      f,
      onFailure: (Object error, StackTrace stack) =>
          AppErrors.record(error, stack, where: 'frame'),
    );
    if (lost > 0) _framesDropped++;
    _notifyForFrame(f);
  }

  /// Notify at the leading edge of a burst, then at most once per window.
  ///
  /// Every inbound frame calls this and 43 widgets watch the whole controller,
  /// so a contact sync of 350 nodes rebuilt all of them 350 times in a few
  /// seconds, which is the jank a user reads as "the app is busy".
  ///
  /// Two things travel on this notification and cannot be allowed to wait:
  /// a listener that *reacts* to a frame (the SOS watchdog classifies a
  /// refusal from the message row, the CLI path resolves from the ledger) and
  /// any frame the user just caused. Those notify synchronously — see
  /// [notifyNow]. Only the bulk streams, which arrive as a flood and whose
  /// readers are all `watch`ing widgets, are coalesced.
  ///
  /// The timer exists only while a burst is being coalesced, which matters
  /// twice: an isolated frame must never leave a timer armed (a pending timer
  /// fails a widget test and wakes a phone), and the trailing notify is what
  /// guarantees the last frame's state is ever rendered.
  static const Duration _frameNotifyWindow = Duration(milliseconds: 50);
  Timer? _frameNotifyTimer;
  DateTime? _lastFrameNotifyAt;

  /// Frames whose delivery changes something a listener acts on, rather than
  /// something a widget draws. A command answer, a send confirmation and the
  /// self-info handshake all belong here: they are the ones a caller is
  /// awaiting, and delaying them by a notification window would make the app
  /// look slower than it is.
  bool _answersSomebodyNow(MeshcoreInbound f) =>
      f is OkFrame ||
      f is ErrorFrame ||
      f is MsgSentFrame ||
      f is AckFrame ||
      f is SelfInfoFrame ||
      f is DisabledFrame;

  void _notifyForFrame(MeshcoreInbound f) {
    if (_answersSomebodyNow(f)) {
      _frameNotifyTimer?.cancel();
      _frameNotifyTimer = null;
      _lastFrameNotifyAt = DateTime.now();
      notifyListeners();
      return;
    }
    final DateTime now = DateTime.now();
    final DateTime? last = _lastFrameNotifyAt;
    if (last == null || now.difference(last) >= _frameNotifyWindow) {
      _frameNotifyTimer?.cancel();
      _frameNotifyTimer = null;
      _lastFrameNotifyAt = now;
      notifyListeners();
      return;
    }
    // Inside the window: this frame shares the burst's trailing notify.
    if (_frameNotifyTimer != null) return;
    _frameNotifyTimer = Timer(_frameNotifyWindow - now.difference(last), () {
      _frameNotifyTimer = null;
      _lastFrameNotifyAt = DateTime.now();
      notifyListeners();
    });
  }

  /// Late notifications are dropped rather than thrown, by [SafeNotifier]:
  /// several paths can land after disposal — the constructor's unawaited
  /// `_meshbook.load()` / `_dmReadStore.load()` chains, and any `await` still
  /// in flight when the screen goes away. `ChangeNotifier` asserts in debug on
  /// that, so "construct a controller, dispose it, keep going" (what a widget
  /// test does, and what any future re-create-the-controller flow does) used to
  /// throw out of the framework rather than being a no-op.
  @override
  void dispose() {
    _manualDisconnect = true;
    _reconnectGen++; // invalidate any pending scheduled retry
    _scanTimer?.cancel();
    _battTimer?.cancel();
    _selfInfoTimer?.cancel();
    _battHistorySaveTimer?.cancel();
    _telemPollTimer?.cancel();
    _meshbookSaveTimer?.cancel();
    // The contact table has its own debounce, so closing the app inside the
    // three-second window must still write it: a restart would otherwise ask
    // the radio only for changes since a token describing a table that was
    // never saved, which is the empty-table bug this store exists to end.
    if (_contactsSaveTimer != null) {
      _contactsSaveTimer!.cancel();
      unawaited(ContactStore.save(_contacts.values)
          .catchError((Object _) {}));
      _contactsSaveTimer = null;
    }
    _drainWatchdog?.cancel();
    // The two protocol walks own timers of their own: the channel probe's idle
    // window and the contact stream's watchdog. Left armed they outlive the
    // controller and fire into a disposed one.
    _channelProbeIdleTimer?.cancel();
    _channelProbeIdleTimer = null;
    _contactIdleTimer?.cancel();
    _contactIdleTimer = null;
    _frameNotifyTimer?.cancel();
    _frameNotifyTimer = null;
    for (final Timer t in _deliveryTimers.values) {
      t.cancel();
    }
    _deliveryTimers.clear();
    _statesSub?.cancel();
    _inboundSub?.cancel();
    _rawSub?.cancel();
    _flushChat(); // final flush
    unawaited(_flushBatteryHistory()); // final flush
    unawaited(_keepalive.stop());
    unawaited(_incomingCh.close());
    unawaited(_incomingDm.close());
    unawaited(_taskErrors.close());
    unawaited(_adverts.close());
    unawaited(_channelDatagramStream.close());
    unawaited(_transport?.close());
    unawaited(_connection.dispose());
    super.dispose();
  }
}

/// What came back from one radio CLI command.
///
/// The firmware answers `CMD_RUN_CLI_COMMAND` with zero or more text frames and
/// then a bare answer, so there are five outcomes and each one is a different
/// thing to tell the reader. None of them is a bool: "the radio said nothing"
/// and "the radio refused" are not the same fact, and a screen that renders them
/// as one teaches the user to distrust both.
sealed class RadioCliResult {
  const RadioCliResult();

  /// The radio's own words, when it said any. Present on every outcome that
  /// carried text, including a refusal and a half-finished answer.
  String get text;
}

/// The radio ran the command and closed the answer with `OK`.
final class RadioCliAnswered extends RadioCliResult {
  const RadioCliAnswered({required this.text});

  @override
  final String text;

  /// The on/off state the reply states, when it states one plainly.
  ///
  /// This is a convenience over the radio's own text, not a second parser of the
  /// CLI: the last whole word that is `on`/`off`/`true`/`false` wins, and
  /// anything else is `null` so the screen shows the verbatim text rather than
  /// guessing. A firmware that answers "buzzer: disabled" therefore reads as
  /// unknown until someone teaches this rule that word — deliberately, because a
  /// wrong state is worse than no state on a control that changes a radio.
  bool? get onOff {
    final List<String> words = text
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((String w) => w.isNotEmpty)
        .toList();
    for (final String w in words.reversed) {
      if (w == 'on' || w == 'true' || w == '1') return true;
      if (w == 'off' || w == 'false' || w == '0') return false;
    }
    return null;
  }

  @override
  String toString() => 'RadioCliAnswered("$text")';
}

/// The radio refused the command, with its own error code when it sent one.
final class RadioCliRejected extends RadioCliResult {
  const RadioCliRejected({required this.code, required this.text});

  final int? code;

  @override
  final String text;

  @override
  String toString() => 'RadioCliRejected(err $code, "$text")';
}

/// Nothing closed the answer inside the window. The link may still be fine and
/// the radio still working: a command that produces no output is answered by the
/// same OK as one that produces ten lines, so silence is a missing answer, not a
/// verdict.
final class RadioCliSilent extends RadioCliResult {
  const RadioCliSilent({this.partial = ''});

  /// The lines that did arrive before the window closed, if any.
  final String partial;

  @override
  String get text => partial;

  @override
  String toString() => 'RadioCliSilent("$partial")';
}

/// A command is already waiting for its answer, so this one was not sent.
final class RadioCliBusy extends RadioCliResult {
  const RadioCliBusy();

  @override
  String get text => '';

  @override
  String toString() => 'RadioCliBusy()';
}

/// There is no usable link: not connected, or the send failed.
final class RadioCliUnavailable extends RadioCliResult {
  const RadioCliUnavailable({this.detail = ''});

  final String detail;

  @override
  String get text => '';

  @override
  String toString() => 'RadioCliUnavailable("$detail")';
}
