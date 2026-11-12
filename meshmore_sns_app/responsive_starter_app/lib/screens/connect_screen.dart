// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:meshcore/meshcore.dart' show MeshcoreConnectionState;

import '../gen/app_localizations.dart';
import '../meshcore/failure.dart';
import '../meshcore/meshcore_controller.dart';
import '../theme/mm_skin.dart';
import '../ui/mm_components.dart';
import '../ui/mm_scaffold.dart';

/// The one screen that answers "connect a radio".
///
/// Every place in the app that said "connect" used to answer differently: the
/// composer opened the pairing flow, the dashboard started a connection
/// directly, the device sheet did both, and the app-bar chip opened a
/// diagnostics console. So the same words did four things, and the composer's
/// version — the one a person meets when the text field is dead — went to a
/// scanner even when a radio was already paired and only needed a link.
///
/// This screen reads the radio's state and offers the one action that state
/// needs: a paired radio gets Connect, an unpaired one gets Scan, a live one gets
/// Disconnect. Diagnostics stays reachable from here for the field tool it is,
/// instead of being the first thing a person meets.
class ConnectScreen extends StatelessWidget {
  const ConnectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;
    final MeshcoreController mc = context.watch<MeshcoreController>();

    final bool live = mc.state == MeshcoreConnectionState.ready;
    final bool paired = mc.hasPairedDevice;
    final String radio = mc.pairedName ?? mc.selfInfo?.name ?? '';
    final String state = live
        ? (radio.isEmpty ? l.linkChipLinked : radio)
        : mc.isConnecting
            ? l.chatConnecting
            : paired
                ? (radio.isEmpty ? l.chatNoRadio : radio)
                : l.chatNoRadio;

    return MmScaffold(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: <Widget>[
          Text(state,
              key: const ValueKey<String>('connect-state'),
              style: TextStyle(
                color: skin.color.fg,
                fontSize: skin.type.sizeTitle,
                fontWeight: FontWeight.w600,
              )),
          const SizedBox(height: 12),
          // The action the state needs. One button, not three: a person who has
          // just been told the radio is paired does not need to choose between
          // "connect", "pair" and "diagnostics".
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              if (live)
                MmAction(
                  key: const ValueKey<String>('connect-disconnect'),
                  icon: Icons.link_off,
                  label: l.diagnosticsDisconnect,
                  onPressed: mc.isConnecting ? null : mc.disconnect,
                )
              else if (paired)
                MmAction(
                  key: const ValueKey<String>('connect-now'),
                  icon: Icons.bluetooth_searching,
                  label: l.actionConnect,
                  onPressed: mc.isConnecting ? null : mc.connect,
                )
              else
                MmAction(
                  key: const ValueKey<String>('connect-scan'),
                  icon: Icons.add_link,
                  label: l.diagnosticsPairRadio,
                  onPressed: () => context.push('/pair'),
                ),
              // Scanning for a different radio is a second question, so it is a
              // second, quieter control that only appears when one is already
              // paired.
              if (paired && !live)
                MmAction(
                  key: const ValueKey<String>('connect-scan-other'),
                  icon: Icons.add_link,
                  label: l.diagnosticsPairRadio,
                  onPressed: () => context.push('/pair'),
                ),
            ],
          ),
          if (mc.failure case final Failure f) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              failureText(l, f),
              key: const ValueKey<String>('connect-error'),
              style: TextStyle(color: skin.color.alert, fontSize: skin.type.sizeBody),
            ),
          ],
          const SizedBox(height: 20),
          MmAction(
            key: const ValueKey<String>('connect-diagnostics'),
            icon: Icons.monitor_heart_outlined,
            label: l.diagnosticsTitle,
            onPressed: () => context.push('/settings/diagnostics'),
          ),
        ],
      ),
    );
  }
}
