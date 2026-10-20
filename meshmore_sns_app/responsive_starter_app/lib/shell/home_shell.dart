// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../app_state_model.dart';
import '../bot/bot_bridge.dart';
import '../bot/bot_controller.dart';
import '../cue/cue_bridge.dart';
import '../tts/tts_controller.dart';
import '../cue/cue_service.dart';
import '../gen/app_localizations.dart';
import '../meshcore/meshcore_connection.dart';
import '../meshcore/meshcore_controller.dart';
import '../screens/chat_screen.dart';
import 'boot_overlay.dart';
import '../screens/dashboards/dashboard_host.dart';
import '../screens/docs_hub_screen.dart';
import '../screens/grid_screen.dart';
import '../screens/map_screen.dart';
import '../screens/nodes_screen.dart';
import '../theme/mm_skin.dart';
import '../theme/theme_controller.dart';
import '../ui/mm_components.dart';
import '../ui/mm_scaffold.dart';

/// The primary views (R8 dashboard is the home / first page; the
/// hyperlocal grid follows Nodes — issue #4; R53 adds the Docs tab,
/// sitting after Settings; R61 adds the Map tab right after the grid).
enum MmView { dashboard, chat, nodes, grid, map, settings, docs, about }

extension on MmView {
  /// Localised tab label. Pass `AppLocalizations.of(context)` from the
  /// caller; we don't reach for a context here so the call sites
  /// stay explicit about what they're translating.
  String title(AppLocalizations l) => switch (this) {
        MmView.dashboard => l.tabDashboard,
        MmView.chat => l.tabChat,
        MmView.nodes => l.tabNodes,
        MmView.grid => l.gridTitle,
        MmView.map => l.tabMap,
        MmView.docs => l.tabDocs,
        MmView.settings => l.tabSettings,
        MmView.about => l.tabAbout,
      };
  IconData get icon => switch (this) {
        MmView.dashboard => Icons.dashboard_outlined,
        MmView.chat => Icons.chat_bubble_outline,
        MmView.nodes => Icons.hub_outlined,
        MmView.grid => Icons.radar,
        MmView.map => Icons.map_outlined,
        MmView.docs => Icons.menu_book_outlined,
        MmView.settings => Icons.settings_outlined,
        MmView.about => Icons.info_outline,
      };
}

/// Primary navigation shell (R11, R64): horizontal swipe between the
/// primary views. There is no menu, sheet or drawer that switches
/// views; the strip under the app bar ([_ViewStrip]) only shows where
/// you are and is the tappable, labelled, 48dp-minimum path for anyone
/// who cannot swipe (screen readers, switch access, a locked map).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell>
    with WidgetsBindingObserver {
  final PageController _pc = PageController();
  int _index = 0;
  CueBridge? _cueBridge;
  BotBridge? _botBridge;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // U6: app-scoped event → cue dispatch (R12/R13). Reads providers
    // once at start; both are above us in the tree.
    _cueBridge = CueBridge(
      context.read<MeshcoreController>(),
      context.read<CueService>(),
      // R58 — inbound DM speech, per-peer tri-state. App-scoped so a
      // peer set to `always` is heard wherever the user is.
      context.read<TtsController>(),
    );
    // R59 — the bot answers wherever it is bound, for the same reason
    // the cues fire wherever: a soak client that only replied while
    // you happened to be looking at the thread would be useless.
    _botBridge = BotBridge(
      context.read<MeshcoreController>(),
      context.read<BotController>(),
    );
    // Owns splash teardown now (replaces the old demo home).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FlutterNativeSplash.remove();
      // App-loading cue — the shell is mounted, the splash is gone.
      context.read<CueService>().play(CueKind.boot);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cueBridge?.dispose();
    _botBridge?.dispose();
    _pc.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // R17: on return to foreground, re-ensure the link + drain the
    // radio's queue (messages buffered while backgrounded).
    if (state == AppLifecycleState.resumed) {
      context.read<MeshcoreController>().onAppResumed();
    }
  }

  void _goTo(int i, {required bool reduceMotion}) {
    if (reduceMotion) {
      _pc.jumpToPage(i);
    } else {
      _pc.animateToPage(i,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut);
    }
  }

  /// R67 — an edge swipe on a surface that locks the PageView: one view
  /// back (-1) or forward (+1), clamped to the ends.
  void _edgeSwipe(int delta) {
    final int to = (_index + delta).clamp(0, MmView.values.length - 1);
    if (to != _index) {
      _goTo(to,
          reduceMotion: context.read<ThemeController>().reduceMotion);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MmView current = MmView.values[_index];
    // Root back handling (R11): from a non-Dashboard tab, Back returns
    // to the Dashboard instead of trying to pop the root route (which
    // is what crashed on Android). On the Dashboard, Back is allowed
    // through so the OS gracefully backgrounds the app.
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) {
          _goTo(0,
              reduceMotion:
                  context.read<ThemeController>().reduceMotion);
        }
      },
      child: BootOverlay(child: Scaffold(
      appBar: AppBar(
        title: Text(current.title(l)),
        actions: const <Widget>[RadioLinkIndicator()],
        bottom: _ViewStrip(
          index: _index,
          onSelect: (int i) => _goTo(i,
              reduceMotion: context.read<ThemeController>().reduceMotion),
        ),
      ),
      // A grid view that pans (street map, globe, …) owns horizontal
      // drags, so the shell stops swiping while it shows; Back, the
      // view strip and Back still leave the tab. The Map tab is a
      // pan/zoom map all the time, so it is locked unconditionally;
      // its edge bands (R67, MmEdgeSwipe) change view instead.
      body: ValueListenableBuilder<bool>(
        valueListenable: GridScreen.capturesHorizontalDrag,
        builder: (BuildContext context, bool gridPans, Widget? _) =>
            PageView(
        controller: _pc,
        physics: (gridPans && current == MmView.grid) ||
                current == MmView.map
            ? const NeverScrollableScrollPhysics()
            : null,
        onPageChanged: (int i) {
          // Leaving a view with a focused text field (e.g. Chat) — drop
          // the keyboard so it doesn't linger and shrink the next view.
          FocusManager.instance.primaryFocus?.unfocus();
          // Swipe/nav cue — direction tells navNext (→) from navPrev (←).
          if (i != _index) {
            context
                .read<CueService>()
                .play(i > _index ? CueKind.navNext : CueKind.navPrev);
          }
          setState(() => _index = i);
        },
        children: <Widget>[
          const DashboardHost(),
          const ChatScreen(),
          const NodesScreen(),
          const GridScreen(),
          MapScreen(onEdgeSwipe: _edgeSwipe),
          const _SettingsView(),
          const DocsHubScreen(),
          const _AboutView(),
        ],
      ),
      ),
      ),
      ),
    );
  }
}


