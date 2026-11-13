// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../bot/bot_bridge.dart';
import '../bot/bot_controller.dart';
import '../cue/cue_bridge.dart';
import '../tts/tts_controller.dart';
import '../cue/cue_service.dart';
import '../gen/app_localizations.dart';
import '../field/position_history.dart';
import '../meshcore/meshcore_controller.dart';
import '../screens/chat_screen.dart';
import '../notifications/notification_focus.dart';
import 'shell_view_request.dart';
import 'boot_overlay.dart';
import 'horizontal_drag_claim.dart';
import '../screens/dashboards/dashboard_host.dart';
import '../chat/channel_read_store.dart';
import '../chat/unread_counts.dart';
import '../places/place_bridge.dart';
import '../places/place_store.dart';
import '../screens/grid_screen.dart';
import '../sos/sos_controller.dart';
import '../ui/demo_chip.dart';
import '../screens/map_screen.dart';
import '../screens/nodes_screen.dart';
import '../meshcore/block_filter.dart';
import '../meshcore/block_store.dart';
import '../theme/mm_skin.dart';
import '../ui/mm_components.dart';
import '../ui/mm_scaffold.dart';
import '../ui/mm_shape.dart';
import 'package:meshcore/meshcore.dart';

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
/// views; the strip under the app bar ([_ViewStrip]) shows where you are
/// and is the tappable, labelled, 48dp-minimum path for anyone who cannot
/// swipe (screen readers, switch access, a locked map).
///
/// R109 — the swipe is the shell's, but a surface that needs the same drag
/// takes it: the Map tab and the grid in pan mode hold
/// [shellDragClaim], and the body stops paging while they do.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  final PageController _pc = PageController();
  int _index = 0;
  CueBridge? _cueBridge;
  BotBridge? _botBridge;
  PlaceBridge? _placeBridge;

  /// D8.20 — who is on screen, for the notification decision.
  ///
  /// The shell owns this rather than the chat page: the page is kept alive
  /// once visited, so a record it wrote would outlive the user leaving the
  /// tab and silence that channel for the rest of the process (measured on
  /// 2026-11-05: one Chat visit stopped every channel notification while the
  /// app sat on the Dashboard).
  NotificationFocus? _notificationFocus;
  MeshcoreController? _focusOwner;

  /// "Show me Chat on this slot", asked from outside the shell (a notification
  /// tap from the app root). The last sequence number acted on, so a rebuild
  /// cannot replay a request.
  ShellViewRequest? _viewRequest;
  int _viewRequestSeq = 0;

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
    // Places arrive on the same two streams as everything else and are stored
    // wherever the user is, so the map has them when it is next opened.
    _placeBridge = PlaceBridge(
      context.read<MeshcoreController>(),
      context.read<PlaceStore>(),
    );
    _notificationFocus = context.read<NotificationFocus?>();
    _focusOwner = context.read<MeshcoreController>();
    _viewRequest = context.read<ShellViewRequest?>();
    _viewRequest?.addListener(_onViewRequest);
    // The active slot can change without a page change (the chat header, the
    // channel picker, a radio that renumbers its channels), so follow it.
    _focusOwner?.addListener(_publishNotificationFocus);
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
    _focusOwner?.removeListener(_publishNotificationFocus);
    _viewRequest?.removeListener(_onViewRequest);
    _notificationFocus?.clearThread();
    _cueBridge?.dispose();
    _botBridge?.dispose();
    _placeBridge?.dispose();
    _pc.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final MeshcoreController mc = context.read<MeshcoreController>();
    final bool visible = state == AppLifecycleState.resumed;
    // R17: on return to foreground, re-ensure the link + drain the radio's
    // queue (messages buffered while backgrounded). On the way out, every
    // timer that spends airtime or wakes the CPU is stopped, because a frame a
    // minute for a number nobody can see is a real cost on a shared band.
    mc.setVisible(visible);
    context.read<PositionRecorder?>()?.setVisible(visible);
    if (visible) mc.onAppResumed();
  }

  /// R95 — one view change, one cue. A strip tap used to call
  /// `animateToPage`, so Dashboard -> Settings scrolled through five pages and
  /// `onPageChanged` fired a nav cue on each one: five builds, five vibrations.
  /// The jump is instant and the cue is played once here, at the tap.
  static const MethodChannel _lifecycle =
      MethodChannel('meshmore/app_lifecycle');

  /// Back on the Dashboard: keep the engine (and the radio) alive, in the background.
  /// Best effort: a test or a platform without the channel simply ignores the back.
  Future<void> _moveToBackground() async {
    try {
      await _lifecycle.invokeMethod<bool>('moveTaskToBack');
    } on MissingPluginException {
      // No Android side here.
    } on PlatformException {
      // Same: nothing to background.
    }
  }

  void _select(int i) {
    if (i == _index) return;
    final int from = _index;
    _pc.jumpToPage(i);
    setState(() => _index = i);
    _publishNotificationFocus();
    _playNavCue(from, i);
  }

  /// Another surface asked for a view: a notification tap wants Chat on a
  /// slot, the grid's picker wants the Map tab.
  void _onViewRequest() {
    final ShellViewRequest? request = _viewRequest;
    if (request == null) return;
    if (request.seq == _viewRequestSeq) return;
    _viewRequestSeq = request.seq;
    switch (request.view) {
      case RequestedView.chat:
        _select(MmView.chat.index);
      case RequestedView.map:
        _select(MmView.map.index);
      case null:
        break;
    }
  }

  /// The channel on screen is not announced; nothing else is suppressed.
  void _publishNotificationFocus() {
    final NotificationFocus? focus = _notificationFocus;
    if (focus == null) return;
    focus.openChannel =
        _index == MmView.chat.index ? _focusOwner?.activeChannel : null;
  }

  /// One view change, one cue (R95) — whether the change came from a strip
  /// tap or from a swipe that settled, so the two paths cannot play it twice.
  void _playNavCue(int from, int to) {
    context
        .read<CueService>()
        .play(to > from ? CueKind.navNext : CueKind.navPrev);
  }

  void _onPageChanged(int i) {
    // Leaving a view with a focused text field (e.g. Chat) — drop the
    // keyboard so it doesn't linger and shrink the next view.
    FocusManager.instance.primaryFocus?.unfocus();
    // A strip tap already moved [_index] and played its cue.
    if (i == _index) return;
    final int from = _index;
    setState(() => _index = i);
    _publishNotificationFocus();
    _playNavCue(from, i);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    // Root back handling (R11): from a non-Dashboard tab, Back returns
    // to the Dashboard instead of trying to pop the root route (which
    // is what crashed on Android). On the Dashboard, Back asks the platform
    // to move the task to the back.
    //
    // **Not "allowed through": on Android that finishes the Activity and
    // destroys the Flutter engine, and the engine is where the radio link and
    // the keep-alive service live** (observed on the device, 2026-11-01:
    // pressing Back on the Dashboard left the process running but dropped the
    // link). The foreground notification already says the app is running, so
    // leaving the task in the background is the honest answer.
    // Channel unread for the strip's chat cell. The count is computed inside a
    // selector so the shell repaints only when the number changes, not on
    // every controller notification (battery samples, telemetry, RSSI).
    final ChannelReadStore? reads = context.watch<ChannelReadStore?>();
    final BlockStore? blocks = context.watch<BlockStore?>();
    final BlockFilter filter = BlockFilter(blocks ?? BlockStore());
    final int chatUnread = context.select<MeshcoreController, int>(
      (MeshcoreController mc) => UnreadCounts.total(
        channels: mc.channels.map((MapEntry<int, String> e) => e.key),
        history: mc.messagesFor,
        reads: reads,
        filter: filter,
        // The thread on screen is being read, so its channel contributes
        // nothing to the cell. Relying on the read mark alone left the badge
        // counting a channel the reader was looking at, which is the report:
        // the number kept rising on the channel the message came in on.
        ignore: _index == MmView.chat.index
            ? <int>{mc.activeChannel}
            : const <int>{},
      ),
    );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        if (_index != 0) {
          _select(0);
        } else {
          _moveToBackground();
        }
      },
      child: BootOverlay(
        child: Scaffold(
          appBar: AppBar(
            // One header, and it names what is on screen: the app's own name
            // on the dashboard, the view's name everywhere else. A second
            // title block used to sit under the strip saying the same thing
            // 56 dp lower; two headers where one will do is space the user
            // never gets back.
            title: Text(_index == MmView.dashboard.index
                ? l.appName
                : MmView.values[_index].title(l)),
            // SOS is one tap from every primary view, in every skin: an alarm that
            // needs three taps and a remembered menu is not an alarm. The control
            // only opens the alarm screen; raising still takes the three-second
            // hold, so a stray tap costs nothing (`meshmore-sos-spec.md` §8).
            actions: <Widget>[
              // SOS-4: an alarm that is repeating is visible from every
              // view, not only from the screen the user left. The tint and the
              // semantics label are the two signals that survive a skin
              // change and a screen reader; the ongoing notification carries
              // the same fact outside the app.
              Builder(builder: (BuildContext context) {
                final bool alarm = context.watch<SosController?>()?.isRunning ?? false;
                final MmSkin skin = context.skin;
                return IconButton(
                  key: const ValueKey<String>('sos-entry'),
                  tooltip: alarm ? l.sosActive : l.sosEntryTooltip,
                  icon: Icon(Icons.sos,
                      color: alarm ? skin.color.alert : null),
                  onPressed: () => context.push('/sos'),
                );
              }),
              const DemoChip(),
              const RadioLinkIndicator(),
            ],
            bottom: _ViewStrip(
              index: _index,
              onSelect: _select,
              chatUnread: chatUnread,
            ),
          ),
          // R109 — a horizontal drag pages the body, except while the current
          // view needs the same drag: the Map (its pan/zoom canvas owns the
          // middle, and the R67 edge bands are its gesture exit) and the grid
          // in pan mode, which holds the claim itself. R95's half of this
          // stays: a strip tap jumps in one frame with one cue, and a vertical
          // drag on the strip steps one view.
          body: ValueListenableBuilder<bool>(
            valueListenable: shellDragClaim.claimed,
            builder: (BuildContext _, bool gridOwnsDrag, Widget? __) {
              // The Map is the current view or it is not: a page is built as a
              // neighbour before it is shown, so a mount-time hold would lock
              // the shell while another view was on screen.
              final bool dragOwned = gridOwnsDrag || _index == MmView.map.index;
              return PageView(
                controller: _pc,
                physics:
                    dragOwned ? const NeverScrollableScrollPhysics() : null,
                onPageChanged: _onPageChanged,
                children: <Widget>[
                  const DashboardHost(),
                  ChatScreen(isCurrent: _index == MmView.chat.index),
                  const NodesScreen(),
                  GridScreen(isCurrent: _index == MmView.grid.index),
                  const MapScreen(),
                  const _SettingsView(),
                ],
              );
            },
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
  const _ViewStrip({
    required this.index,
    required this.onSelect,
    this.chatUnread = 0,
  });

  final int index;
  final ValueChanged<int> onSelect;

  /// Unread channel messages, shown on the chat cell.
  final int chatUnread;

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
    final int unread = v == MmView.chat ? widget.chatUnread : 0;
    return Semantics(
      key: _keys[v.index],
      button: true,
      selected: v.index == widget.index,
      // The count is part of the label, not only a number drawn on the icon:
      // a badge a screen reader cannot read is a badge that does not exist.
      label: unread > 0 ? '${v.title(l)}, ${l.chatUnread(unread)}' : v.title(l),
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
                if (unread > 0)
                  _StripBadge(
                    icon: v.icon,
                    count: unread,
                    selected: v.index == widget.index,
                    cs: cs,
                  )
                else
                  Icon(v.icon,
                      size: 22,
                      // On paper ink at 55 % is 2.6:1 and the unselected views
                      // read as ghosts rather than as destinations you can tap,
                      // so paper takes the muted tier. The dark grounds keep the
                      // fade they were drawn with.
                      color: v.index == widget.index
                          ? cs.primary
                          : context.skin.color.isLight
                              ? context.skin.color.fgMuted
                              : cs.onSurface.withValues(alpha: .55)),
                const SizedBox(height: 6),
                Container(
                  width: 22,
                  height: 3,
                  color:
                      v.index == widget.index ? cs.primary : Colors.transparent,
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
    // Titles only. Ten one-line subtitles were jargon a user cannot decode
    // (`PSK`, `frame log`, `event maps`) and four facts crammed into one line
    // with interpuncts. A destination's own header says what it holds, in
    // words that screen can keep true.
    //
    // The group label travels with its group rather than being derived from
    // the row index: R92 shipped a switch on `i` that matched three of the
    // four separators, so APP, CONNECTION and ABOUT all rendered as "ABOUT"
    // on the device (found on the phone 2026-10-21).
    return MmScaffold(
      // No second header: the app bar already says "Settings", and this list
      // starts with its first group label.
      child: Column(
        children: <Widget>[
          Expanded(
            child: ListView(
              padding: cardRows
                  ? const EdgeInsets.fromLTRB(12, 8, 12, 12)
                  : EdgeInsets.zero,
              children: <Widget>[
                for (final ({
                  String label,
                  List<(IconData, String, String)> rows
                }) g in _settingsGroups(l)) ...<Widget>[
                  _GroupLabel(
                      text: g.label,
                      skin: skin,
                      first: g.label == l.settingsGroupRadio),
                  for (final (IconData icon, String title, String route) r
                      in g.rows)
                    Padding(
                      padding: EdgeInsets.only(bottom: cardRows ? 8 : 0),
                      child: MmListRow(
                        leading: Icon(r.$1, color: skin.color.accent),
                        title: Text(r.$2),
                        trailing: Icon(Icons.chevron_right,
                            color: skin.color.fgMuted),
                        onTap: () => context.push(r.$3),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The Settings hub, grouped by what a row is for rather than by module
/// (R92): what configures the radio, what configures the app, what connects
/// it, and what the build is.
List<({String label, List<(IconData, String, String)> rows})> _settingsGroups(
  AppLocalizations l,
) =>
    <({String label, List<(IconData, String, String)> rows})>[
      // RADIO is what the radio *is*: its air-interface settings and its own
      // firmware. Networks belong here rather than under APP — a network is a
      // frequency, a bandwidth, a spreading factor and a path-hash size shared
      // by a group of radios, which is the same kind of fact as a channel and
      // nothing at all like an app preference. Firmware moved here too: it was
      // under CONNECTION, which is what the *link* is doing, and flashing a
      // radio is not a property of the link.
      (
        label: l.settingsGroupRadio,
        rows: <(IconData, String, String)>[
          (Icons.router_outlined, l.settingsHubDevice, '/settings/device'),
          (Icons.tag, l.settingsHubChannels, '/settings/channels'),
          (Icons.hub_outlined, l.networksTitle, '/settings/networks'),
          (
            Icons.system_update_alt,
            l.settingsHubFirmware,
            '/settings/firmware'
          ),
        ],
      ),
      (
        label: l.settingsGroupApp,
        rows: <(IconData, String, String)>[
          (Icons.tune, l.settingsHubApp, '/settings/app'),
          (Icons.palette_outlined, l.settingsHubProfile, '/settings/profile'),
          (Icons.map_outlined, l.settingsHubMaps, '/settings/maps'),
        ],
      ),
      (
        label: l.settingsGroupConnect,
        rows: <(IconData, String, String)>[
          (
            Icons.bluetooth_searching,
            l.settingsHubDiagnostics,
            '/settings/diagnostics'
          ),
          (Icons.handyman_outlined, l.settingsHubTools, '/settings/tools'),
        ],
      ),
      (
        label: l.settingsGroupAbout,
        rows: <(IconData, String, String)>[
          (Icons.menu_book_outlined, l.tabDocs, '/settings/docs'),
          (Icons.info_outline, l.settingsHubInfo, '/settings/about'),
        ],
      ),
    ];

/// A group's name, at the same weight and tracking in every skin.
class _GroupLabel extends StatelessWidget {
  const _GroupLabel(
      {required this.text, required this.skin, this.first = false});

  final String text;
  final MmSkin skin;
  final bool first;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(first ? 0 : 16, first ? 8 : 18, 16, 6),
      child: Text(text, style: mmSectionLabelStyle(skin)),
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

    final ({String label, Color color, IconData icon}) v = switch (mc.state) {
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

    // The chip is the app bar's only route to Diagnostics, and it used to be a
    // dot, an icon and coloured text with no boundary at all: a status readout
    // that happened to be pressable. It now carries the pill's own edge in the
    // state's colour, so the shape says "control" and the colour still says
    // "which state".
    return Semantics(
      button: true,
      label: l.linkChipSemantics(v.label),
      child: InkWell(
        onTap: () => context.push('/connect'),
        borderRadius: mmRadius(context, 20),
        // `DecoratedBox`, not `Container`: the chip's own dot is the first
        // `Container` in this subtree and the colour test finds it that way.
        child: DecoratedBox(
          decoration: ShapeDecoration(
            shape: mmShapeBorder(
              MmShape(
                corner: context.skin.shape.corner == MmCorner.chamfer
                    ? MmCorner.chamfer
                    : MmCorner.rounded,
                cornerSize: 20,
                borderWidth: 1,
              ),
              side: BorderSide(color: v.color),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
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
                    fontSize: context.skin.type.sizeSm,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The chat cell's unread count, drawn over its icon.
///
/// A count rather than a dot, and the same shape the channel chip uses, so
/// the two badges read as the same fact at two scopes.
class _StripBadge extends StatelessWidget {
  const _StripBadge({
    required this.icon,
    required this.count,
    required this.selected,
    required this.cs,
  });

  final IconData icon;
  final int count;
  final bool selected;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final MmSkin skin = context.skin;
    return SizedBox(
      height: 22,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: <Widget>[
          Icon(icon,
              size: 22,
              color: selected
                  ? cs.primary
                  : context.skin.color.isLight
                      ? context.skin.color.fgMuted
                      : cs.onSurface.withValues(alpha: .55)),
          Positioned(
            right: -10,
            top: -4,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: skin.space.step(1)),
              constraints: BoxConstraints(minWidth: skin.space.step(4)),
              // The attention pair, so the count is legible over *both* icon
              // states: the selected icon is drawn in the accent, and an
              // accent badge on top of it disappeared.
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
            ),
          ),
        ],
      ),
    );
  }
}
