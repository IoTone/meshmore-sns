import 'media/media_inbox.dart';
import 'media/media_journal.dart';
import 'media/photo_source.dart';
import 'media/media_composer.dart';
import 'places/place_photo.dart';
import 'media/media_codec.dart';
import 'voice/native_voice_codec.dart';
import 'voice/voice_capture.dart';
import 'voice/voice_codec.dart';
import 'voice/voice_inbox.dart';
import 'voice/voice_playback.dart';
// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

import 'app/boot_guard.dart';
import 'maps/compass.dart';
import 'app/mm_text_scaler.dart';
import 'package:provider/provider.dart';

import 'package:meshmore_sns_app/app/demo_mode.dart';
import 'package:meshmore_sns_app/app_router.dart';
import 'package:meshmore_sns_app/app/app_errors.dart';
import 'package:meshmore_sns_app/app_state_model.dart';
import 'package:meshmore_sns_app/chat/channel_read_store.dart';
import 'package:meshmore_sns_app/cue/asset_audio_pack.dart';
import 'package:meshmore_sns_app/cue/cue_service.dart';
import 'package:meshmore_sns_app/docs/docs_repository.dart';
import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/legal/terms_controller.dart';
import 'package:meshmore_sns_app/licenses/asset_licenses.dart';
import 'package:meshmore_sns_app/maps/maps_controller.dart';
import 'package:meshmore_sns_app/field/position_history.dart';
import 'package:meshmore_sns_app/field/relationship.dart';
import 'package:meshmore_sns_app/geofence/geofence_controller.dart';
import 'package:meshmore_sns_app/telemetry/coverage_session.dart';
import 'package:meshmore_sns_app/tools/discover_tool.dart';
import 'package:meshmore_sns_app/meshcore/auto_publish_controller.dart';
import 'package:meshmore_sns_app/meshcore/block_filter.dart';
import 'package:meshmore_sns_app/meshcore/block_store.dart';
import 'package:meshmore_sns_app/meshcore/background_keepalive.dart';
import 'package:meshmore_sns_app/meshcore/city_lookup.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/meshcore/radio_lease.dart';
import 'package:meshmore_sns_app/sos/sos_controller.dart';
import 'package:meshmore_sns_app/bot/bot_controller.dart';
import 'package:meshmore_sns_app/peer/peer_profiles.dart';
import 'package:meshmore_sns_app/meshcore/discovered_node.dart';
import 'package:meshmore_sns_app/notifications/channel_notification_prefs.dart';
import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/notifications/local_notifier.dart';
import 'package:meshmore_sns_app/notifications/app_notification_effects.dart';
import 'package:meshmore_sns_app/notifications/message_notification.dart';
import 'package:meshmore_sns_app/notifications/notification_focus.dart';
import 'package:meshmore_sns_app/shell/shell_view_request.dart';
import 'package:meshmore_sns_app/notifications/notification_service.dart';
import 'package:meshmore_sns_app/notifications/notifier.dart';
import 'package:meshmore_sns_app/perms/first_run_controller.dart';
import 'package:meshmore_sns_app/perms/location_service.dart';
import 'package:meshmore_sns_app/perms/permissions_service.dart';
import 'package:meshmore_sns_app/places/place_report_budget.dart';
import 'package:meshmore_sns_app/places/place_store.dart';
import 'package:meshmore_sns_app/places/place_wiring.dart';
import 'package:meshmore_sns_app/screens/first_run_intro_screen.dart';
import 'package:meshmore_sns_app/screens/terms_screen.dart';
import 'package:meshmore_sns_app/splash/branded_splash_screen.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';
import 'package:meshmore_sns_app/tools/tools_controller.dart';
import 'package:meshmore_sns_app/tts/tts_controller.dart';
import 'package:meshmore_sns_app/util/mm_format.dart';
import 'package:meshmore_sns_app/ui/mm_collapse_controller.dart';

Future<void> main() async {
  final WidgetsBinding widgetsBinding =
      WidgetsFlutterBinding.ensureInitialized();
  // Before anything can throw: a release build has no crash reporter by
  // decision, so the framework error sink, the async sink and the failed-build
  // panel are the whole of the app's crash story.
  AppErrors.install();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // Attribute the bundled non-code assets (docs, GeoNames, Natural
  // Earth, OSM) in the standard license page.
  registerAssetLicenses();

  // R25 Stage 2 — pre-warm the offline city DB so the equal-grid
  // view shows real labels on first paint. Fire-and-forget; failures
  // degrade to grid-coord cell labels.
  unawaited(warmCityLookup());
  await bootGuarded();
}