/// R64 — the non-gesture way to reach any view. It replaces the
/// quick-nav sheet and the old 6 px dots (which were a 4 px-tall tap
/// target with no semantics, so the sheet was the only accessible path).
///
/// One icon per [MmView], each a 48x48 button with the view's title as
/// its semantic label and tooltip and `selected` on the current one. It
/// scrolls sideways if the screen is narrower than 8 x 48dp and scrolls
/// the current view into sight, so it never clips on a small phone.
class _ViewStrip extends StatefulWidget implements PreferredSizeWidget {
  const _ViewStrip({required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  static const double cell = 48;

  @override
  Size get preferredSize => const Size.fromHeight(cell);

  @override
  State<_ViewStrip> createState() => _ViewStripState();
}

class _ViewStripState extends State<_ViewStrip> {
  final List<GlobalKey> _keys =
      List<GlobalKey>.generate(MmView.values.length, (_) => GlobalKey());

  @override
  void didUpdateWidget(_ViewStrip old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final BuildContext? c = _keys[widget.index].currentContext;
        if (c != null && c.mounted) {
          Scrollable.ensureVisible(c,
              duration: const Duration(milliseconds: 150));
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final AppLocalizations l = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) =>
          SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: box.maxWidth),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              for (final MmView v in MmView.values)
                Semantics(
                  key: _keys[v.index],
                  button: true,
                  selected: v.index == widget.index,
                  label: v.title(l),
                  excludeSemantics: true,
                  onTap: () => widget.onSelect(v.index),
                  child: Tooltip(
                    message: v.title(l),
                    excludeFromSemantics: true,
                    child: InkWell(
                      onTap: () => widget.onSelect(v.index),
                      child: SizedBox(
                        width: _ViewStrip.cell,
                        height: _ViewStrip.cell,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Icon(v.icon,
                                size: 20,
                                color: v.index == widget.index
                                    ? cs.primary
                                    : cs.onSurface.withValues(alpha: .6)),
                            const SizedBox(height: 4),
                            Container(
                              width: 18,
                              height: 2,
                              color: v.index == widget.index
                                  ? cs.primary
                                  : Colors.transparent,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsView extends StatelessWidget {
  const _SettingsView();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;
    final bool cardRows =
        skin.shape.corner != MmCorner.sharp || skin.ornament.any;
    final List<(IconData, String, String, String)> items =
        <(IconData, String, String, String)>[
      (Icons.router_outlined, l.settingsHubDevice, l.settingsHubDeviceSub,
          '/settings/device'),
      (Icons.tune, l.settingsHubApp, l.settingsHubAppSub, '/settings/app'),
      (Icons.palette_outlined, l.settingsHubProfile, l.settingsHubProfileSub,
          '/settings/profile'),
      (Icons.tag, l.settingsHubChannels, l.settingsHubChannelsSub,
          '/settings/channels'),
      (Icons.bluetooth_searching, l.settingsHubDiagnostics,
          l.settingsHubDiagnosticsSub, '/settings/diagnostics'),
      (Icons.handyman_outlined, l.settingsHubTools, l.settingsHubToolsSub,
          '/settings/tools'),
      (Icons.map_outlined, l.settingsHubMaps, l.settingsHubMapsSub,
          '/settings/maps'),
    ];
    return MmScaffold(
      child: ListView.separated(
        padding: cardRows
            ? const EdgeInsets.fromLTRB(12, 8, 12, 12)
            : EdgeInsets.zero,
        itemCount: items.length,
        separatorBuilder: (_, __) => SizedBox(height: cardRows ? 8 : 0),
        itemBuilder: (BuildContext context, int i) {
          final (IconData, String, String, String) it = items[i];
          return MmListRow(
            leading: Icon(it.$1, color: skin.color.accent),
            title: Text(it.$2),
            subtitle: Text(it.$3,
                style:
                    TextStyle(color: skin.color.fgMuted, fontSize: 12)),
            trailing: Icon(Icons.chevron_right, color: skin.color.fgMuted),
            onTap: () => context.push(it.$4),
          );
        },
      ),
    );
  }
}

class _AboutView extends StatelessWidget {
  const _AboutView();

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final AppState app = context.watch<AppState>();
    final AppLocalizations l = AppLocalizations.of(context);
    return MmScaffold(
      // Centered when it fits; scrolls when the viewport is short (small
      // screens, or a keyboard left open while swiping over from chat —
      // otherwise the fixed-height Column overflows into warning stripes).
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints:
                  BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('MESHMORE SNS',
                style: TextStyle(
                    fontSize: 22, letterSpacing: 4, color: cs.onSurface)),
            const SizedBox(height: 4),
            // The EN + JP subtitles are intentionally rendered as a
            // *pair* regardless of the active locale — the brand name
            // is bilingual.
            Text(l.aboutSubtitleEn,
                style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurface.withValues(alpha: .8))),
            const SizedBox(height: 2),
            Text(l.aboutSubtitleJa,
                style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurface.withValues(alpha: .65))),
            const SizedBox(height: 14),
            Text(l.aboutVersion(app.getAppVersion()),
                style:
                    TextStyle(color: cs.onSurface.withValues(alpha: .6))),
            const SizedBox(height: 16),
            Text(
              '${l.aboutDescription}\n'
              '${l.aboutCopyright}\n'
              '${l.aboutLicense}',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurface.withValues(alpha: .65)),
            ),
            const SizedBox(height: 18),
            Text(l.aboutMadeWith,
                style: TextStyle(
                    color: cs.onSurface.withValues(alpha: .55),
                    fontStyle: FontStyle.italic)),
            const SizedBox(height: 14),
            Text(l.aboutTerms,
                style: TextStyle(
                    color: cs.onSurface.withValues(alpha: .4),
                    fontSize: 11)),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: () => showLicensePage(
                context: context,
                applicationName: l.appName,
                applicationVersion: l.aboutVersion(app.getAppVersion()),
                applicationLegalese: l.aboutCopyright,
              ),
              icon: const Icon(Icons.description_outlined, size: 18),
              label: Text(l.aboutLicensesButton),
            ),
            const SizedBox(height: 10),
            Text(l.aboutAttributions,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: cs.onSurface.withValues(alpha: .45),
                    fontSize: 10.5,
                    height: 1.4)),
          ],
        ),
      ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Always-visible radio link state (every primary view). Tap → the
/// Diagnostics & connect screen.
class RadioLinkIndicator extends StatelessWidget {
  const RadioLinkIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final MeshcoreController mc = context.watch<MeshcoreController>();
    final ColorScheme cs = Theme.of(context).colorScheme;

    final ({String label, Color color, IconData icon}) v =
        switch (mc.state) {
      MeshcoreConnectionState.ready => (
          label: 'LINKED',
          color: cs.tertiary,
          icon: Icons.bluetooth_connected,
        ),
      MeshcoreConnectionState.handshaking => (
          label: 'SYNC',
          color: cs.secondary,
          icon: Icons.bluetooth_searching,
        ),
      MeshcoreConnectionState.reconnecting => (
          label: 'RETRY',
          color: cs.secondary,
          icon: Icons.bluetooth_searching,
        ),
      MeshcoreConnectionState.failed => (
          label: 'FAIL',
          color: cs.error,
          icon: Icons.bluetooth_disabled,
        ),
      MeshcoreConnectionState.disconnected => (
          label: mc.isConnecting ? 'SCAN' : 'OFFLINE',
          color: cs.onSurfaceVariant,
          icon: Icons.bluetooth_disabled,
        ),
    };

    return Semantics(
      button: true,
      label: 'Radio ${v.label}',
      child: InkWell(
        onTap: () => context.push('/settings/diagnostics'),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 9,
                height: 9,
                decoration:
                    BoxDecoration(color: v.color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Icon(v.icon, size: 16, color: v.color),
              const SizedBox(width: 4),
              Text(
                v.label,
                style: TextStyle(
                  color: v.color,
                  fontSize: 11,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
