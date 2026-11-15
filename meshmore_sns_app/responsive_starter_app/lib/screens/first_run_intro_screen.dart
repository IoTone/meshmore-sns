// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'pair_radio_screen.dart';
import 'package:provider/provider.dart';

import '../app/demo_mode.dart';
import '../gen/app_localizations.dart';
import '../media/media_prefs.dart';
import '../meshcore/meshcore_controller.dart';
import '../perms/first_run_controller.dart';
import '../perms/permissions_service.dart';
import '../theme/mm_skin.dart';
import '../theme/mm_tokens.dart';
import '../theme/theme_controller.dart';
import '../ui/mm_components.dart';
import '../ui/mm_shape.dart';
import '../util/mm_format.dart';

/// The first run, as three decisions rather than one wall of prose.
///
/// It used to be a single page: what the app asks for, then Grant or Skip. That
/// is the one screen with no app bar to escape through, and it spent its whole
/// height explaining permissions while the two choices a new reader actually
/// makes — what the app looks like and how it reads numbers — were buried three
/// taps deep in Appearance.
///
/// Page 0 is still the permission explainer, unchanged in substance: Bluetooth
/// is requested only on Grant, notifications are not requested here at all, and
/// Skip is a real path rather than a trap. Page 1 is the theme picker, live, so
/// the choice re-skins the picker as it is made. Page 2 is the three settings
/// that change every screen and nothing else. The last page says what happens
/// next, because a flow that ends in silence is a flow that ends in confusion.
///
/// Replay (About → Replay the first-run screens) mounts this screen again with
/// the reader's current theme and units already selected. It is a review of the
/// choices, not a reset of them.
class FirstRunIntroScreen extends StatefulWidget {
  const FirstRunIntroScreen({super.key});

  /// How many pages the flow has. Read by the tests and by the indicator.
  static const int pageCount = 3;

  @override
  State<FirstRunIntroScreen> createState() => _FirstRunIntroScreenState();
}

class _FirstRunIntroScreenState extends State<FirstRunIntroScreen> {
  final PageController _pages = PageController();
  int _page = 0;
  bool _busy = false;
  String? _denialNote;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _goTo(int page) {
    setState(() => _page = page);
    _pages.animateToPage(page,
        duration: const Duration(milliseconds: 240), curve: Curves.easeOut);
  }

