// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../gen/app_localizations.dart';
import '../theme/mm_skin.dart';
import '../meshcore/meshcore_controller.dart';
import '../ui/mm_scaffold.dart';
import '../ui/mm_shape.dart';

/// R53 — the Docs hub (a Settings row since R86, `/settings/docs`): a menu
/// into the offline-readable docs (companion protocol, device firmware, this
/// app, and our per-device field notes).
/// Rendered in the futuristic monospace style; each row opens a
/// [DocReaderScreen].
class DocsHubScreen extends StatelessWidget {
  const DocsHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ColorScheme cs = Theme.of(context).colorScheme;
    final MeshcoreController mc = context.watch<MeshcoreController>();
    final String? fw = mc.deviceInfo?.firmwareVersion;

    return Scaffold(
      appBar: AppBar(title: Text(l.tabDocs)),
      body: MmScaffold(
        child: ListView(
          padding: EdgeInsets.fromLTRB(context.skin.space.screenEdge,
              context.skin.space.screenEdge, context.skin.space.screenEdge,
              context.skin.space.emptyState),
          children: <Widget>[
            Text(
              l.docsHubSubtitle,
              style: TextStyle(
                  fontFamily: context.skin.type.wordsMono,
                  fontSize: context.skin.type.sizeBody,
                  height: 1.4,
                  color: cs.onSurfaceVariant),
            ),
            SizedBox(height: context.skin.space.screenEdge),
            _DocCard(
              icon: Icons.terminal,
              title: l.docsProtocolTitle,
              subtitle: l.docsProtocolSub,
              onTap: () => context.push('/docs/protocol'),
            ),
            _DocCard(
              icon: Icons.memory,
              title: l.docsFirmwareTitle,
              subtitle: (fw == null || fw.isEmpty)
                  ? l.docsFirmwareSub
                  : l.docsFirmwareSubVersion(fw),
              onTap: () => context.push('/docs/firmware'),
            ),
            _DocCard(
              icon: Icons.smartphone,
              title: l.docsAppTitle,
              subtitle: l.docsAppSub,
              onTap: () => context.push('/docs/app'),
            ),
            _DocCard(
              icon: Icons.settings_input_antenna,
              title: l.docsDevicesTitle,
              subtitle: l.docsDevicesSub,
              onTap: () => context.push('/docs/devices'),
            ),
            SizedBox(height: context.skin.space.screenEdge),
            Text(
              l.docsHubFooter,
              style: TextStyle(
                  fontFamily: context.skin.type.wordsMono,
                  fontSize: context.skin.type.size(10.5),
                  height: 1.5,
                  color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _DocCard extends StatelessWidget {
  const _DocCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final MmSkin skin = context.skin;
    // A card is a control here, so it is an object with a full-strength
    // outline: at 40 % the border is 1.5:1 on paper and the card's only edge
    // was a Material shadow, which a light ground renders as a grey smear under
    // the text rather than as an edge.
    return Card(
      elevation: 0,
      color: skin.color.surface,
      margin: EdgeInsets.only(bottom: skin.space.rowInset),
      shape: RoundedRectangleBorder(
        borderRadius: mmRadius(context, kRadiusMd),
        side: BorderSide(color: skin.color.edge, width: skin.shape.borderWidth),
      ),
      child: InkWell(
        borderRadius: mmRadius(context, 12),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: skin.space.screenEdge,
              vertical: skin.space.screenEdge),
          child: Row(
            children: <Widget>[
              Container(
                width: skin.space.step(9) + skin.space.step(4),
                height: skin.space.step(9) + skin.space.step(4),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: .14),
                  borderRadius: mmRadius(context, kRadiusSm),
                ),
                child: Icon(icon, color: cs.primary, size: 22),
              ),
              SizedBox(width: context.skin.space.rowInset),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title.toUpperCase(),
                        style: TextStyle(
                            fontFamily: context.skin.type.wordsMono,
                            fontSize: context.skin.type.size(14),
                            letterSpacing: 1.5,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface)),
                    SizedBox(height: context.skin.space.labelToControl),
                    Text(subtitle,
                        style: TextStyle(
                            fontFamily: context.skin.type.wordsMono,
                            fontSize: context.skin.type.size(11.5),
                            height: 1.35,
                            color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
