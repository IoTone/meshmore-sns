// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:go_router/go_router.dart';

import 'screens/app_settings_screen.dart';
import 'screens/battery_screen.dart';
import 'screens/channels_screen.dart';
import 'docs/doc_section.dart';
import 'screens/device_config_screen.dart';
import 'screens/doc_reader_screen.dart';
import 'screens/dm_screen.dart';
import 'screens/diagnostics_screen.dart';
import 'screens/location_settings_screen.dart';
import 'screens/personalization_screen.dart';
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
    GoRoute(
      path: '/settings/voice',
      builder: (_, __) => const VoiceSettingsScreen(),
    ),
    GoRoute(
      path: '/settings/location',
      builder: (_, __) => const LocationSettingsScreen(),
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