  /// Page 0's primary action: ask for Bluetooth, then carry on. A refusal is
  /// not the end of the flow — it is a note on this page, and Skip is still
  /// there — but it is never silently treated as granted either.
  Future<void> _grant() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _denialNote = null;
    });
    final PermissionsService perms = context.read<PermissionsService>();
    final PermissionResult r = await perms.requestBle();
    if (!mounted) return;
    setState(() => _busy = false);
    if (r == PermissionResult.granted || r == PermissionResult.notApplicable) {
      _goTo(1);
      return;
    }
    final AppLocalizations l = AppLocalizations.of(context);
    setState(() {
      _denialNote = r == PermissionResult.permanentlyDenied
          ? l.firstRunDeniedPermanent
          : l.firstRunDeniedTransient;
    });
  }

  /// The last page's radio path: the pairing flow, then done.
  ///
  /// The pairing screen is pushed on the intro's own Navigator and the flow ends
  /// when it closes. Marking done first would swap this whole MaterialApp for
  /// the shell mid-push and take the pairing route with it, which is how a
  /// button can promise one screen and deliver another.
  Future<void> _finishWithRadio() async {
    if (_busy) return;
    setState(() => _busy = true);
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (BuildContext _) => const PairRadioScreen(),
    ));
    if (!mounted) return;
    setState(() => _busy = false);
    await context.read<FirstRunController>().markDone();
  }

  /// The last page's offline path. Demo mode by name: it records the choice so
  /// the next launch does not reach for a radio, and a link that answered the
  /// auto-connect before this tap is dropped, because a demo that keeps a live
  /// link is not radio-free.
  /// Keep the radio that is already linked and leave the flow.
  ///
  /// Not [_finishWithDemo]: that one turns demo mode on, and demo mode
  /// disconnects the link — the opposite of keeping the radio the reader chose
  /// to keep.
  Future<void> _finishKeepRadio() async {
    if (_busy) return;
    setState(() => _busy = true);
    await context.read<FirstRunController>().markDone();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _finishWithDemo() async {
    if (_busy) return;
    setState(() => _busy = true);
    final DemoMode demo = context.read<DemoMode>();
    final FirstRunController fr = context.read<FirstRunController>();
    final MeshcoreController mc = context.read<MeshcoreController>();
    await demo.setEnabled(true, onEnabled: () => mc.disconnect());
    await fr.markDone();
  }

  Future<void> _openSettings() async {
    await context.read<PermissionsService>().openAppSettingsPage();
  }

  /// The radio that is already linked, if any: the name the last page shows.
  ///
  /// A replayed first run is mounted over a running app, so the reader may
  /// already have a radio answering. The last page names it instead of asking
  /// for one.
  String? get _linkedRadioName {
    final MeshcoreController mc = context.read<MeshcoreController>();
    if (!mc.isReady) return null;
    final String? n = mc.selfInfo?.name;
    return (n != null && n.isNotEmpty) ? n : mc.pairedName;
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (int i) => setState(() => _page = i),
                children: <Widget>[
                  _WelcomePage(
                    denialNote: _denialNote,
                    onOpenSettings: _openSettings,
                  ),
                  const _ThemePage(),
                  const _PrefsPage(),
                ],
              ),
            ),
            _PageDots(count: FirstRunIntroScreen.pageCount, at: _page),
            // The bar scrolls rather than clipping. The last page carries three
            // actions, and at 320 dp with 200 % text they are 140 px taller
            // than the space a PageView leaves, which clipped the last one.
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                    skin.space.sectionGap,
                    skin.space.rowGap,
                    skin.space.sectionGap,
                    skin.space.sectionGap),
                child: _Actions(
                page: _page,
                busy: _busy,
                onGrant: _grant,
                onSkip: () => _goTo(1),
                onNext: () => _goTo(_page + 1),
                onBack: () => _goTo(_page - 1),
                  onRadio: _finishWithRadio,
                  onDemo: _finishWithDemo,
                  // A replayed first run is mounted over a running app, so the
                  // radio may already be linked and answering. The last page then
                  // names it and offers to keep it instead of asking for one.
                  linkedName: _linkedRadioName,
                  onKeep: _finishKeepRadio,
                  l: l,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The action bar is one row per page, so the flow always has exactly one
/// obvious next step and never two competing primaries.
///
/// It uses the app's own action family (`MmAction`, `MmActionRow`) rather than
/// Material's buttons, which is the convention every screen follows and the two
/// ratchets enforce: one shape language, one placement, start-aligned under the
/// content it acts on.
class _Actions extends StatelessWidget {
  const _Actions({
    required this.page,
    required this.busy,
    required this.onGrant,
    required this.onSkip,
    required this.onNext,
    required this.onBack,
    required this.onRadio,
    required this.onDemo,
    required this.onKeep,
    required this.linkedName,
    required this.l,
  });

  final int page;
  final bool busy;
  final VoidCallback onGrant;
  final VoidCallback onSkip;
  final VoidCallback onNext;
  final VoidCallback onBack;
  final VoidCallback onRadio;
  final VoidCallback onDemo;

  /// The reader already has a radio: keep it and leave the flow. This is not
  /// [onDemo] — that one turns on demo mode, which *disconnects* the radio the
  /// reader just chose to keep.
  final Future<void> Function() onKeep;

  /// The radio already linked, or null when there is none.
  final String? linkedName;

  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final MmSkin skin = context.skin;
    switch (page) {
      case 0:
        return MmActionRow(
          children: <Widget>[
            MmAction(
              key: const ValueKey<String>('first-run-skip'),
              icon: Icons.arrow_forward,
              label: l.firstRunSkipShort,
              onPressed: busy ? null : onSkip,
            ),
            MmAction(
              key: const ValueKey<String>('first-run-grant'),
              primary: true,
              icon: Icons.check_circle_outline,
              label: l.firstRunGrant,
              onPressed: busy ? null : onGrant,
            ),
          ],
        );
      case 1:
        return MmActionRow(
          children: <Widget>[
            MmAction(
              key: const ValueKey<String>('first-run-back'),
              icon: Icons.arrow_back,
              label: l.firstRunBack,
              onPressed: busy ? null : onBack,
            ),
            MmAction(
              key: const ValueKey<String>('first-run-next'),
              primary: true,
              icon: Icons.arrow_forward,
              label: l.firstRunNext,
              onPressed: busy ? null : onNext,
            ),
          ],
        );
      default:
        // The radio may already be linked: a replayed first run is mounted over
        // a running app, and the auto-connect answers before the first frame. A
        // reader whose radio is linked and answering has already made this
        // choice, so the page names it and offers to keep it.
        final String? linked = linkedName;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (linked != null) ...<Widget>[
              Row(
                children: <Widget>[
                  const Icon(Icons.bluetooth_connected, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(l.firstRunRadioLinked(linked),
                        key: const ValueKey<String>('first-run-linked'),
                        style: Theme.of(context).textTheme.bodyMedium),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            MmActionRow(
              children: <Widget>[
                if (linked != null)
                  MmAction(
                    key: const ValueKey<String>('first-run-keep-radio'),
                    primary: true,
                    icon: Icons.check,
                    label: l.firstRunKeepRadio,
                    onPressed: busy ? null : () => onKeep(),
                  )
                else
                  MmAction(
                    key: const ValueKey<String>('first-run-connect'),
                    primary: true,
                    icon: Icons.bluetooth_searching,
                    label: l.firstRunConnect,
                    onPressed: busy ? null : onRadio,
                  ),
              ],
            ),
            SizedBox(height: skin.space.rowGap),
            MmActionRow(
              children: <Widget>[
                MmAction(
                  key: const ValueKey<String>('first-run-demo'),
                  icon: Icons.cloud_off,
                  label: l.firstRunSkip,
                  onPressed: busy ? null : onDemo,
                ),
                MmAction(
                  key: const ValueKey<String>('first-run-back'),
                  icon: Icons.arrow_back,
                  label: l.firstRunBack,
                  onPressed: busy ? null : onBack,
                ),
              ],
            ),
          ],
        );
    }
  }
}

/// Three dots, the current one filled. No numbers: a first run is three steps
/// long and a reader only needs to know how much is left.
class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.at});

  final int count;
  final int at;

  @override
  Widget build(BuildContext context) {
    final MmSkin skin = context.skin;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        for (int i = 0; i < count; i++)
          Container(
            width: 8,
            height: 8,
            margin: EdgeInsets.symmetric(horizontal: skin.space.labelToControl),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i == at ? skin.color.accent : skin.color.line,
            ),
          ),
      ],
    );
  }
}