/// The boot chain, guarded: whatever happens the splash comes down, and the
/// user sees either the app or one line saying why it could not start.
Future<void> bootGuarded() => runBoot(
      boot: startApp,
      onFailed: (Object error) {
        AppErrors.record(error, StackTrace.current, where: 'boot');
        runApp(
          BootFailureApp(
            message: AppErrors.firstLine(error),
            onRetry: () => unawaited(bootGuarded()),
          ),
        );
      },
    );

/// Everything between the splash and the first frame. Split out of [main] so
/// that [runBoot] can guard it and a retry can run it again.
Future<void> startApp() async {
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  // R65 — read the folded-group state before the first frame, so a
  // group the user folded never paints open and then snaps shut.
  final MmCollapseController collapse = MmCollapseController();
  // Radio-free mode is read before the tree exists: it decides whether the
  // launch reaches for a paired companion at all, and doing that after the
  // first frame would make the decision twice.
  final DemoMode demo = DemoMode();
  // Two independent preference reads, one platform-channel round trip. Both
  // are needed before the first frame, so awaiting them in sequence put a
  // second wait in front of the splash for no reason.
  await Future.wait(<Future<void>>[collapse.load(), demo.load()]);
  final MeshcoreController controller = MeshcoreController(
    backgroundKeepalive: createBackgroundKeepalive(),
    locationService: const GeolocatorLocationService(),
  );
  // **The radio is shared.** Another app on this phone can ask Meshmore to let go of the BLE
  // companion, and this is the wiring that makes the answer happen. Attached before the first
  // connect, so a launch cannot race a request that arrived while the process was gone.
  RadioLease.attach(controller);
  // One read, before anything reaches for a companion.
  await RadioLease.refresh();
  // Our own position is the map's anchor and every distance in the app, so it
  // stays live from launch: on-demand fixes left a phone that walked with the
  // map open still drawn where it started. The stream never prompts and only
  // reports movement, so an app with no permission simply keeps the on-demand
  // path and the banner that asks for one.
  controller.startOwnLocationStream();
  if (!demo.enabled) controller.autoConnectIfPaired();
  // D8.20 — one notifier, one focus record, one service. Created before the
  // tree so the notification permission is asked at first launch, not on
  // the first message; the service starts after the first frame so its
  // stream subscription never races the controller's own connect.
  // The block list is read by every surface, so it is one app-scoped store:
  // the timeline, the roster, the map, search, speech and notifications all
  // ask the same object (block-spec §5).
  final BlockStore blockStore = BlockStore();
  unawaited(blockStore.load());
  // Places share the block list: a blocked reporter's stored rows leave with
  // the block rather than sitting on disk behind a read-time filter (places
  // spec §10). Attached here, before the tree reads the store.
  final PlaceStore placeStore = PlaceStore(isBlocked: blockStore.isBlocked)
    ..load();
  attachPlaceBlockDeletion(blockStore, placeStore);
  final BlockFilter blockFilter = BlockFilter(blockStore);
  // When each channel was last read, so a channel badge counts what the
  // reader has not seen rather than the whole channel's traffic.
  final ChannelReadStore channelReads = ChannelReadStore();
  unawaited(channelReads.load());
  // The inbound half of media: one consumer of the radio's channel
  // datagrams, because two consumers would each hold half the chunks. It is
  // app-scoped and started once, so a rebuild cannot subscribe twice.
  final MediaInbox mediaInbox = MediaInbox(
    datagrams: controller.channelDatagramStream,
    codec: const AvifMediaCodec(),
    clock: DateTime.now,
  )..start();
  // The voice half of the same inbox. A completed voice payload has no surface
  // claiming it — nobody is waiting for a note the way a place sheet waits for
  // its picture — so the newest few are kept for the channel they arrived on,
  // and the sheet says they last as long as the process does.
  final VoiceInbox voiceInbox =
      VoiceInbox(completed: mediaInbox.completed)..start();
  // One codec, one recorder and one player for the app: the codec opens the
  // two shipped libraries and builds pitch tables, so a per-tap instance would
  // reload them for nothing. A build without the libraries still starts: every
  // call refuses with a typed failure the sheet has a sentence for.
  final VoiceCodec voiceCodec = NativeVoiceCodec();
  final VoiceCapture voiceCapture = PlatformVoiceCapture();
  final VoicePlayback voicePlayback = AudioplayersVoicePlayback();
  final PlacePhotos placePhotos = PlacePhotos(clock: DateTime.now);

  // Transfers the last process left unfinished. Read at startup so the
  // composer can say so once, instead of the payload vanishing with no trace
  // when the process was killed mid-send.
  final MediaInterruptions mediaInterruptions = MediaInterruptions();
  unawaited(mediaInterruptions.load());
  final LocalNotifier notifier = LocalNotifier();
  final NotificationPrefs notificationPrefs = NotificationPrefs();
  final NotificationFocus notificationFocus = NotificationFocus();
  // A tap has to be able to change the shell's visible view, and the tap
  // handler lives out here with no way to reach the page controller.
  final ShellViewRequest shellViewRequest = ShellViewRequest();
  unawaited(notificationPrefs.load());
  // The notification text follows the app's own locale choice, and it is
  // resolved per message rather than once, so switching language takes
  // effect on the next message without a restart.
  final LocaleController notificationLocale = LocaleController()..load();
  final NotificationService notifications = NotificationService(
    channelMessages: controller.incomingChannelMessages,
    directMessages: controller.incomingDirectMessages,
    notifier: notifier,
    prefs: notificationPrefs,
    focus: notificationFocus,
    strings: () => LocalizedNotificationStrings(
      lookupAppLocalizations(_notificationLocale(notificationLocale.locale)),
    ),
    selfDisplayName: () => controller.selfInfo?.name,
    ownPubKeyHex: () => controller.ownPubKeyHex,
    peerDisplayName: (String key) => _peerName(controller, key),
    channelName: (int slot) => _channelName(controller, slot),
    isBlocked: blockFilter.hidesMessage,
  );
  // Tell the service when the link comes up, so the queue the radio hands over
  // is one "N unread messages" line rather than one notification per message.
  // Only the edge into `ready` matters: a second notification for a link that
  // was already up would start a catch-up window for ordinary traffic.
  MeshcoreConnectionState lastLinkState = controller.state;
  controller.addListener(() {
    final MeshcoreConnectionState now = controller.state;
    if (now != lastLinkState) {
      lastLinkState = now;
      if (now == MeshcoreConnectionState.ready) notifications.onLinkReady();
    }
  });
  notifier.onTap = (String payload) {
    if (payload.startsWith('dm:')) {
      appRouter.push('/dm/${payload.substring(3)}');
    } else if (payload.startsWith('ch:')) {
      final int? slot = int.tryParse(payload.substring(3));
      if (slot == null) return;
      controller.setActiveChannel(slot);
      // The shell is the only thing that knows which page is showing, so the
      // tap asks it rather than going to the root route and stopping there.
      appRouter.go('/');
      shellViewRequest.openChat(slot);
    }
  };
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<MmCollapseController>.value(value: collapse),
        ChangeNotifierProvider<AppState>(create: (_) => AppState()),
        // One compass for every dial in the app: the two radars and the map's
        // arrow. Started here and never stopped, because it is the same phone
        // facing the same way whatever screen is open.
        ChangeNotifierProvider<CompassHeading?>(
            create: (_) => CompassHeading()..start()),
        ChangeNotifierProvider<ThemeController>(
          create: (_) => ThemeController()..load(),
        ),
        // One owner for the per-peer record (R58). Speech reads it,
        // the cue path reads it, the node sheet writes it — but only
        // this instance touches the prefs key.
        ChangeNotifierProvider<PeerProfiles>(create: (_) => PeerProfiles()),
        // Units and clock: one store, read by the formatter every surface uses,
        // so "km" cannot survive in one screen after the reader chose miles.
        ChangeNotifierProvider<FormatPrefs>(
          create: (_) => FormatPrefs()..load(),
        ),
        ChangeNotifierProvider<TtsController>(
          // Speech answers to the same audio master as the cues —
          // without this the quick-mute silenced every chime and
          // left inbound messages speaking aloud.
          // `TtsController.load()` loads the shared per-peer records
          // too, so `PeerProfiles` needs no separate load() here.
          create: (BuildContext ctx) => TtsController(
            theme: ctx.read<ThemeController>(),
            peers: ctx.read<PeerProfiles>(),
          )..load(),
        ),
        Provider<CueService>(
          create: (BuildContext ctx) {
            final ThemeController tc = ctx.read<ThemeController>();
            return CueService(
              theme: tc,
              // R12 per-theme audio: pull WAV cues from
              // assets/audio/<themeKey>/<cue>.wav at play time.
              audio: AssetAudioPack(theme: tc),
              // R12 per-theme haptics: the 'feel' follows the skin too —
              // pattern resolved off the active preset at play time.
              haptic: SystemHapticBackend(theme: tc),
            );
          },
        ),
        ChangeNotifierProvider<DemoMode>.value(value: demo),
        ChangeNotifierProvider<MeshcoreController>.value(value: controller),
        // R59 — the bot. `pskFor` is what makes the "never on Public"
        // refusal real: it reads the slot's live key off the radio,
        // so a slot reset to the stock key stops qualifying at once.
        ChangeNotifierProvider<BotController>(
          create: (BuildContext ctx) => BotController(
            pskFor: ctx.read<MeshcoreController>().channelPsk,
          )..load(),
        ),
        // R60 — Settings → Tools. App-scoped so a soak or range test
        // keeps running while you look at something else.
        ChangeNotifierProvider<ToolsController>(
          create: (BuildContext ctx) =>
              ToolsController(ctx.read<MeshcoreController>()),
        ),
        // SOS and check-in (`meshmore-sos-spec.md`). App-scoped because the
        // alarm has to keep repeating while the screen is closed: the
        // foreground service keeps the isolate alive, and this owns the
        // one-second schedule tick.
        ChangeNotifierProvider<SosController>(
          create: (BuildContext ctx) =>
              SosController(mc: ctx.read<MeshcoreController>())..start(),
        ),
        // Fences watch our own position against circles the user drew. The
        // tick is app-scoped for the same reason the alarm's is: a fence
        // crossed while the screen is off still happened.
        ChangeNotifierProvider<GeofenceController>(
          create: (BuildContext ctx) =>
              GeofenceController(
                  mc: ctx.read<MeshcoreController>(),
                  // A crossing is an alert, so it is heard: the fence screen is
                  // the one place a reader is guaranteed not to be when they
                  // walk through a fence.
                  onRaised: (List<GeofenceAlert> raised) =>
                      ctx.read<CueService>().play(CueKind.alert))
                ..load()
                ..start(),
        ),
        // The recorded trail: our own fixes only, bounded (see
        // `field/position_history.dart`). App-scoped so the map, the export
        // and the coverage session read the same list.
        // Which way each node's distance is going: two measurements, so it
        // belongs to the session, not to a node.
        Provider<RelationshipTracker>(create: (_) => RelationshipTracker()),
        // Coverage: pings from where we are, session-only. The pinger is the
        // app's own discover tool, because that is the one code path that
        // knows how to ask the radio.
        ChangeNotifierProvider<CoverageSession>(
          create: (BuildContext ctx) {
            final ToolsController tools = ctx.read<ToolsController>();
            return CoverageSession(
              mc: ctx.read<MeshcoreController>(),
              pinger: () async {
                await tools.discover.start();
                return <CoverageResponder>[
                  for (final DiscoveredRepeater r in tools.discover.found)
                    CoverageResponder(
                      key: r.response.publicKey,
                      snr: r.weakerSnrDb.round(),
                    ),
                ];
              },
            );
          },
        ),

        ChangeNotifierProvider<PositionRecorder>(
          create: (BuildContext ctx) =>
              PositionRecorder(mc: ctx.read<MeshcoreController>())
                ..load()
                ..start(),
        ),

        // R61 — offline maps (issue #5): tile cache, region packs,
        // event layers. App-scoped so downloads run in the background.
        ChangeNotifierProvider<MapsController>(
          create: (_) => MapsController(
            appVersion: () => AppState.packageInfo?.version ?? '',
          )..load(),
        ),
        Provider<PermissionsService>(
          create: (_) => const PlatformPermissionsService(),
        ),
        // R53 — docs reader: loads bundled/cached markdown and
        // refreshes from GitHub opportunistically. Stateless service.
        Provider<DocsRepository>(create: (_) => DocsRepository()),
        ChangeNotifierProvider<FirstRunController>(
          create: (_) => FirstRunController()..load(),
        ),
        // The terms page is a gate, not a banner: it is read once at
        // first use and again only when the wording changes (N-group:
        // "terms acceptance at first use"). Version lives with the text.
        ChangeNotifierProvider<TermsController>(
          create: (_) => TermsController()..load(),
        ),
        ChangeNotifierProvider<LocaleController>.value(
            value: notificationLocale),
        // Registered nullable on purpose: the notification subsystem is
        // app-scoped and optional, so a widget test that builds this tree
        // without it runs with no notifications instead of failing a lookup
        // it never needed (D8.21's rule, applied to the harness).
        Provider<NotificationFocus?>.value(value: notificationFocus),
        ChangeNotifierProvider<ShellViewRequest?>.value(
            value: shellViewRequest),
        // Places (meshmore-places-spec.md): reports live in one app-scoped
        // store, so the map layer, the history list, the chat echo and
        // search cannot disagree about what exists. The budget is the
        // send-side rate limit and is app-scoped for the same reason: it
        // must survive leaving the sheet that charged it.
        ChangeNotifierProvider<BlockStore>.value(value: blockStore),
        ChangeNotifierProvider<ChannelReadStore?>.value(value: channelReads),
        // The one instance the block-deletion hook above is attached to; a
        // second store built here would leave that hook pointing at nothing.
        ChangeNotifierProvider<PlaceStore>.value(value: placeStore),
        Provider<MediaInbox>.value(value: mediaInbox),
        // Voice: the inbox is nullable-safe for a harness, and the codec,
        // recorder and player are registered so a surface never constructs a
        // native object itself (a widget test keeps none of them and the sheet
        // says which sentence applies).
        ChangeNotifierProvider<VoiceInbox?>.value(value: voiceInbox),
        Provider<VoiceCodec?>.value(value: voiceCodec),
        Provider<VoiceCapture?>.value(value: voiceCapture),
        Provider<VoicePlayback?>.value(value: voicePlayback),
        // The real photo source for the composer: the platform picker plus
        // the engine's decoder. Nullable-safe for harnesses: the composer
        // falls back to the named "cannot read a photo" state.
        Provider<MediaPhotoSource>.value(
            value: const PlatformMediaPhotoSource()),
        Provider<PlacePhotos>.value(value: placePhotos),
        ChangeNotifierProvider<MediaInterruptions>.value(
            value: mediaInterruptions),
        Provider<PlaceReportBudget>(
          create: (_) => PlaceReportBudget(clock: DateTime.now),
        ),
        Provider<Notifier?>.value(value: notifier),
        ChangeNotifierProvider<NotificationPrefs?>.value(
            value: notificationPrefs),
        Provider<NotificationService?>.value(value: notifications),
        // R36 — auto-publish location. Owns its own
        // shared_preferences-backed settings + the periodic
        // timer / position stream. Constructed lazily to read
        // the already-built MeshcoreController; loads persisted
        // state immediately so a previously-enabled loop
        // resumes after a cold launch.
        ChangeNotifierProvider<AutoPublishController>(
          create: (BuildContext ctx) => AutoPublishController(
            mc: ctx.read<MeshcoreController>(),
            location: const GeolocatorLocationService(),
          )..load(),
        ),
      ],
      child: const MyApp(),
    ),
  );
}

