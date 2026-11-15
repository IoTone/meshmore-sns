// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../gen/app_localizations.dart';
import '../media/aeic_installer.dart';
import '../media/media_mode.dart';
import '../media/media_prefs.dart';
import '../ui/mm_components.dart';

/// The photo rows, drawn by Settings → Chat & photos.
///
/// A file rather than a page: the page was three rows of App settings promoted to
/// their own screen, and then folded into Chat & photos with history, which is
/// where a reader looks for them. Spoken voice is not here: it is a reading
/// preference and lives in App settings.

/// Photo mode: preview, preview plus the full picture on request, or neural.
///
/// A sheet rather than a switch because the three answers differ in what the
/// reader *gets*, not in on/off, and each states its own cost so the choice is
/// made on the number.
class PhotoModeTile extends StatefulWidget {
  const PhotoModeTile({super.key, this.cs, this.l});

  /// Optional overrides for older call sites; the tile reads the theme itself.
  final ColorScheme? cs;
  final AppLocalizations? l;

  @override
  State<PhotoModeTile> createState() => PhotoModeTileState();
}

class PhotoModeTileState extends State<PhotoModeTile> {
  MediaMode _mode = MediaMode.onRequest;

  @override
  void initState() {
    super.initState();
    MediaModePrefs.photoMode().then((MediaMode m) {
      if (mounted) setState(() => _mode = m);
    });
  }

  String label(AppLocalizations l, MediaMode m) => switch (m) {
        MediaMode.preview => l.photoModePreview,
        MediaMode.onRequest => l.photoModeOnRequest,
        MediaMode.neural => l.codecTitle,
      };

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ColorScheme cs = Theme.of(context).colorScheme;
    return ListTile(
      key: const ValueKey<String>('settings-photo-mode'),
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.photo_size_select_large),
      title: Text(l.photoModeTitle),
      subtitle: Text('${label(l, _mode)} · ${_mode.bytes}',
          style: TextStyle(color: cs.onSurfaceVariant)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        final AeicInstaller? codec =
            Provider.of<AeicInstaller?>(context, listen: false);
        final MediaMode? picked = await showModalBottomSheet<MediaMode>(
          context: context,
          showDragHandle: true,
          builder: (BuildContext ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (final MediaMode m in MediaMode.values)
                  ListTile(
                    key: ValueKey<String>('photo-mode-${m.id}'),
                    dense: true,
                    title: Text(label(l, m)),
                    subtitle: Text(
                        m == MediaMode.neural
                            ? (!kAeicEncodeAvailable
                                ? l.codecUnavailableHere
                                : (codec?.ready ?? false
                                    ? '${m.quality} · ${m.bytes}'
                                    : l.photoModeNeedsCodec))
                            : '${m.quality} · ${m.bytes}',
                        style: TextStyle(color: cs.onSurfaceVariant)),
                    // Neural is offered only when this build can encode it *and*
                    // the bundle is on disk. A mode that cannot encode is a
                    // promise the app cannot keep.
                    enabled: m != MediaMode.neural ||
                        (kAeicEncodeAvailable && (codec?.ready ?? false)),
                    trailing: m == _mode ? Icon(Icons.check, color: cs.primary) : null,
                    onTap: () => Navigator.pop(ctx, m),
                  ),
              ],
            ),
          ),
        );
        if (picked == null || !mounted) return;
        setState(() => _mode = picked);
        await MediaModePrefs.setPhotoMode(picked);
      },
    );
  }
}

/// The neural codec's install state, and the one action that changes it.
class AeicCodecRow extends StatelessWidget {
  const AeicCodecRow({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ColorScheme cs = Theme.of(context).colorScheme;
    final AeicInstaller? codec = Provider.of<AeicInstaller?>(context);
    if (codec == null) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: codec,
      builder: (BuildContext context, Widget? _) {
        final double? progress = codec.progress;
        final String subtitle = switch (codec.state) {
          AeicState.ready => '${l.codecInstalled} · ${l.codecLicence}',
          AeicState.working => progress == null
              ? l.codecDownload
              : '${(progress * 100).clamp(0, 100).toStringAsFixed(0)} %',
          // The reason stays out of the row: it carries a file name, a byte
          // count and sometimes an HTTP status, and a settings row is not a
          // place to spell a device code into user text.
          AeicState.failed => l.codecFailed,
          AeicState.partial => l.codecNotInstalled,
          AeicState.absent => '${l.codecNotInstalled} · ${l.codecLicence}',
        };
        return ListTile(
          key: const ValueKey<String>('settings-photo-codec'),
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.memory),
          title: Text(l.codecTitle),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(subtitle, style: TextStyle(color: cs.onSurfaceVariant)),
              if (codec.state == AeicState.working) ...<Widget>[
                const SizedBox(height: 6),
                LinearProgressIndicator(value: progress),
              ],
              if (!kAeicEncodeAvailable)
                Text(l.codecUnavailableHere,
                    style: TextStyle(color: cs.onSurfaceVariant)),
            ],
          ),
          trailing: switch (codec.state) {
            AeicState.working => MmAction(
                key: const ValueKey<String>('codec-cancel'),
                dense: true,
                label: l.codecCancel,
                onPressed: codec.cancel),
            AeicState.ready => IconButton(
                key: const ValueKey<String>('codec-remove'),
                tooltip: l.codecRemove,
                icon: const Icon(Icons.delete_outline),
                onPressed: codec.busy ? null : codec.remove),
            _ => MmAction(
                key: const ValueKey<String>('codec-download'),
                dense: true,
                label: codec.state == AeicState.failed
                    ? l.codecRetry
                    : l.codecDownload,
                onPressed: codec.busy ? null : codec.install),
          },
        );
      },
    );
  }
}

/// Colour or grey. A mesh photo has one budget and grey is a third of the data,
/// so grey is the default and this is the way back.
class PhotoColorSwitch extends StatefulWidget {
  const PhotoColorSwitch({
    super.key,
    this.secondary,
    this.contentPadding = EdgeInsets.zero,
    this.tileKey = const ValueKey<String>('settings-photo-color'),
  });

  /// The leading icon. Both surfaces pass one, because a row without it puts
  /// its title in the icon column, 16 dp left of every title around it.
  final Widget? secondary;

  /// The row's own padding. Zero by default, because both surfaces that draw
  /// this row put it inside a list that already supplies the page edge.
  final EdgeInsetsGeometry? contentPadding;

  /// The key on the row itself, so a second surface can name its own row.
  final Key tileKey;

  @override
  State<PhotoColorSwitch> createState() => PhotoColorSwitchState();
}

class PhotoColorSwitchState extends State<PhotoColorSwitch> {
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
    final AppLocalizations l = AppLocalizations.of(context);
    return SwitchListTile(
      key: widget.tileKey,
      dense: true,
      contentPadding: widget.contentPadding,
      secondary: widget.secondary,
      title: Text(l.settingsPhotoColorTitle),
      subtitle: Text(l.settingsPhotoColorSub,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      value: _color,
      // Off until the preference has been read: a thumb that jumps after the
      // first frame is worse than a moment of "off".
      onChanged: !_loaded
          ? null
          : (bool v) async {
              setState(() => _color = v);
              await MediaPrefs.setColorPhotos(v);
            },
    );
  }
}