/// A first-run page body that fills its page.
///
/// These pages were short columns at the top of a full-height PageView: on a tall
/// phone the permission explainer and the theme list occupied the upper half and
/// left the lower half empty, so the flow looked like a half-drawn screen. The
/// content now fills the page and centres inside it, and still scrolls when it is
/// taller than the page (320 dp at 200 % text is taller).
class _PageBody extends StatelessWidget {
  const _PageBody({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final MmSkin skin = context.skin;
    final EdgeInsets pad = EdgeInsets.symmetric(
        horizontal: skin.space.sectionGap, vertical: skin.space.emptyState);
    return LayoutBuilder(
      builder: (BuildContext c, BoxConstraints box) => SingleChildScrollView(
        key: key,
        padding: pad,
        child: ConstrainedBox(
          constraints: BoxConstraints(
              minHeight: (box.maxHeight - pad.vertical).clamp(0.0, double.infinity)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            // Centred, so the page's own weight sits in the middle of the screen
            // rather than hanging from the top edge.
            mainAxisAlignment: MainAxisAlignment.center,
            children: children,
          ),
        ),
      ),
    );
  }
}

class _WelcomePage extends StatelessWidget {
  const _WelcomePage({required this.denialNote, required this.onOpenSettings});

  final String? denialNote;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final ThemeData th = Theme.of(context);
    final ColorScheme cs = th.colorScheme;
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;
    // The page scrolls. At 320 dp with 200 % text the old single page
    // overflowed by 2120 px, and a new user with large text could not reach the
    // button that lets them in.
    return _PageBody(
      children: <Widget>[
          Text(l.firstRunHeader,
              style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: skin.type.sizeBody,
                  letterSpacing: skin.type.headingTracking)),
          SizedBox(height: skin.space.screenEdge),
          Text(l.firstRunTitle, style: th.textTheme.headlineSmall),
          SizedBox(height: skin.space.sectionGap),
          _PermBlock(
            icon: Icons.bluetooth_searching,
            title: l.firstRunBleTitle,
            body: l.firstRunBleBody,
          ),
          SizedBox(height: skin.space.rowInset),
          _PermBlock(
            icon: Icons.notifications_active_outlined,
            title: l.firstRunNotificationsTitle,
            body: l.firstRunNotificationsBody,
          ),
          SizedBox(height: skin.space.rowInset),
          _PermBlock(
            icon: Icons.cloud_off,
            title: l.firstRunOfflineTitle,
            body: l.firstRunOfflineBody,
          ),
          if (denialNote != null) ...<Widget>[
            SizedBox(height: skin.space.sectionGap),
            Container(
              padding: EdgeInsets.all(skin.space.rowInset),
              decoration: BoxDecoration(
                color: cs.errorContainer,
                borderRadius: mmRadius(context, kRadiusSm),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(Icons.info_outline, color: cs.onErrorContainer, size: 18),
                  SizedBox(width: skin.space.rowGap),
                  Expanded(
                    child: Text(denialNote!,
                        style: TextStyle(color: cs.onErrorContainer)),
                  ),
                ],
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: MmAction(
                onPressed: onOpenSettings,
                icon: Icons.settings_outlined,
                label: l.firstRunOpenSettings,
                dense: true,
              ),
            ),
          ],
        ],
    );
  }
}