/// Root widget. Owns the single MaterialApp + the go_router config;
/// theme and font-scale come from [ThemeController] (R14).
///
/// Lifts `FlutterNativeSplash.remove()` up to here (away from
/// HomeShell) so the native splash dismisses regardless of which
/// gate paints next — HomeShell, the first-run intro, or the
/// loading placeholder.
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  /// Flutter-side splash min-display gate. Even when first-run prefs
  /// resolve in microseconds the user gets ~1.5 s of the branded
  /// splash with the rotating icon + version readout. Without this,
  /// shared_preferences typically resolves before the first frame
  /// and the splash never shows.
  bool _minSplashElapsed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FlutterNativeSplash.remove();
      // After the first frame: the OS channels exist before any message can
      // arrive, and the tap handler is installed before the user can tap.
      // A harness that builds this widget without the notification providers
      // (every widget test) simply runs without notifications, rather than
      // failing on a lookup it never needed.
      final Notifier? notifier = context.read<Notifier?>();
      final NotificationService? service = context.read<NotificationService?>();
      if (notifier != null && service != null) {
        // The bundle's cue, vibration and speech are the app's, not the OS's,
        // so they are attached here, where the providers that own them exist.
        service.effects = AppNotificationEffects(
          onCue: (NotificationClass cls) =>
              context.read<CueService>().play(switch (cls) {
                    NotificationClass.channel => CueKind.messageIn,
                    NotificationClass.direct => CueKind.dmIn,
                    NotificationClass.sos => CueKind.alert,
                  }),
          onVibrate: HapticFeedback.mediumImpact,
          onSpeakChannel: (int slot, String text) =>
              context.read<TtsController>().speakForChannel(slot, text),
        );
        notifier.init().then((_) => service.start());
      }
    });
    Future<void>.delayed(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _minSplashElapsed = true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// D8.20 — a message that arrives while the app is in front is already
  /// visible, so it is not announced. Reading the lifecycle here keeps that
  /// decision out of the notification service, which has no window.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    final NotificationFocus? focus = context.read<NotificationFocus?>();
    if (focus != null) focus.foreground = state == AppLifecycleState.resumed;
  }

  // R4 / U5 — l10n wiring shared between every MaterialApp branch:
  // delegates for the generated AppLocalizations + Material + Cupertino
  // + Widgets, plus the supported-locales list.
  static const List<LocalizationsDelegate<Object>> _localeDelegates =
      <LocalizationsDelegate<Object>>[
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];

  @override
  Widget build(BuildContext context) {
    final ThemeController tc = context.watch<ThemeController>();
    final FirstRunController fr = context.watch<FirstRunController>();
    final LocaleController lc = context.watch<LocaleController>();
    final TermsController terms = context.watch<TermsController>();

    // R21 / U12 — gate the app on first-run state. While the pref
    // is loading we render the splash holder so the test binding
    // doesn't see a different MaterialApp shape mid-frame. When
    // first-run is NOT done we mount a small MaterialApp around the
    // intro screen (so it has theming + a Navigator without booting
    // the full router). When done, the regular router-app boots.
    // Show the branded Flutter splash while either (a) first-run
    // prefs are still loading OR (b) the 1.5 s min-display gate
    // hasn't elapsed. Without (b) the splash never appears on
    // device — shared_preferences usually resolves before the
    // first frame.
    if (!fr.loaded || !_minSplashElapsed) {
      return MaterialApp(
        theme: tc.theme,
        locale: lc.locale,
        supportedLocales: LocaleController.supported,
        localizationsDelegates: _localeDelegates,
        home: const BrandedSplashScreen(),
      );
    }
    if (!fr.done) {
      return MaterialApp(
        title: 'Meshmore SNS',
        theme: tc.theme,
        locale: lc.locale,
        supportedLocales: LocaleController.supported,
        localizationsDelegates: _localeDelegates,
        home: const FirstRunIntroScreen(),
      );
    }
    // Terms and privacy. `loaded` false is one frame of splash; an older
    // accepted version than [TermsController.currentVersion] is the same as
    // none, so changed wording is read before the app opens again.
    if (!terms.loaded) {
      return MaterialApp(
        theme: tc.theme,
        locale: lc.locale,
        supportedLocales: LocaleController.supported,
        localizationsDelegates: _localeDelegates,
        home: const BrandedSplashScreen(),
      );
    }
    if (!terms.accepted) {
      return MaterialApp(
        title: 'Meshmore SNS',
        theme: tc.theme,
        locale: lc.locale,
        supportedLocales: LocaleController.supported,
        localizationsDelegates: _localeDelegates,
        home: const TermsScreen(),
      );
    }
    return MaterialApp.router(
      title: 'Meshmore SNS',
      theme: tc.theme,
      locale: lc.locale,
      supportedLocales: LocaleController.supported,
      localizationsDelegates: _localeDelegates,
      routerConfig: appRouter,
      builder: (BuildContext context, Widget? child) {
        // User font-size scale (R14) layered on the OS text scale (R13 —
        // honour the platform setting). MmTextScaler keeps the platform curve
        // instead of re-linearising it, and caps the product at the largest
        // scale the accessibility floor test builds.
        final MediaQueryData mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: MmTextScaler(os: mq.textScaler, user: tc.fontScale),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}

/// The locale a notification is written in: the app's own choice when the
/// user picked one, otherwise the one the device would resolve to. Only the
/// two shipped bundles exist, so anything else falls back to English rather
/// than throwing inside a notification handler.
Locale _notificationLocale(Locale? chosen) {
  final Locale effective =
      chosen ?? WidgetsBinding.instance.platformDispatcher.locale;
  return effective.languageCode == 'ja'
      ? const Locale('ja')
      : const Locale('en');
}

/// A peer's display name for a DM notification title, from the full key or
/// the 12-hex prefix the legacy frame carries.
String? _peerName(MeshcoreController controller, String key) {
  if (key.isEmpty) return null;
  for (final DiscoveredNode n in controller.nodes) {
    if (n.pubKeyHex.startsWith(key)) return n.name;
  }
  return null;
}

/// A channel slot's name for a notification title. The controller names only
/// the active slot; another slot shows its number until it is selected.
String _channelName(MeshcoreController controller, int slot) =>
    slot == controller.activeChannel
        ? controller.activeChannelName
        : 'CH $slot';
