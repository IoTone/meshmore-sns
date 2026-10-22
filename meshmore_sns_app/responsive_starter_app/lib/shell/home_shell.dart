// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

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
import '../screens/grid_screen.dart';
import '../screens/map_screen.dart';
import '../screens/nodes_screen.dart';
import '../theme/mm_skin.dart';
import '../ui/mm_components.dart';
import '../ui/mm_scaffold.dart';
import '../ui/mm_shape.dart';

/// The primary views (R8 dashboard is the home / first page; the
/// hyperlocal grid follows Nodes — issue #4; R53 adds the Docs tab,
/// sitting after Settings; R61 adds the Map tab right after the grid).
/// R85 - six views, the ones a person switches between. Docs and the
/// information page were top-level views; they are static content, so they
/// are rows in the Settings hub instead (R86: peers, Docs then Information).
enum MmView { dashboard, chat, nodes, grid, map, settings }

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
        MmView.settings => l.tabSettings,
      };
  IconData get icon => switch (this) {
        MmView.dashboard => Icons.dashboard_outlined,
        MmView.chat => Icons.chat_bubble_outline,
        MmView.nodes => Icons.hub_outlined,
        MmView.grid => Icons.radar,
        MmView.map => Icons.map_outlined,
        MmView.settings => Icons.settings_outlined,
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

  /// R95 — one view change, one cue. A strip tap used to call
  /// `animateToPage`, so Dashboard -> Settings scrolled through five pages and
  /// `onPageChanged` fired a nav cue on each one: five builds, five vibrations.
  /// The jump is instant and the cue is played once here, at the tap.
  void _select(int i) {
    if (i == _index) return;
    final int from = _index;
    _pc.jumpToPage(i);
    setState(() => _index = i);
    context
        .read<CueService>()
        .play(i > from ? CueKind.navNext : CueKind.navPrev);
  }

  /// R67 — an edge swipe on the map: one view back (-1) or forward (+1),
  /// clamped to the ends. R95 keeps it for every skin: the map owns horizontal
  /// drags, so the band is its only gesture exit.
  void _edgeSwipe(int delta) {
    _select((_index + delta).clamp(0, MmView.values.length - 1));
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
          _select(0);
        }
      },
      child: BootOverlay(child: Scaffold(
      appBar: AppBar(
        title: Text(current.title(l)),
        actions: const <Widget>[RadioLinkIndicator()],
        bottom: _ViewStrip(
          index: _index,
          onSelect: _select,
        ),
      ),
      // R95 — the body never scrolls by touch, in any skin. Swiping
      // between views fought every panning surface in the app (map, globe,
      // street map, radar) and each gesture had to be special-cased. The strip
      // is the switcher: tap snaps, a vertical drag on the strip steps one
      // view. The map keeps its edge bands (R67) because it is a pan surface.
      body: PageView(
        controller: _pc,
        physics: const NeverScrollableScrollPhysics(),
        onPageChanged: (int i) {
          // Leaving a view with a focused text field (e.g. Chat) — drop
          // the keyboard so it doesn't linger and shrink the next view.
          FocusManager.instance.primaryFocus?.unfocus();
          setState(() => _index = i);
        },
        children: <Widget>[
          const DashboardHost(),
          const ChatScreen(),
          const NodesScreen(),
          const GridScreen(),
          MapScreen(onEdgeSwipe: _edgeSwipe),
          const _SettingsView(),
        ],
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
/// One icon per [MmView], each a button at least 48x48 with the view's title as
/// its semantic label and tooltip and `selected` on the current one. It
/// fills the full width in equal cells, and scrolls sideways (keeping the
/// current view in sight) only if the screen is narrower than 6 x 48dp.
class _ViewStrip extends StatefulWidget implements PreferredSizeWidget {
  const _ViewStrip({required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  /// Minimum cell width; the fill branch shares the width equally.
  static const double cell = 48;

  /// Cell height (R95: 48 -> 56, so the icon and its rule have room).
  static const double height = 56;

  @override
  Size get preferredSize => const Size.fromHeight(height);

  @override
  State<_ViewStrip> createState() => _ViewStripState();
}

class _ViewStripState extends State<_ViewStrip> {
  final List<GlobalKey> _keys =
      List<GlobalKey>.generate(MmView.values.length, (_) => GlobalKey());

  /// R95 — a vertical drag on the strip steps one view, the same result as
  /// tapping the next or previous cell. A drag is deliberate, so it needs
  /// either a visible travel or a real fling to fire.
  double _dragDy = 0;

  void _onDragStart(DragStartDetails _) => _dragDy = 0;
  void _onDragUpdate(DragUpdateDetails d) => _dragDy += d.delta.dy;

  void _onDragEnd(DragEndDetails d) {
    final double v = d.primaryVelocity ?? 0;
    final double dy = _dragDy;
    _dragDy = 0;
    final bool? up = (v < -220 || dy < -28)
        ? true
        : (v > 220 || dy > 28)
            ? false
            : null;
    if (up == null) return;
    final int to =
        (widget.index + (up ? 1 : -1)).clamp(0, MmView.values.length - 1);
    if (to != widget.index) widget.onSelect(to);
  }

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

  /// One view button. [width] null means "fill the Expanded slot the caller
  /// gave me"; a number pins it (the scrolling fallback).
  Widget _cell(MmView v, AppLocalizations l, ColorScheme cs, {double? width}) {
    return Semantics(
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
            width: width,
            height: _ViewStrip.height,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(v.icon,
                    size: 22,
                    color: v.index == widget.index
                        ? cs.primary
                        : cs.onSurface.withValues(alpha: .55)),
                const SizedBox(height: 6),
                Container(
                  width: 22,
                  height: 3,
                  color: v.index == widget.index
                      ? cs.primary
                      : Colors.transparent,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final AppLocalizations l = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        // Wide enough for every cell at its minimum: the cells share the
        // whole width equally, so no dead space at either edge (an
        // Expanded needs a bounded main axis, hence no scroll view here).
        final Widget strip =
            box.maxWidth >= _ViewStrip.cell * MmView.values.length
                ? Row(
                    children: <Widget>[
                      for (final MmView v in MmView.values)
                        Expanded(child: _cell(v, l, cs)),
                    ],
                  )
                // Narrower than 6 x 48dp: fixed cells that scroll sideways.
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: <Widget>[
                        for (final MmView v in MmView.values)
                          _cell(v, l, cs, width: _ViewStrip.cell),
                      ],
                    ),
                  );
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: _onDragStart,
          onVerticalDragUpdate: _onDragUpdate,
          onVerticalDragEnd: _onDragEnd,
          child: strip,
        );
      },
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
    // A group label is a row with a null icon; its text sits in the
    // subtitle slot. The label travels with its group rather than being
    // derived from the row index: R92 shipped a switch on `i` that only
    // matched three of the four separators, so APP, CONNECTION and ABOUT
    // all rendered as "ABOUT" on the device (found on the phone 2026-10-21).
    final List<(IconData?, String?, String, String)> items =
        <(IconData?, String?, String, String)>[
      // R92 — grouped by what the row is for, not one flat list of nine.
      (null, null, l.settingsGroupRadio, ''),
      (Icons.router_outlined, l.settingsHubDevice, l.settingsHubDeviceSub,
          '/settings/device'),
      (Icons.tag, l.settingsHubChannels, l.settingsHubChannelsSub,
          '/settings/channels'),
      (null, null, l.settingsGroupApp, ''),
      (Icons.tune, l.settingsHubApp, l.settingsHubAppSub, '/settings/app'),
      (Icons.palette_outlined, l.settingsHubProfile, l.settingsHubProfileSub,
          '/settings/profile'),
      (Icons.map_outlined, l.settingsHubMaps, l.settingsHubMapsSub,
          '/settings/maps'),
      (null, null, l.settingsGroupConnect, ''),
      (Icons.bluetooth_searching, l.settingsHubDiagnostics,
          l.settingsHubDiagnosticsSub, '/settings/diagnostics'),
      (Icons.handyman_outlined, l.settingsHubTools, l.settingsHubToolsSub,
          '/settings/tools'),
      (null, null, l.settingsGroupAbout, ''),
      (Icons.menu_book_outlined, l.tabDocs, l.settingsHubDocsSub,
          '/settings/docs'),
      (Icons.info_outline, l.settingsHubInfo, l.settingsHubInfoSub,
          '/settings/about'),
    ];
    return MmScaffold(
      child: ListView.separated(
        padding: cardRows
            ? const EdgeInsets.fromLTRB(12, 8, 12, 12)
            : EdgeInsets.zero,
        itemCount: items.length,
        separatorBuilder: (_, __) => SizedBox(height: cardRows ? 8 : 0),
        itemBuilder: (BuildContext context, int i) {
          final (IconData?, String?, String, String) it = items[i];
          if (it.$2 == null) {
            // A group label, not a row. R92 — nine flat rows with subtitles
            // gave no clue which of them configure the radio, which the app,
            // which are about the build.
            return Padding(
              padding: EdgeInsets.fromLTRB(
                  cardRows ? 8 : 16, i == 0 ? 8 : 18, 16, 6),
              child: Text(
                it.$3,
                style: TextStyle(
                    color: skin.color.fgMuted,
                    fontSize: 11,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w600),
              ),
            );
          }
          return MmListRow(
            leading: Icon(it.$1!, color: skin.color.accent),
            title: Text(it.$2!),
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


/// Always-visible radio link state (every primary view). Tap → the
/// Diagnostics & connect screen.
class RadioLinkIndicator extends StatelessWidget {
  const RadioLinkIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final MeshcoreController mc = context.watch<MeshcoreController>();
    final ColorScheme cs = Theme.of(context).colorScheme;
    final AppLocalizations l = AppLocalizations.of(context);

    final ({String label, Color color, IconData icon}) v =
        switch (mc.state) {
      MeshcoreConnectionState.ready => (
          label: l.linkChipLinked,
          // R97 — green in every skin, not `ok`, which is beige in SEELE,
          // cyan in AG-HUD and amber in Recon.
          color: context.skin.color.link,
          icon: Icons.bluetooth_connected,
        ),
      MeshcoreConnectionState.handshaking => (
          label: l.linkChipSync,
          color: cs.secondary,
          icon: Icons.bluetooth_searching,
        ),
      MeshcoreConnectionState.reconnecting => (
          label: l.linkChipRetry,
          color: cs.secondary,
          icon: Icons.bluetooth_searching,
        ),
      MeshcoreConnectionState.failed => (
          label: l.linkChipFail,
          color: cs.error,
          icon: Icons.bluetooth_disabled,
        ),
      MeshcoreConnectionState.disconnected => (
          label: mc.isConnecting ? l.linkChipScan : l.linkChipOffline,
          color: cs.onSurfaceVariant,
          icon: Icons.bluetooth_disabled,
        ),
    };

    return Semantics(
      button: true,
      label: l.linkChipSemantics(v.label),
      child: InkWell(
        onTap: () => context.push('/settings/diagnostics'),
        borderRadius: mmRadius(context, 20),
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
