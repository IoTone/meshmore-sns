// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:meshcore/meshcore.dart';
import 'package:provider/provider.dart';

import '../bot/bot_controller.dart';
import '../bot/bot_guards.dart';
import '../bot/responder.dart';
import '../gen/app_localizations.dart';
import '../meshcore/failure.dart';
import 'raw_record_card.dart';
import '../ui/mm_components.dart';
import '../ui/mm_collapse_controller.dart';
import '../ui/mm_collapsible.dart';
import '../ui/mm_confirm.dart';
import '../ui/mm_scaffold.dart';
import '../theme/mm_skin.dart';
import '../ui/radio_health_block.dart';
import 'diagnostics_redaction.dart';
import '../meshcore/chat_store.dart';
import '../places/place_store.dart';
import '../meshcore/meshcore_controller.dart';
import '../ui/mm_shape.dart';

/// Field/dev tool: connect to a real Meshcore radio, watch live state
/// and the raw frame log, send test commands, and run the M6
/// interop closure (export a `grp_txt_capture` fixture + the
/// channel-secret-tail oracle) — all over the existing
/// `MeshcoreController`. Reached from Settings.
/// L1/L2 — one redactor for every path that leaves the screen. The
/// encrypted frames stay (they are the evidence); a channel key, a node key
/// and a position do not.
const DiagnosticsRedaction _redaction = DiagnosticsRedaction();

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  final TextEditingController _msg =
      TextEditingController(text: 'M6 interop test 1');
  String? _exportJson;
  String? _oracleResult;

  static String get _pubPskHex => kPublicChannelPsk
      .map((int b) => b.toRadixString(16).padLeft(2, '0'))
      .join();

  Uint8List _hex(String s) {
    final Uint8List out = Uint8List(s.length ~/ 2);
    for (int i = 0; i < out.length; i++) {
      out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  @override
  void dispose() {
    _msg.dispose();
    super.dispose();
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  // --- The radio's own alert outputs (D8.24) ---------------------------
  //
  // `get/set buzzer` and `get/set vibration` are the two commands the whitelist
  // ships: they change what the radio does on its own, with no app involved,
  // which is why they are here and not on a settings page a user would find by
  // accident. Nothing is sent by opening the fold — every frame is channel
  // time — so the read is the button.
  RadioCliResult? _buzzer;
  RadioCliResult? _vibration;
  bool _alertsReading = false;

  Future<void> _readAlerts(MeshcoreController mc) async {
    if (_alertsReading || !mc.isReady) return;
    setState(() => _alertsReading = true);
    try {
      // Each value is shown as it arrives: one read that is slow, or that times
      // out, must not hold the other row at "asking the radio" for six more
      // seconds.
      final RadioCliResult b =
          await mc.runRadioCli(const BuzzerCommand.read(), correlation: 'b1');
      if (!mounted) return;
      setState(() => _buzzer = b);
      final RadioCliResult v =
          await mc.runRadioCli(const VibrationCommand.read(), correlation: 'v1');
      if (!mounted) return;
      setState(() => _vibration = v);
    } finally {
      if (mounted) setState(() => _alertsReading = false);
    }
  }

  /// Send one `set`, then read the value back.
  ///
  /// The re-read is the proof: the radio clamps and may refuse, and a screen
  /// that showed what was asked for instead of what was stored would be lying
  /// about the radio's own alerting.
  Future<void> _setAlert(MeshcoreController mc,
      {required bool buzzer, required bool enable}) async {
    final AppLocalizations l = AppLocalizations.of(context);
    final ScaffoldMessengerState sm = ScaffoldMessenger.of(context);
    final RadioCliResult r = await mc.runRadioCli(
      buzzer ? BuzzerCommand(enable) : VibrationCommand(enable),
      correlation: buzzer ? 'b2' : 'v2',
    );
    if (!mounted) return;
    setState(() {
      if (buzzer) {
        _buzzer = r;
      } else {
        _vibration = r;
      }
    });
    sm
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(_alertOutcome(l, r))));
    await _readAlerts(mc);
  }

  /// What to say about one CLI answer. A refusal names the firmware's cause,
  /// because "refused (bad state)" is actionable and "refused" is not.
  String _alertOutcome(AppLocalizations l, RadioCliResult r) => switch (r) {
        RadioCliAnswered(:final String text) =>
          text.isEmpty ? l.diagnosticsAlertDone : l.diagnosticsAlertSaid(text),
        RadioCliRejected(:final int? code, :final String text) =>
          text.isEmpty
              ? l.diagnosticsAlertRefused(
                  failureText(l, Failure.deviceError(code)))
              : l.diagnosticsAlertRefusedSaid(
                  failureText(l, Failure.deviceError(code)), text),
        RadioCliSilent(:final String partial) => partial.isEmpty
            ? l.diagnosticsAlertSilent
            : l.diagnosticsAlertSilentPartial(partial),
        RadioCliBusy() => l.diagnosticsAlertBusy,
        RadioCliUnavailable() => l.diagnosticsAlertUnavailable,
      };

  /// `CMD_REBOOT`: no reply, the link drops, the reconnect brings it back.
  ///
  /// The firmware persists its own state and drops whatever was queued for the
  /// app, so the confirmation names that rather than pretending the restart is
  /// free.
  Future<void> _restartRadio(
      MeshcoreController mc, AppLocalizations l) async {
    final bool go = await mmConfirm(
      context,
      title: l.diagnosticsRestartRadio,
      body: l.diagnosticsRestartConfirm,
      cancelLabel: l.actionCancel,
      confirmLabel: l.diagnosticsRestartRadio,
      // A restart drops the link and anything queued on the radio, which is
      // what the body says; the tone is the rest of the warning.
      destructive: true,
    );
    if (!go || !mounted) return;
    final ScaffoldMessengerState sm = ScaffoldMessenger.of(context);
    try {
      await mc.send(MeshcoreFrameCodec.reboot());
      sm
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(l.diagnosticsRestartSent)));
    } catch (_) {
      sm
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(l.diagnosticsRestartNoReply)));
    }
  }

  Future<void> _send(MeshcoreController mc, Uint8List frame, String what) async {
    // Read the strings before the await: the widget can be gone afterwards,
    // and the toast already guards on mounted.
    final AppLocalizations l = AppLocalizations.of(context);
    try {
      await mc.send(frame);
      _toast(l.diagnosticsSentWhat(what));
    } catch (e) {
      _toast(l.diagnosticsSendFailed('$e'));
    }
  }

  void _export(MeshcoreController mc) {
    try {
      final String json = _redaction.json(mc.exportGrpTxtFixture(
        pskHex: _pubPskHex,
        knownPlaintextUtf8: _msg.text,
        channelName: kPublicChannelName,
        firmware: 'companion-v1.15.0 / dee3e26 (record exact T1000-E fw)',
        description: 'Public-channel msg captured via 0x88',
      ));
      setState(() => _exportJson = json);
    } catch (e) {
      _toast(AppLocalizations.of(context).diagnosticsExportNeedsCapture);
    }
  }

  void _resolveTail(MeshcoreController mc) {
    final String? hex = mc.lastRfLogHex;
    if (hex == null) {
      _toast(AppLocalizations.of(context).diagnosticsNoRfLog);
      return;
    }
    final MeshcoreInbound f = MeshcoreFrameCodec.decode(_hex(hex));
    if (f is! RfLogFrame) {
      _toast(AppLocalizations.of(context).diagnosticsNotRfLog);
      return;
    }
    final GrpTxtPayload? g = f.log.packet?.grpTxt;
    if (g == null) {
      _toast(AppLocalizations.of(context).diagnosticsNotGrpTxt);
      return;
    }
    final ChannelTailResult r = resolveChannelTail(
      psk: Uint8List.fromList(kPublicChannelPsk),
      knownPlaintext: Uint8List.fromList(utf8.encode(_msg.text)),
      grpTxt: g,
    );
    setState(() => _oracleResult = r.resolved
        ? 'RESOLVED → channel-secret tail = ${r.match!.name} '
            '(channelHashOk: ${r.channelHashOk})'
        : 'UNRESOLVED — try another capture / confirm PSK & plaintext');
  }

  @override
  Widget build(BuildContext context) {
    final MeshcoreController mc = context.watch<MeshcoreController>();
    final ColorScheme cs = Theme.of(context).colorScheme;
    final AppLocalizations l = AppLocalizations.of(context);
    final bool live = mc.state == MeshcoreConnectionState.ready ||
        mc.state == MeshcoreConnectionState.handshaking ||
        mc.state == MeshcoreConnectionState.reconnecting;
    final int nowUnix = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    // R23: full capture buffer scrolls inside a bounded pane below,
    // so the page-level scroll keeps the State/Sends/Capture context
    // visible regardless of how long the log gets.
    final List<String> log = mc.captureLog.reversed.toList();

    // The profile byte has three readings and only one of them is a fault,
    // so the label says which without judging it.
    String viaLabel(AppLocalizations l, RxVia via) => switch (via) {
          RxVia.primary => l.rxViaPrimary,
          RxVia.secondary => l.rxViaSecondary,
          RxVia.unknown => l.rxViaUnknown,
        };

    final MmSkin skin = context.skin;
    // One fact per line. A joined subtitle could not be read at a glance and
    // its line count changed with the link, which is why the connection block
    // is a stack now: state, radio, battery, link, last datagram, paired.
    Widget fact(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
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
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(text,
              style: TextStyle(
                  color: cs.error,
                  fontSize: skin.type.sizeBody,
                  fontFamily: skin.type.bodyFamily,
                  height: 1.35)),
        );
    Widget section(String t) => Padding(
          padding: EdgeInsets.fromLTRB(context.skin.space.screenEdge, context.skin.space.screenEdge, context.skin.space.screenEdge, context.skin.space.rowGap),
          child: Text(t, style: mmSectionLabelStyle(skin)),
        );
    // One alert output: what the radio says it is, and the two explicit choices.
    // Two buttons rather than one toggle on purpose (D8.24): a mute rule must
    // never be able to unmute silently, so the on/off intent is the label the
    // user pressed. The button that matches the current state is disabled, so a
    // second tap cannot re-assert what is already set.
    Widget alertRow({required bool buzzer}) {
      final String name =
          buzzer ? l.diagnosticsBuzzer : l.diagnosticsVibration;
      final RadioCliResult? r = buzzer ? _buzzer : _vibration;
      final bool? state = r is RadioCliAnswered ? r.onOff : null;
      final String said = r == null
          ? (_alertsReading
              ? l.diagnosticsAlertReading
              : l.diagnosticsAlertNotRead)
          : _alertOutcome(l, r);
      final String id = buzzer ? 'buzzer' : 'vibration';
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('$name — $said',
                key: ValueKey<String>('radio-alert-$id-said'),
                style: TextStyle(
                    color: r is RadioCliRejected ? cs.error : cs.onSurface,
                    fontSize: skin.type.sizeBody,
                    fontFamily: skin.type.bodyFamily,
                    height: 1.35)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, children: <Widget>[
              MmAction(
                key: ValueKey<String>('radio-alert-$id-on'),
                label: l.diagnosticsAlertOn,
                dense: true,
                onPressed: !mc.isReady || state == true
                    ? null
                    : () => _setAlert(mc, buzzer: buzzer, enable: true),
              ),
              MmAction(
                key: ValueKey<String>('radio-alert-$id-off'),
                label: l.diagnosticsAlertOff,
                dense: true,
                onPressed: !mc.isReady || state == false
                    ? null
                    : () => _setAlert(mc, buzzer: buzzer, enable: false),
              ),
            ]),
          ],
        ),
      );
    }

    final String stateText = switch (mc.state) {
          MeshcoreConnectionState.disconnected => l.diagnosticsStateDisconnected,
          MeshcoreConnectionState.handshaking => l.diagnosticsStateHandshaking,
          MeshcoreConnectionState.ready => l.diagnosticsStateReady,
          MeshcoreConnectionState.reconnecting =>
            l.diagnosticsStateReconnecting,
          MeshcoreConnectionState.failed => l.diagnosticsStateFailed,
        } +
        (mc.isConnecting ? l.diagnosticsConnectingSuffix : '');

    return Scaffold(
      appBar:
          AppBar(title: Text(AppLocalizations.of(context).diagnosticsTitle)),
      body: MmScaffold(
        child: ListView(
        children: <Widget>[
          // The variable part of the page is ONE child of the list: a fact
          // appears when the link reports it, and a shifting child list makes
          // the list's keep-alive wrappers remount subtrees that own a
          // collapsible group.
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              section(l.diagnosticsSectionConnection),
              fact(l.diagnosticsStateLine(stateText)),
              if (mc.selfInfo != null)
                fact(l.diagnosticsDeviceLine(mc.selfInfo!.name,
                    '${mc.selfInfo!.frequencyMhz}',
                    '${mc.selfInfo!.spreadingFactor}')),
              if (mc.batteryMillivolts != null)
                fact(l.diagnosticsBatteryLine(
                        mc.batteryVolts!.toStringAsFixed(2),
                        '${mc.batteryPercent}') +
                    (mc.charging == true ? l.diagnosticsChargingSuffix : '')),
              if (mc.mtu != null)
                fact(l.diagnosticsMtuLine(
                    '${mc.mtu}', '${MeshcoreBle.requiredMtu}')),
              // Which radio carried the last channel datagram. The byte only
              // means something while a second profile is on, so "unreported"
              // is the normal reading on a single-profile radio.
              if (mc.lastFrame case final ChannelDataFrame d)
                fact(l.diagnosticsDatagramLine(
                    '${d.channelIndex}',
                    viaLabel(l, d.via),
                    '0x${d.dataType.toRadixString(16).padLeft(4, '0')}')),
              if (mc.reconnectAttempt > 0)
                fact(l.diagnosticsReconnectLine('${mc.reconnectAttempt}') +
                    (mc.gaveUp ? l.diagnosticsGaveUpSuffix : '')),
              // A handshake started more than once, or one that got no answer,
              // is the shape of the report that read "handshaking for a long
              // time". Shown only when there is something to see: one clean
              // handshake is the normal case, and this page is already dense.
              if (mc.handshakeAttempts > 1 || mc.handshakeTimeouts > 0)
                fact(l.diagnosticsHandshakeLine(
                    '${mc.handshakeAttempts}', '${mc.handshakeTimeouts}')),
              // A teardown the phone never finished. Counted, not a fault: the
              // app opened a new link anyway, and this is the only trace that
              // the previous one had to be abandoned.
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
              // A frame that lost a step. It is a fault rather than a counter
              // because the app cannot say which part of it is missing, and
              // the only honest reading is that some of its data may not be
              // there.
              if (mc.framesDropped > 0)
                fault(l.diagnosticsFramesDroppedLine(mc.framesDropped)),
              // APP-C5 — the app's own duty-cycle meter, always charging.
              // A refusal is the one line here a user can act on, so it is a
              // sentence rather than a counter when it has happened.
              fact(mc.airtimeBudget == null
                  ? l.airtimeSpentLineUnlimited(_shortDuration(mc.airtimeSpent))
                  : l.airtimeSpentLine(_shortDuration(mc.airtimeSpent),
                      _shortDuration(mc.airtimeBudget!))),
              if (mc.airtimeRefusals > 0)
                fault(l.airtimeRefusedCount(mc.airtimeRefusals)),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                // Three peer actions, one control. They used to be a filled
                // button, an outlined button with an icon and an outlined
                // button without one, side by side: three weights for three
                // peers, which reads as a ranking nobody intended. `MmAction`
                // is the app's own control, and every one of them carries an
                // icon so the row scans as a row.
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.start,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    MmAction(
                      key: const ValueKey<String>('diag-connect'),
                      icon: live ? Icons.link_off : Icons.bluetooth_searching,
                      label: live
                          ? l.diagnosticsDisconnect
                          : l.actionConnect,
                      onPressed: () => live ? mc.disconnect() : mc.connect(),
                    ),
                    MmAction(
                      key: const ValueKey<String>('diag-pair'),
                      icon: Icons.add_link,
                      // One connect screen: pairing and connecting are two states
                      // of the same question, and `/connect` is where both live.
                      label: l.diagnosticsPairRadio,
                      onPressed: () => context.push('/connect'),
                    ),
                    if (mc.hasPairedDevice)
                      MmAction(
                        key: const ValueKey<String>('diag-forget'),
                        icon: Icons.link_off,
                        label: l.diagnosticsForgetShort,
                        onPressed: () => _confirmForget(mc),
                      ),
                  ],
                ),
              ),
              if (mc.hasPairedDevice)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: fact(l.diagnosticsPairedLine('${mc.pairedName}')),
                ),
              // D8.7 — the BLE identity can survive a reflash while the
              // radio's own key does not. When the key changed, the history
              // on screen belongs to another node and nothing is migrated
              // until the user says which radio this is.
              if (mc.radioChanged)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        l.diagnosticsRadioChangedLine(
                            _shortKey(mc.previousRadioKey ?? '?'),
                            _shortKey(mc.ownPubKeyHex ?? '?')),
                        style: TextStyle(
                            color: cs.error,
                            fontSize: skin.type.sizeBody,
                            fontFamily: skin.type.bodyFamily,
                            height: 1.35),
                      ),
                      const SizedBox(height: 4),
                      // The same control as every other action on the page: a
                      // lone OutlinedButton here was the fourth style on one
                      // screen.
                      MmAction(
                        icon: Icons.check,
                        label: l.diagnosticsRadioChangedAccept,
                        onPressed: () => mc.acceptRadioIdentity(),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                // The block carries its own title and its own Read action, so
                // a section header above it said "radio health" twice in the
                // same breath — the duplicated label rule the dashboard obeys.
                child: const RadioHealthBlock(),
              ),
            ],
          ),
          // Everything below is a developer surface: it is folded away by
          // default so the connection facts and the one action stay the page.
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: MmCollapsibleSection(
              id: MmGroupIds.diagnosticsDeveloper,
              title: l.diagnosticsSectionDeveloper,
              initiallyExpanded: false,
              children: <Widget>[
                // The one place the sealed store's state is stated: whether the
                // history can be opened on this device, and whether the last
                // write reached it. Both are facts a support question needs.
                section(l.diagnosticsHistoryStore),
                ValueListenableBuilder<bool>(
                  valueListenable: ChatStore.unreadable,
                  builder: (BuildContext _, bool lost, Widget? __) =>
                      ValueListenableBuilder<String?>(
                    valueListenable: ChatStore.lastWriteFailure,
                    builder: (BuildContext _, String? failed, Widget? ___) {
                      final String code = failed ?? 'current';
                      return fact(lost
                          ? l.diagnosticsHistoryStoreKeyLost
                          : failed == null
                              ? l.diagnosticsHistoryStoreOk
                              : l.diagnosticsHistoryStoreWriteFailed(code));
                    },
                  ),
                ),
                section(l.diagnosticsPlaceStore),
                ValueListenableBuilder<bool>(
                  valueListenable: PlaceStore.writeFailed,
                  builder: (BuildContext _, bool failed, Widget? __) => fact(
                      failed
                          ? l.diagnosticsPlaceStoreWriteFailed
                          : l.diagnosticsPlaceStoreOk),
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: PlaceStore.corruptDocumentKept,
                  builder: (BuildContext _, bool kept, Widget? __) => kept
                      ? fact(l.diagnosticsPlaceStoreCorruptKept)
                      : const SizedBox.shrink(),
                ),
                section(l.diagnosticsSectionSend),
                // One padded Wrap with one control style. It used to be four
                // OutlinedButtons behind a stray `SizedBox(width: 8)`, so the
                // first button was indented by a widget that only existed to
                // fake a margin, and the restart carried an icon the other
                // three did not. `MmAction` in a padded Wrap fixes both.
                // One column of equal-width actions, not a Wrap.
                //
                // A Wrap gave each button its label's own width, and these four
                // labels are 15 to 22 characters: on the phone they stacked one
                // per line at four different widths, which is the "too many
                // rows, badly laid out" the owner reported. Equal width makes
                // the column deliberate, and a column cannot be ragged.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      MmAction(
                        icon: Icons.campaign_outlined,
                        label: l.diagnosticsSendSelfAdvert,
                        onPressed: () => _send(mc,
                            MeshcoreFrameCodec.sendSelfAdvert(), 'self-advert'),
                      ),
                      const SizedBox(height: 8),
                      MmAction(
                        icon: Icons.schedule,
                        label: l.diagnosticsReadClock,
                        onPressed: () => _send(mc,
                            MeshcoreFrameCodec.getDeviceTime(), 'get-time'),
                      ),
                      const SizedBox(height: 8),
                      MmAction(
                        icon: Icons.download_outlined,
                        label: l.diagnosticsPullMessage,
                        onPressed: () => _send(mc,
                            MeshcoreFrameCodec.syncNextMessage(), 'sync-msg'),
                      ),
                      const SizedBox(height: 8),
                      // The radio's own restart (`CMD_REBOOT` 0x13). It is the
                      // only way out of a radio that has stopped answering its
                      // own screens, and it silently drops any message it was
                      // holding, so it asks first and says what it costs.
                      MmAction(
                        icon: Icons.restart_alt,
                        label: l.diagnosticsRestartRadio,
                        onPressed:
                            mc.isReady ? () => _restartRadio(mc, l) : null,
                      ),
                    ],
                  ),
                ),
                // The field takes the row and the button keeps its own width:
                // a bare `Row` with the button's intrinsic width squeezed the
                // field to nothing at a narrow width.
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: _msg,
                          decoration: InputDecoration(
                              labelText: l.diagnosticsTestMessage),
                        ),
                      ),
                      const SizedBox(width: 8),
                      MmAction(
                        key: const ValueKey<String>('diag-send-test'),
                        label: l.diagnosticsSend,
                        onPressed: () => _send(
                          mc,
                          MeshcoreFrameCodec.sendChannelTextMessage(
                            channelIdx: 0,
                            timestamp: nowUnix,
                            text: _msg.text,
                          ),
                          'ch0 message',
                        ),
                      ),
                    ],
                  ),
                ),
                // The radio's own alert outputs. Folded inside the developer
                // section on purpose: this changes what the radio does with no
                // app involved, and every frame it costs is channel time, so
                // nothing here is sent by opening a fold.
                section(l.diagnosticsSectionRadioAlerts),
                Column(
                  key: const Key('radio-alerts'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                      child: Text(l.diagnosticsRadioAlertsWhy,
                          style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontSize: skin.type.sizeSm,
                              fontFamily: skin.type.bodyFamily,
                              height: 1.35)),
                    ),
                    alertRow(buzzer: true),
                    alertRow(buzzer: false),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: MmAction(
                          key: const Key('radio-alerts-read'),
                          label: l.diagnosticsAlertRead,
                          dense: true,
                          onPressed: !mc.isReady || _alertsReading
                              ? null
                              : () => _readAlerts(mc),
                        ),
                      ),
                    ),
                  ],
                ),
                // Where the position the app acts on actually came from,
                // in raw numbers. This readout used to sit on the dashboard
                // under the location value, where it was developer detail in a
                // place a user reads; the values are the same, the audience is
                // now the developer section that exists for exactly this.
                section(l.diagnosticsPosition),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 6,
                    children: <Widget>[
                      fact(l.diagnosticsPositionRadio(
                          mc.selfInfo?.latitude.toStringAsFixed(6) ?? '—',
                          mc.selfInfo?.longitude.toStringAsFixed(6) ?? '—')),
                      fact(l.diagnosticsPositionPolicy(
                          mc.customVars['advert_loc_policy'] ??
                              mc.customVars['advertLocPolicy'] ??
                              '—')),
                      fact(l.diagnosticsPositionPhone(
                          mc.ownLocation == null
                              ? l.diagnosticsPositionNone
                              : mc.ownLocation!.source.name)),
                    ],
                  ),
                ),
                // The retained raw-send capability, with the caller D10.1
                // kept it for: one typed record to one contact, answered by
                // the radio's own OK or ERR rather than by a chat row.
                const SizedBox(height: 8),
                RawRecordCard(mc: mc),
                section(l.diagnosticsSectionM6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
                    OutlinedButton.icon(
                      icon: const Icon(Icons.bug_report_outlined),
                      label: Text(l.diagnosticsResolveTail),
                      onPressed: () => _resolveTail(mc),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.save_alt),
                      label: Text(l.diagnosticsExportFixture),
                      onPressed: () => _export(mc),
                    ),
                  ]),
                ),
                if (_oracleResult != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text(_oracleResult!,
                        style: TextStyle(color: cs.primary)),
                  ),
                if (_exportJson != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        TextButton.icon(
                          icon: const Icon(Icons.copy, size: 16),
                          label: Text(l.diagnosticsCopyFixture),
                          onPressed: () {
                            Clipboard.setData(
                                ClipboardData(text: _exportJson!));
                            _toast(l.diagnosticsFixtureCopied);
                          },
                        ),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(8),
                          color: cs.surfaceContainerHighest,
                          child: SelectableText(_exportJson!,
                              style: TextStyle(
                                  fontFamily: skin.type.monoFamily,
                                  fontSize: skin.type.sizeSm)),
                        ),
                      ],
                    ),
                  ),
                // R59 — soak evidence. Per-scope counters aggregated here so a
                // run can be read and exported without opening each sheet.
                const _BotSoakPanel(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(l.diagnosticsRawFrameLog,
                            style: mmSectionLabelStyle(skin)),
                      ),
                      TextButton.icon(
                        onPressed: mc.captureLog.isEmpty
                            ? null
                            : () {
                                // A capture pasted into a bug report must not
                                // carry a channel secret: a frame log has no
                                // field names, so the redactor masks the one
                                // frame that does (CHANNEL_INFO) and leaves
                                // every other frame replayable.
                                final String blob = _redaction
                                    .frames(mc.captureLog.reversed)
                                    .map((String h) => '${_label(h)}\t$h')
                                    .join('\n');
                                Clipboard.setData(ClipboardData(text: blob));
                                _toast(
                                    l.diagnosticsFramesCopied('${mc.captureLog.length}'));
                              },
                        icon: const Icon(Icons.copy, size: 16),
                        label: Text(l.diagnosticsCopyLog),
                      ),
                    ],
                  ),
                ),
                // R23 / U14: bounded inner scroll for the frame log so the user
                // can scroll the capture without losing the connection facts
                // above. Nested ListView is constrained by the SizedBox; the
                // outer page-level ListView owns the rest.
                Container(
                  margin: EdgeInsets.fromLTRB(
                      context.skin.space.screenEdge,
                      context.skin.space.labelToControl,
                      context.skin.space.screenEdge,
                      context.skin.space.screenEdge),
                  // Fifteen step-eights: a bounded inner scroll, expressed from
                  // the ladder rather than as a private 360.
                  height: context.skin.space.step(8) * 15,
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: context.skin.color.line,
                        width: context.skin.shape.borderWidth),
                    borderRadius: mmRadius(context, kRadiusSm),
                  ),
                  child: log.isEmpty
                      ? Center(child: Text(l.diagnosticsNoFrames))
                      : Scrollbar(
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            itemCount: log.length,
                            itemBuilder: (BuildContext _, int i) {
                              final String hex = log[i];
                              return ListTile(
                                dense: true,
                                title: Text(
                                  _label(hex),
                                  style: TextStyle(
                                      color: hex.startsWith('88')
                                          ? cs.primary
                                          : cs.onSurface),
                                ),
                                subtitle: Text(
                                  hex.length > 64
                                      ? '${hex.substring(0, 64)}…'
                                      : hex,
                                  style: TextStyle(
                                      fontFamily: skin.type.monoFamily,
                                      fontSize: skin.type.sizeMicro),
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  /// Forget is irreversible — it drops the paired record, the OS bond and the
  /// history entry — so it asks first and names the consequence.
  Future<void> _confirmForget(MeshcoreController mc) async {
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

  String _label(String hex) {
    try {
      final MeshcoreInbound f = MeshcoreFrameCodec.decode(_hex(hex));
      return f.runtimeType.toString();
    } catch (_) {
      return 'op 0x${hex.length >= 2 ? hex.substring(0, 2) : '?'}';
    }
  }
}

/// R59 — bot soak counters, aggregated across every bound scope.
///
/// Lives on Diagnostics rather than only in the per-scope sheets
/// because a soak run is read *afterwards*, often by someone who was
/// not the one who configured it. "Which scopes were running, what did
/// they do, and can I replay it" should be one screen, not a tour.
class _BotSoakPanel extends StatelessWidget {
  const _BotSoakPanel();

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;
    final BotController bot = context.watch<BotController>();
    final List<MapEntry<String, BotBinding>> scopes =
        bot.bindings.entries.toList();

    // Nothing has ever been bound — say so plainly rather than showing
    // an empty table that looks like a broken readout.
    if (scopes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Text(l.diagnosticsSoakEmpty, style: mmSectionLabelStyle(skin)),
      );
    }

    final BotCounters t = bot.totals();
    final TextStyle mono = TextStyle(
        fontFamily: skin.type.monoFamily, fontSize: skin.type.sizeSm);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l.diagnosticsSectionSoak, style: mmSectionLabelStyle(skin)),
          const SizedBox(height: 6),
          Text(
            'total  rx ${t.received}  tx ${t.replied}  '
            'own ${t.suppressedOwn}  loop ${t.suppressedLoop}  '
            'rate ${t.suppressedRate}  nomatch ${t.noMatch}  '
            'refused ${t.refused}',
            style: mono,
          ),
          const SizedBox(height: 4),
          for (final MapEntry<String, BotBinding> e in scopes)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                '${e.value.enabled ? "on " : "off"} ${e.key}  '
                'rx ${e.value.counters.received} '
                'tx ${e.value.counters.replied} '
                '(${e.value.mode.id}'
                '${e.value.mode == BotMode.random ? " seed ${e.value.seed}" : ""})',
                style: mono.copyWith(
                    color:
                        e.value.enabled ? cs.onSurface : cs.onSurfaceVariant),
              ),
            ),
          const SizedBox(height: 4),
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: Text(l.diagnosticsCopySoak),
            onPressed: () {
              Clipboard.setData(ClipboardData(
                  text: _redaction.maskSecrets(bot.exportReport())));
              ScaffoldMessenger.maybeOf(context)
                ?..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(
                  content: Text(l.diagnosticsSoakCopied),
                  duration: const Duration(seconds: 2),
                ));
            },
          ),
        ],
      ),
    );
  }
}

/// Seconds to `12s`, a minute and more to `1m 05s`. The meter line is read at a
/// glance next to other one-fact lines, so it never says `0:00:12`.
String _shortDuration(Duration d) {
  final int s = d.inSeconds;
  if (s < 60) return '${s}s';
  final int m = s ~/ 60;
  final int rest = s % 60;
  return rest == 0 ? '${m}m' : '${m}m ${rest.toString().padLeft(2, '0')}s';
}

/// The first and last four hex characters of a key, which is enough to tell two
/// radios apart without putting a 64-character key in a sentence.
String _shortKey(String hex) =>
    hex.length <= 8 ? hex : '${hex.substring(0, 4)}…${hex.substring(hex.length - 4)}';
