// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:meshcore/meshcore.dart';
import 'package:provider/provider.dart';

import '../app/app_errors.dart';
import '../bot/bot_controller.dart';
import '../bot/bot_guards.dart';
import '../bot/responder.dart';
import '../gen/app_localizations.dart';
import '../meshcore/failure.dart';
import 'raw_record_card.dart';
import '../ui/mm_confirm.dart';
import '../ui/mm_components.dart';
import '../ui/radio_connection_facts.dart';
import '../ui/mm_collapse_controller.dart';
import '../ui/mm_collapsible.dart';
import '../ui/app_errors_list.dart';
import '../ui/mm_scaffold.dart';
import '../theme/mm_skin.dart';
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
    final int nowUnix = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    // R23: full capture buffer scrolls inside a bounded pane below,
    // so the page-level scroll keeps the State/Sends/Capture context
    // visible regardless of how long the log gets.
    final List<String> log = mc.captureLog.reversed.toList();

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
          // The facts and the four actions are one widget, shared with
          // `/settings/connection`: a developer reading frames wants the link
          // state visible, and two copies of these lines would drift.
          const RadioConnectionFacts(),
          // The door back to the reader-facing half. A console is a place a
          // person arrives at deliberately, and the way out is named.
          Padding(
            padding: EdgeInsets.symmetric(
                horizontal: skin.space.step(1), vertical: skin.space.step(2)),
            child: ListTile(
              key: const ValueKey<String>('diagnostics-connection-row'),
              leading: const Icon(Icons.bluetooth_searching),
              title: Text(l.settingsHubDiagnostics),
              subtitle: Text(l.connectionDiagnosticsExplainer),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/connection'),
            ),
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
                // The app's own failures, current run and previous one.
                //
                // `AppErrors` has collected the last twenty throws since it was
                // written and nothing read them: the records were held in memory
                // for "the Diagnostics developer section" that did not exist. A
                // periodic freeze therefore left no trace anywhere — the process
                // died, and with it the only account of what had thrown. The list
                // is written to prefs on every error and read back at launch, so a
                // run that ended badly is still readable here.
                section(l.diagnosticsSectionErrors),
                AppErrorsList(errors: AppErrors.previous, previous: true),
                AppErrorsList(errors: AppErrors.records, previous: false),
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
