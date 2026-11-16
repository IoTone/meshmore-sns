// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../gen/app_localizations.dart';
import '../cue/cue_service.dart';
import '../theme/mm_tokens.dart';
import '../theme/theme_controller.dart';
import '../ui/mm_collapse_controller.dart';
import '../ui/mm_components.dart';
import '../ui/mm_collapsible.dart';
import '../ui/mm_scaffold.dart';
import '../ui/mm_shape.dart';
import '../theme/mm_skin.dart';

/// Profile & personalization (R14): live preset / font / accessibility
/// picker. The chosen design concept is the default theme; all six
/// ship here as selectable presets (D = default, also high-contrast).
class PersonalizationScreen extends StatelessWidget {
  const PersonalizationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeController tc = context.watch<ThemeController>();
    final AppLocalizations l = AppLocalizations.of(context);
    return Scaffold(
      // The same words the door uses. This page held the theme presets, the
      // type scale and the accessibility switches — appearance and
      // accessibility, with no profile anywhere on it — under a title that
      // named something else.
      appBar: AppBar(title: Text(l.settingsHubProfile)),
      body: MmScaffold(
        child: ListView(
          children: <Widget>[
            MmCollapsibleSection(
              id: MmGroupIds.persPreset,
              title: l.personalizationThemePreset,
              children: <Widget>[
                // When High contrast is ON, the rendered theme is forced
                // to SEELE regardless of which preset is selected. Hint
                // the user so a tap that "does nothing" makes sense.
                if (tc.highContrast)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                        context.skin.space.screenEdge,
                        0,
                        context.skin.space.screenEdge,
                        context.skin.space.labelToControl),
                    child: Container(
                      padding: EdgeInsets.all(context.skin.space.rowInset),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        borderRadius: mmRadius(context, kRadiusSm),
                      ),
                      child: Row(
                        children: <Widget>[
                          Icon(Icons.info_outline,
                              size: 16,
                              color: Theme.of(context).colorScheme.primary),
                          SizedBox(width: context.skin.space.rowGap),
                          Expanded(
                            child: Text(
                              l.personalizationHighContrastHint,
                              style: TextStyle(
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                  fontSize: context.skin.type.sizeBody,
                                  height: 1.35),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                // Plain ListTile + onTap (rather than RadioGroup +
                // RadioListTile) — the latter wasn't reliably firing
                // `setPreset` in 3.35, so the chosen theme was a no-op.
                // We render the radio glyph by hand so the row visually
                // matches a RadioListTile.
                for (final MmThemePreset p in MmThemePreset.values)
                  Opacity(
                    opacity: tc.highContrast ? 0.55 : 1.0,
                    child: ListTile(
                      dense: true,
                      onTap: () {
                        // A theme is a sound as well as a colour, so picking one
                        // plays it. The cue is the pack's own `discovery` — the
                        // sound a theme's neighbours make when they arrive —
                        // which is the shortest honest sample of the pack.
                        tc.setPreset(p);
                        _playSample(context, CueKind.discovery);
                      },
                      leading: Icon(
                        tc.preset == p
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: tc.preset == p
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      title: Text(p.label),
                      trailing: _Swatches(kMmPresets[p]!),
                    ),
                  ),
              ],
            ),
            SizedBox(height: context.skin.space.sectionGap),
            MmCollapsibleSection(
              id: MmGroupIds.persType,
              title: l.personalizationType,
              children: <Widget>[
                ListTile(
                  dense: true,
                  title: Text(l.personalizationFontSize),
                  subtitle: Slider(
                    min: 0.8,
                    max: 1.6,
                    divisions: 8,
                    value: tc.fontScale,
                    label: '${(tc.fontScale * 100).round()}%',
                    onChanged: tc.setFontScale,
                  ),
                ),
              ],
            ),
            SizedBox(height: context.skin.space.sectionGap),
            MmCollapsibleSection(
              id: MmGroupIds.persAccessibility,
              title: l.personalizationAccessibility,
              children: <Widget>[
                SwitchListTile(
                  dense: true,
                  title: Text(l.personalizationHighContrast),
                  subtitle: Text(l.personalizationHighContrastSubtitle),
                  value: tc.highContrast,
                  onChanged: tc.setHighContrast,
                ),
                SwitchListTile(
                  dense: true,
                  title: Text(l.personalizationReduceMotion),
                  value: tc.reduceMotion,
                  onChanged: tc.setReduceMotion,
                ),
                SwitchListTile(
                  dense: true,
                  title: Text(l.personalizationVisualHapticOnly),
                  subtitle: Text(l.personalizationVisualHapticOnlySubtitle),
                  value: tc.visualHapticOnly,
                  onChanged: tc.setVisualHapticOnly,
                ),
              ],
            ),
            SizedBox(height: context.skin.space.sectionGap),
            MmCollapsibleSection(
              id: MmGroupIds.persAudio,
              title: l.personalizationAudioAlerts,
              children: <Widget>[
                SwitchListTile(
                  dense: true,
                  title: Text(l.personalizationAudioMaster),
                  subtitle: Text(tc.visualHapticOnly
                      ? l.personalizationAudioMasterDisabled
                      : l.personalizationAudioMasterEnabled),
                  value: tc.audioMaster,
                  onChanged: tc.visualHapticOnly ? null : tc.setAudioMaster,
                ),
                // The trim, because the phone's own media volume is a choice
                // about everything that plays and cannot be ours to set. The
                // packs are normalised to a -1.5 dBFS peak, so 100 % is sane.
                ListTile(
                  dense: true,
                  enabled: tc.audioMaster && !tc.visualHapticOnly,
                  title: Text(l.personalizationCueVolume),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Slider(
                        min: 0,
                        max: 1,
                        divisions: 10,
                        value: tc.cueVolume,
                        label: '${(tc.cueVolume * 100).round()}%',
                        onChanged: tc.audioMaster && !tc.visualHapticOnly
                            ? tc.setCueVolume
                            : null,
                      ),
                      Text(
                        l.personalizationCueVolumeSubtitle(
                            '${(tc.cueVolume * 100).round()}'),
                        style: TextStyle(
                            fontSize: context.skin.type.sizeSm,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant),
                      ),
                      // Measured on the owner's handset: the media stream sat
                      // at two of fifteen while notifications were loud, so
                      // every cue was inaudible and the app looked broken. The
                      // slider above cannot fix that, and nothing else on this
                      // screen says which stream a cue uses.
                      Text(
                        l.personalizationCueStreamNote,
                        style: TextStyle(
                            fontSize: context.skin.type.sizeSm,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                // Every pack is written for its own theme, and the only way to
                // judge one is to hear it in the place it can be changed.
                Padding(
                  padding: EdgeInsets.fromLTRB(
                      context.skin.space.screenEdge,
                      0,
                      context.skin.space.screenEdge,
                      context.skin.space.rowGap),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: MmAction(
                      key: const ValueKey<String>('cue-preview'),
                      icon: Icons.volume_up,
                      label: l.personalizationCuePreview,
                      onPressed: tc.audioMaster && !tc.visualHapticOnly
                          ? () => _playSample(context, CueKind.alert)
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Swatches extends StatelessWidget {  const _Swatches(this.t);
  final MmTokens t;
  @override
  Widget build(BuildContext context) {
    // A swatch is a colour chip, so its outline comes from the skin's rule.
    // The white 20 % edge it used before vanishes on a light ground — and the
    // light preset is one of the choices this very row exists to offer, so the
    // swatch for it was the one you could not see.
    final Color outline = context.skin.color.edge;
    Widget dot(Color c) => Container(
          width: context.skin.space.rowInset + context.skin.space.insideText,
          height: context.skin.space.rowInset + context.skin.space.insideText,
          margin: EdgeInsets.only(left: context.skin.space.insideText),
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(kRadiusSm),
            border: Border.all(color: outline),
          ),
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[dot(t.base), dot(t.accent), dot(t.alert)],
    );
  }
}

/// Play one cue of the active pack.
///
/// Guarded like `MmAudioToggle`: a widget test pumps this screen without the
/// audio stack above it, and a preview is not worth a ProviderNotFound.
void _playSample(BuildContext context, CueKind kind) {
  CueService? cue;
  try {
    cue = context.read<CueService>();
  } on ProviderNotFoundException {
    cue = null;
  }
  unawaited(cue?.play(kind) ?? Future<void>.value());
}
