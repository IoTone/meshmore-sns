// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:go_router/go_router.dart';

import 'screens/app_settings_screen.dart';
import 'screens/about_screen.dart';
import 'screens/docs_hub_screen.dart';
import 'screens/battery_screen.dart';
import 'screens/blocked_keys_screen.dart';
import 'screens/channels_screen.dart';
import 'docs/doc_section.dart';
import 'screens/coverage_screen.dart';
import 'screens/geofences_screen.dart';
import 'screens/device_config_screen.dart';
import 'screens/networks_screen.dart';
import 'screens/doc_reader_screen.dart';
import 'screens/dm_screen.dart';
import 'screens/connect_screen.dart';
import 'screens/diagnostics_screen.dart';
import 'screens/terms_screen.dart';
import 'screens/location_settings_screen.dart';
import 'screens/chat_search_screen.dart';
import 'screens/checkin_screen.dart';
import 'screens/pair_radio_screen.dart';
import 'screens/personalization_screen.dart';
import 'screens/sos_screen.dart';
import 'screens/maps/maps_screen.dart';
import 'screens/maps/maps_self_test_screen.dart';
import 'screens/maps/new_pack_screen.dart';
import 'screens/tools/discover_screen.dart';
import 'screens/tools/ping_screen.dart';
import 'screens/tools/radio_stats_screen.dart';
import 'screens/tools/range_test_screen.dart';
import 'screens/tools/soak_screen.dart';
import 'screens/tools/tools_hub_screen.dart';
import 'screens/tools/trace_screen.dart';
import 'screens/voice_settings_screen.dart';
import 'tools/mesh_tool.dart';
import 'shell/home_shell.dart';
import 'screens/firmware_screen.dart';

/// App routes (R11). `/` hosts the swipe shell (the hyperlocal grid is
/// one of its tabs, not a route); the Settings hub pushes its
/// sub-screens.
final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  routes: <RouteBase>[
    GoRoute(path: '/', builder: (_, __) => const HomeShell()),
    GoRoute(
      path: '/settings/device',
      builder: (_, __) => const DeviceConfigScreen(),
    ),
    GoRoute(
      path: '/settings/firmware',
      builder: (_, __) => const FirmwareScreen(),
    ),
    GoRoute(
      path: '/settings/networks',
      builder: (_, __) => const NetworksScreen(),
    ),
    GoRoute(
      path: '/settings/app',
      builder: (_, __) => const AppSettingsScreen(),
    ),
    GoRoute(
      path: '/settings/profile',
      builder: (_, __) => const PersonalizationScreen(),
    ),
    GoRoute(
      path: '/settings/channels',
      builder: (_, __) => const ChannelsScreen(),
    ),
    // SOS and check-in (`meshmore-sos-spec.md`). The alarm is one tap from
    // every primary view via the shell's app-bar action; the check-in sits
    // beside it on the alarm screen because it is the non-emergency sibling.
    GoRoute(path: '/sos', builder: (_, __) => const SosScreen()),
    GoRoute(path: '/checkin', builder: (_, __) => const CheckinScreen()),
    // APP-E6 — search over stored history. A route rather than a sheet
    // because a hit opens a thread, and a sheet over the list makes that read
    // as a preview rather than a jump.
    GoRoute(
      path: '/chat/search',
      builder: (_, __) => const ChatSearchScreen(),
    ),
    GoRoute(
      path: '/dm/:pubkey',
      builder: (_, GoRouterState state) => DmScreen(
        peerPubKeyHex: state.pathParameters['pubkey']!,
      ),
    ),
    GoRoute(
      path: '/settings/diagnostics',
      builder: (_, __) => const DiagnosticsScreen(),
    ),
    // The in-app pairing flow. A route rather than a sheet so the store's
    // declaration video can show one screen going scan → connect → done.
    // The one screen that answers "connect a radio". Every affordance that
    // says "connect" goes here, so the words mean one thing: a paired radio is
    // offered a link, an unpaired one is offered a scan, and Diagnostics is a
    // quieter step below rather than the first thing a person meets.
    GoRoute(
      path: '/connect',
      builder: (_, __) => const ConnectScreen(),
    ),
    GoRoute(
      path: '/pair',
      builder: (_, __) => const PairRadioScreen(),
    ),
    // APP-F1..F3 - the keys this device blocks, and the one action that
    // matters there.
    GoRoute(
      path: '/settings/blocks',
      builder: (_, __) => const BlockedKeysScreen(),
    ),
    GoRoute(
      path: '/settings/voice',
      builder: (_, __) => const VoiceSettingsScreen(),
    ),
    GoRoute(
      path: '/settings/location',
      builder: (_, __) => const LocationSettingsScreen(),
    ),
    GoRoute(
      path: '/settings/geofences',
      builder: (_, __) => const GeofencesScreen(),
    ),
    GoRoute(
      path: '/settings/coverage',
      builder: (_, __) => const CoverageScreen(),
    ),
    // R60 — Settings → Tools (issue #7). Unknown tool names fall back
    // to the hub.
    GoRoute(
      path: '/settings/tools',
      builder: (_, __) => const ToolsHubScreen(),
    ),
    GoRoute(
      path: '/settings/tools/:tool',
      builder: (_, GoRouterState state) =>
          switch (ToolKind.values.asNameMap()[state.pathParameters['tool']]) {
        ToolKind.stats => const RadioStatsScreen(),
        ToolKind.ping => const PingScreen(),
        ToolKind.trace => const TraceScreen(),
        ToolKind.discover => const DiscoverScreen(),
        ToolKind.soak => const SoakScreen(),
        ToolKind.range => const RangeTestScreen(),
        null => const ToolsHubScreen(),
      },
    ),
    // R61 — Settings → Offline maps (issue #5).
    GoRoute(
      path: '/settings/maps',
      builder: (_, __) => const MapsScreen(),
    ),
    GoRoute(
      path: '/settings/maps/new',
      builder: (_, __) => const NewPackScreen(),
    ),
    GoRoute(
      path: '/settings/maps/selftest',
      builder: (_, __) => const MapsSelfTestScreen(),
    ),
    GoRoute(
      path: '/settings/battery',
      builder: (_, __) => const BatteryScreen(),
    ),
    // R85/R86 - the information page and the docs hub are static content,
    // so they live under Settings as peers instead of owning two of the
    // six views.
    GoRoute(
      path: '/settings/about',
      builder: (_, __) => const AboutScreen(),
    ),
    // The terms page is a gate at first use; this route is the read-only
    // copy of the same text, so it can be checked at any time.
    GoRoute(
      path: '/settings/terms',
      builder: (_, __) => const TermsScreen(gate: false),
    ),
    GoRoute(
      path: '/settings/docs',
      builder: (_, __) => const DocsHubScreen(),
    ),
    // R53 — docs reader. `:section` is one of protocol / firmware / app;
    // unknown values fall back to the app self-docs.
    GoRoute(
      path: '/docs/:section',
      builder: (_, GoRouterState state) => DocReaderScreen(
        section: DocSection.values.firstWhere(
          (DocSection s) => s.name == state.pathParameters['section'],
          orElse: () => DocSection.app,
        ),
      ),
    ),
  ],
);