/// The theme picker, live. `setPreset` rebuilds the app around this page, so the
/// choice is shown by the choice: the reader sees the theme they are choosing
/// rather than a swatch of it.
class _ThemePage extends StatelessWidget {
  const _ThemePage();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ThemeController tc = context.watch<ThemeController>();
    final MmSkin skin = context.skin;
    final ColorScheme cs = Theme.of(context).colorScheme;
    // One scroll view, header included. A fixed header above an `Expanded` list
    // is a Column that overflows the moment the header alone is taller than the
    // space — at 320 dp with 200 % text it was 70 px over, and the first row a
    // reader could not reach was the theme list itself.
    return _PageBody(
      key: const ValueKey<String>('first-run-themes'),
      children: <Widget>[
        Padding(
          padding: EdgeInsets.symmetric(horizontal: skin.space.labelToControl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(l.firstRunThemeTitle,
                  style: TextStyle(
                      color: cs.onSurface,
                      fontSize: skin.type.sizeLg,
                      fontWeight: FontWeight.w700)),
              SizedBox(height: skin.space.labelToControl),
              Text(l.firstRunThemeBody,
                  style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: skin.type.sizeBody,
                      height: 1.35)),
            ],
          ),
        ),
        SizedBox(height: skin.space.rowGap),
        for (final MmThemePreset p in MmThemePreset.values)
          Builder(builder: (BuildContext c) {
            final bool chosen = tc.preset == p;
            // The swatches are a second way to say what the row already says,
            // so they are what goes when the row is short.
            final bool roomForSwatches = MediaQuery.sizeOf(c).width >= 380;
            return ListTile(
              key: ValueKey<String>('first-run-theme-${p.name}'),
              dense: true,
              leading: Icon(
                chosen ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: chosen ? cs.primary : cs.onSurfaceVariant,
              ),
              title: Text(p.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: cs.onSurface)),
              trailing:
                  roomForSwatches ? _Swatches(tokens: kMmPresets[p]!) : null,
              onTap: () => tc.setPreset(p),
            );
          }),
      ],
    );
  }
}

