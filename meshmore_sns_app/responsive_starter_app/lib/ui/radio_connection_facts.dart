// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:meshcore/meshcore.dart';
import 'package:provider/provider.dart';

import '../gen/app_localizations.dart';
import '../meshcore/failure.dart';
import '../meshcore/meshcore_controller.dart';
import '../theme/mm_skin.dart';
import 'mm_components.dart';
import 'mm_confirm.dart';

/// What the radio link is doing, and the four things a reader can do about it.
///
/// One widget because there are two screens that show it and they must not
/// disagree: `/settings/connection` for a reader, and the diagnostics console for
/// a developer who wants the state visible while reading frames. The facts are
/// read from [MeshcoreController] directly, so there is no second copy to keep in
/// step — only the rendering is shared.
///
/// Every line is conditional on the link having reported it. A fact that has not
/// been reported is absent rather than shown as a zero: this page exists to say
/// what is true, and a row of zeros reads as a healthy link.
class RadioConnectionFacts extends StatelessWidget {
  const RadioConnectionFacts({super.key, this.showActions = true});

  /// Whether to render the Connect/Pair/Forget row under the facts. On by
  /// default, because a state without a way to change it is a readout rather
  /// than a control, and this page is the app's one place for both.
  final bool showActions;

  @override
  Widget build(BuildContext context) {
    final MeshcoreController mc = context.watch<MeshcoreController>();
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;
    final ColorScheme cs = Theme.of(context).colorScheme;
    final bool live = mc.state == MeshcoreConnectionState.ready ||
        mc.state == MeshcoreConnectionState.handshaking ||
        mc.state == MeshcoreConnectionState.reconnecting;

    // One fact per line. A joined subtitle could not be read at a glance and
    // its line count changed with the link, which is why this block is a stack:
    // state, radio, battery, link, last datagram, paired.
    Widget fact(String text) => Padding(
          padding: EdgeInsets.fromLTRB(
              skin.space.step(4), skin.space.step(1), skin.space.step(4),
              skin.space.step(1)),
          child: Text(text,
              style: TextStyle(
                  color: cs.onSurface,
                  fontSize: skin.type.sizeBody,
                  fontFamily: skin.type.bodyFamily,
                  height: 1.35)),
        );
    // A fault is the one thing here that gets a sentence, because it is the
    // only line a reader can act on.
    Widget fault(String text) => Padding(
          padding: EdgeInsets.fromLTRB(
              skin.space.step(4), skin.space.step(2), skin.space.step(4),
              skin.space.step(1)),
          child: Text(text,
              style: TextStyle(
                  color: cs.error,
                  fontSize: skin.type.sizeBody,
                  fontFamily: skin.type.bodyFamily,
                  height: 1.35)),
        );

    final String stateText = switch (mc.state) {
          MeshcoreConnectionState.disconnected => l.diagnosticsStateDisconnected,
          MeshcoreConnectionState.handshaking => l.diagnosticsStateHandshaking,
          MeshcoreConnectionState.ready => l.diagnosticsStateReady,
          MeshcoreConnectionState.reconnecting =>
            l.diagnosticsStateReconnecting,
          MeshcoreConnectionState.failed => l.diagnosticsStateFailed,
        } +
        (mc.isConnecting ? l.diagnosticsConnectingSuffix : '');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _SectionLabel(l.diagnosticsSectionConnection),
        fact(l.diagnosticsStateLine(stateText)),
        if (mc.selfInfo != null)
          fact(l.diagnosticsDeviceLine(mc.selfInfo!.name,
              '${mc.selfInfo!.frequencyMhz}', '${mc.selfInfo!.spreadingFactor}')),
        if (mc.batteryMillivolts != null)
          fact(l.diagnosticsBatteryLine(
                  mc.batteryVolts!.toStringAsFixed(2), '${mc.batteryPercent}') +
              (mc.charging == true ? l.diagnosticsChargingSuffix : '')),
        if (mc.mtu != null)
          fact(l.diagnosticsMtuLine('${mc.mtu}', '${MeshcoreBle.requiredMtu}')),
        // Which radio carried the last channel datagram. The byte only means
        // something while a second profile is on, so "unreported" is the normal
        // reading on a single-profile radio.
        if (mc.lastFrame case final ChannelDataFrame d)
          fact(l.diagnosticsDatagramLine('${d.channelIndex}',
              _viaLabel(l, d.via), '0x${d.dataType.toRadixString(16).padLeft(4, '0')}')),
        if (mc.reconnectAttempt > 0)
          fact(l.diagnosticsReconnectLine('${mc.reconnectAttempt}') +
              (mc.gaveUp ? l.diagnosticsGaveUpSuffix : '')),
        // A handshake started more than once, or one that got no answer, is the
        // shape of the report that read "handshaking for a long time". Shown
        // only when there is something to see: one clean handshake is the
        // normal case, and this page is already dense.
        if (mc.handshakeAttempts > 1 || mc.handshakeTimeouts > 0)
          fact(l.diagnosticsHandshakeLine(
              '${mc.handshakeAttempts}', '${mc.handshakeTimeouts}')),
        // A teardown the phone never finished. Counted, not a fault: the app
        // opened a new link anyway, and this is the only trace that the previous
        // one had to be abandoned.
        if (mc.linkCloseTimeouts > 0)
          fact(l.diagnosticsLinkCloseLine('${mc.linkCloseTimeouts}')),
        if (mc.mtuRefusal != null)
          fault(l.diagnosticsMtuRefusedLine(
              '${mc.mtuRefusal!.mtu}', '${MeshcoreBle.requiredMtu}'))
        else if (mc.truncatedFrames > 0 ||
            mc.trailingBytesFrames > 0 ||
            mc.emptyFrames > 0)
          fact(l.diagnosticsFramingLine('${mc.truncatedFrames}',
              '${mc.trailingBytesFrames}', '${mc.emptyFrames}'))
        else if (mc.failure != null)
          fault(l.diagnosticsErrorLine(failureText(l, mc.failure!)))
        else if (mc.error != null)
          fault(l.diagnosticsErrorLine('${mc.error}')),
        // A frame that lost a step. It is a fault rather than a counter because
        // the app cannot say which part of it is missing, and the only honest
        // reading is that some of its data may not be there.
        if (mc.framesDropped > 0)
          fault(l.diagnosticsFramesDroppedLine(mc.framesDropped)),
        // APP-C5 — the app's own duty-cycle meter, always charging. A refusal is
        // the one line here a user can act on, so it is a sentence rather than a
        // counter when it has happened.
        fact(mc.airtimeBudget == null
            ? l.airtimeSpentLineUnlimited(mmShortDuration(mc.airtimeSpent))
            : l.airtimeSpentLine(mmShortDuration(mc.airtimeSpent),
                mmShortDuration(mc.airtimeBudget!))),
        if (mc.airtimeRefusals > 0)
          fault(l.airtimeRefusedCount(mc.airtimeRefusals)),
        // Three counters that were kept and read by nothing. Each one is a
        // thing that happened and left no trace on any screen, which is the
        // same defect as a received picture that nothing claimed: the app knew,
        // and the reader did not.
        if (mc.unansweredCommands > 0)
          fact(l.diagnosticsUnansweredLine(mc.unansweredCommands)),
        if (mc.reactionsWithoutTarget > 0)
          fact(l.diagnosticsReactionsOrphanedLine(mc.reactionsWithoutTarget)),
        // The cost of asking peers for readings. It is a fact rather than a
        // fault: every one of these was a frame this app chose to send, and the
        // number is how a reader sees what the telemetry poller costs.
        if (mc.telemetrySendCount > 0)
          fact(l.diagnosticsTelemetryAskedLine(mc.telemetrySendCount)),
        if (showActions) ...<Widget>[
          SizedBox(height: skin.space.step(2)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: skin.space.step(4)),
            // Three peer actions, one control. They used to be a filled button,
            // an outlined button with an icon and an outlined button without
            // one, side by side: three weights for three peers, which reads as a
            // ranking nobody intended. `MmAction` is the app's own control, and
            // every one of them carries an icon so the row scans as a row.
            child: Wrap(
              spacing: skin.space.step(2),
              runSpacing: skin.space.step(2),
              alignment: WrapAlignment.start,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                MmAction(
                  key: const ValueKey<String>('diag-connect'),
                  icon: live ? Icons.link_off : Icons.bluetooth_searching,
                  label: live ? l.diagnosticsDisconnect : l.actionConnect,
                  onPressed: () => live ? mc.disconnect() : mc.connect(),
                ),
                MmAction(
                  key: const ValueKey<String>('diag-pair'),
                  icon: Icons.add_link,
                  // One connect screen: pairing and connecting are two states of
                  // the same question, and `/connect` is where both live.
                  label: l.diagnosticsPairRadio,
                  onPressed: () => context.push('/connect'),
                ),
                if (mc.hasPairedDevice)
                  MmAction(
                    key: const ValueKey<String>('diag-forget'),
                    icon: Icons.link_off,
                    label: l.diagnosticsForgetShort,
                    onPressed: () => _confirmForget(context, mc),
                  ),
              ],
            ),
          ),
        ],
        if (mc.hasPairedDevice)
          Padding(
            padding: EdgeInsets.only(top: skin.space.step(2)),
            child: fact(l.diagnosticsPairedLine('${mc.pairedName}')),
          ),
        // D8.7 — the BLE identity can survive a reflash while the radio's own key
        // does not. When the key changed, the history on screen belongs to
        // another node and nothing is migrated until the user says which radio
        // this is.
        if (mc.radioChanged)
          Padding(
            padding: EdgeInsets.fromLTRB(skin.space.step(4), skin.space.step(2),
                skin.space.step(4), skin.space.step(1)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  l.diagnosticsRadioChangedLine(
                      mmShortKey(mc.previousRadioKey ?? '?'),
                      mmShortKey(mc.ownPubKeyHex ?? '?')),
                  style: TextStyle(
                      color: cs.error,
                      fontSize: skin.type.sizeBody,
                      fontFamily: skin.type.bodyFamily,
                      height: 1.35),
                ),
                SizedBox(height: skin.space.step(1)),
                // The same control as every other action here: a lone
                // OutlinedButton was the fourth style on one screen.
                MmAction(
                  icon: Icons.check,
                  label: l.diagnosticsRadioChangedAccept,
                  onPressed: () => mc.acceptRadioIdentity(),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// The profile byte has three readings and only one of them is a fault, so the
  /// label says which without judging it.
  static String _viaLabel(AppLocalizations l, RxVia via) => switch (via) {
        RxVia.primary => l.rxViaPrimary,
        RxVia.secondary => l.rxViaSecondary,
        RxVia.unknown => l.rxViaUnknown,
      };
}

/// Forget is irreversible — it drops the paired record, the OS bond and the
/// history entry — so it asks first and names the consequence.
Future<void> _confirmForget(BuildContext context, MeshcoreController mc) async {
  final AppLocalizations l = AppLocalizations.of(context);
  final bool forget = await mmConfirm(
    context,
    title: l.diagnosticsForgetConfirmTitle,
    body: l.diagnosticsForgetConfirmBody,
    cancelLabel: l.cancel,
    confirmLabel: l.diagnosticsForgetShort,
    destructive: true,
  );
  if (forget) await mc.forgetDevice();
}

/// A section label in the skin's own voice, matching what the console draws.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(
            context.skin.space.screenEdge,
            context.skin.space.screenEdge,
            context.skin.space.screenEdge,
            context.skin.space.rowGap),
        child: Text(text, style: mmSectionLabelStyle(context.skin)),
      );
}

/// Seconds to `12s`, a minute and more to `1m 05s`. The meter line is read at a
/// glance next to other one-fact lines, so it never says `0:00:12`.
String mmShortDuration(Duration d) {
  final int s = d.inSeconds;
  if (s < 60) return '${s}s';
  final int m = s ~/ 60;
  final int rest = s % 60;
  return rest == 0 ? '${m}m' : '${m}m ${rest.toString().padLeft(2, '0')}s';
}

/// The first and last four hex characters of a key, which is enough to tell two
/// radios apart without putting a 64-character key in a sentence.
String mmShortKey(String hex) => hex.length <= 8
    ? hex
    : '${hex.substring(0, 4)}…${hex.substring(hex.length - 4)}';
