// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:meshcore/meshcore.dart' show MeshcoreConnectionState;

import '../gen/app_localizations.dart';
import '../meshcore/failure.dart';
import '../meshcore/meshcore_controller.dart';
import '../meshcore/paired_device_history.dart';
import '../meshcore/radio_switch.dart';
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

    // A pushed screen needs a bar: without one there is no title and no back
    // control, and the heading is drawn under the status bar clock.
    return Scaffold(
      appBar: AppBar(title: Text(l.connectTitle)),
      body: MmScaffold(
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
          // D8.9 — one session, and changing it is explicit. The list is the
          // radios this phone has paired, newest first, and the one in use is
          // marked rather than offered: a row that switches to the radio you
          // are already on is a control that does nothing.
          if (mc.pairedHistory.length > 1) ...<Widget>[
            const SizedBox(height: 24),
            Text(l.radioSwitchTitle,
                style: mmSectionLabelStyle(skin)),
            const SizedBox(height: 6),
            for (final PairedDeviceHistoryEntry e in mc.pairedHistory)
              _PairedRadioRow(
                entry: e,
                current: e.remoteId == mc.pairedRemoteId,
                onSwitch: () => _switchTo(context, mc, e),
              ),
          ],
        ],
      ),
      ),
    );
  }

  /// Switch, and say what happened.
  ///
  /// The refusal is the interesting case: a message still waiting for an answer
  /// belongs to the link it was sent on, so the switch is refused rather than
  /// leaving that row to time out into a failure the app cannot prove.
  Future<void> _switchTo(
    BuildContext context,
    MeshcoreController mc,
    PairedDeviceHistoryEntry entry,
  ) async {
    final AppLocalizations l = AppLocalizations.of(context);
    final RadioSwitchOutcome outcome =
        await switchRadio(mc, remoteId: entry.remoteId, name: entry.name);
    if (!context.mounted) return;
    final String message = switch (outcome) {
      RadioSwitchOutcome.switched => l.radioSwitchDone(entry.name),
      RadioSwitchOutcome.sameRadio => l.radioSwitchSame,
      RadioSwitchOutcome.refusedUnsettled => l.radioSwitchWaiting,
    };
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(message)));
  }
}

/// One paired radio, with the one action it can take.
class _PairedRadioRow extends StatelessWidget {
  const _PairedRadioRow({
    required this.entry,
    required this.current,
    required this.onSwitch,
  });

  final PairedDeviceHistoryEntry entry;
  final bool current;
  final VoidCallback onSwitch;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Icon(
            current ? Icons.bluetooth_connected : Icons.bluetooth,
            size: 18,
            color: current ? skin.color.link : skin.color.fgMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              entry.name,
              key: ValueKey<String>('radio-switch-name-${entry.remoteId}'),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: skin.color.fg,
                fontSize: skin.type.sizeBody,
              ),
            ),
          ),
          if (current)
            Text(l.radioSwitchCurrent,
                style: TextStyle(
                    color: skin.color.fgMuted, fontSize: skin.type.sizeSm))
          else
            MmAction(
              key: ValueKey<String>('radio-switch-${entry.remoteId}'),
              dense: true,
              label: l.radioSwitchAction,
              onPressed: onSwitch,
            ),
        ],
      ),
    );
  }
}