/// The three settings that change every screen.
///
/// Units and the clock are on every list and every timestamp. Whether a photo
/// goes out in colour decides a third of a photo's airtime, which is worth one
/// switch before the first send. Nothing else belongs here: a first-run page is
/// a decision, not a settings screen.
class _PrefsPage extends StatelessWidget {
  const _PrefsPage();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;
    final ColorScheme cs = Theme.of(context).colorScheme;
    final FormatPrefs fmt = context.watch<FormatPrefs>();
    return _PageBody(
      children: <Widget>[
          Text(l.firstRunPrefsTitle,
              style: TextStyle(
                  color: cs.onSurface,
                  fontSize: skin.type.sizeLg,
                  fontWeight: FontWeight.w700)),
          SizedBox(height: skin.space.labelToControl),
          Text(l.firstRunPrefsBody,
              style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: skin.type.sizeBody,
                  height: 1.35)),
          SizedBox(height: skin.space.sectionGap),
          SwitchListTile(
            key: const ValueKey<String>('first-run-units'),
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.straighten),
            title: Text(l.firstRunUnits),
            subtitle: Text(
                fmt.units == DistanceUnits.imperial
                    ? l.settingsUnitsImperial
                    : l.settingsUnitsMetric,
                style: TextStyle(color: cs.onSurfaceVariant)),
            value: fmt.units == DistanceUnits.imperial,
            onChanged: (bool v) =>
                fmt.setUnits(v ? DistanceUnits.imperial : DistanceUnits.metric),
          ),
          SwitchListTile(
            key: const ValueKey<String>('first-run-clock24'),
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.schedule),
            title: Text(l.settingsClock24),
            subtitle: Text(fmt.clock24 ? l.settingsClock24On : l.settingsClock12On,
                style: TextStyle(color: cs.onSurfaceVariant)),
            value: fmt.clock24,
            onChanged: fmt.setClock24,
          ),
          _PhotoColourSwitch(l: l),
      ],
    );
  }
}

/// Colour or grey, on its own so the page stays stateless.
class _PhotoColourSwitch extends StatefulWidget {
  const _PhotoColourSwitch({required this.l});

  final AppLocalizations l;

  @override
  State<_PhotoColourSwitch> createState() => _PhotoColourSwitchState();
}

class _PhotoColourSwitchState extends State<_PhotoColourSwitch> {
  bool _color = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    MediaPrefs.colorPhotos().then((bool v) {
      if (!mounted) return;
      setState(() {
        _color = v;
        _loaded = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return SwitchListTile(
      key: const ValueKey<String>('first-run-photo-colour'),
      contentPadding: EdgeInsets.zero,
      secondary: const Icon(Icons.photo_camera_outlined),
      title: Text(widget.l.settingsPhotoColorTitle),
      subtitle: Text(widget.l.settingsPhotoColorSub,
          style: TextStyle(color: cs.onSurfaceVariant)),
      // Off until the preference has been read, so the thumb does not jump.
      value: _color,
      onChanged: !_loaded
          ? null
          : (bool v) async {
              setState(() => _color = v);
              await MediaPrefs.setColorPhotos(v);
            },
    );
  }
}

class _Swatches extends StatelessWidget {
  const _Swatches({required this.tokens});

  final MmTokens tokens;

  @override
  Widget build(BuildContext context) {
    final MmSkin skin = context.skin;
    Widget dot(Color c) => Container(
          width: 10,
          height: 10,
          margin: const EdgeInsets.only(left: 2),
          decoration: BoxDecoration(
            color: c,
            shape: BoxShape.circle,
            border: Border.all(color: skin.color.edge, width: 1),
          ),
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        dot(tokens.base),
        dot(tokens.accent),
        dot(tokens.alert),
      ],
    );
  }
}

class _PermBlock extends StatelessWidget {
  const _PermBlock({
    required this.icon,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final MmSkin skin = context.skin;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: mmRadius(context, 8),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: cs.primary, size: 20),
        ),
        SizedBox(width: skin.space.rowInset),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              SizedBox(height: skin.space.insideText),
              Text(body,
                  style: TextStyle(
                      color: cs.onSurfaceVariant, height: 1.35)),
            ],
          ),
        ),
      ],
    );
  }
}
