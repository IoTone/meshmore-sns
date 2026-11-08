// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
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

  /// `CMD_REBOOT`: no reply, the link drops, the reconnect brings it back.
  ///
  /// The firmware persists its own state and drops whatever was queued for the
  /// app, so the confirmation names that rather than pretending the restart is
  /// free.
  Future<void> _restartRadio(
      MeshcoreController mc, AppLocalizations l) async {
    final bool? go = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(l.diagnosticsRestartRadio),
        content: Text(l.diagnosticsRestartConfirm),
        actions: <Widget>[
          MmAction(
              label: l.actionCancel, onPressed: () => Navigator.pop(ctx, false)),
          MmAction(
              label: l.diagnosticsRestartRadio,
              onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    if (go != true || !mounted) return;
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
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    FilledButton.icon(
                      icon: Icon(
                          live ? Icons.link_off : Icons.bluetooth_searching),
                      label: Text(live
                          ? l.diagnosticsDisconnect
                          : l.diagnosticsScanConnect),
                      onPressed: () => live ? mc.disconnect() : mc.connect(),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.add_link),
                      label: Text(l.diagnosticsPairRadio),
                      onPressed: () => context.push('/pair'),
                    ),
                    if (mc.hasPairedDevice)
                      OutlinedButton(
                        onPressed: () => _confirmForget(mc),
                        child: Text(l.diagnosticsForgetShort),
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
                      OutlinedButton(
                        onPressed: () => mc.acceptRadioIdentity(),
                        child: Text(l.diagnosticsRadioChangedAccept),
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
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () => _send(mc,
                          MeshcoreFrameCodec.sendSelfAdvert(), 'self-advert'),
                      child: Text(l.diagnosticsSendSelfAdvert),
                    ),
                    OutlinedButton(
                      onPressed: () => _send(
                          mc, MeshcoreFrameCodec.getDeviceTime(), 'get-time'),
                      child: Text(l.diagnosticsReadClock),
                    ),
                    OutlinedButton(
                      onPressed: () => _send(mc,
                          MeshcoreFrameCodec.syncNextMessage(), 'sync-msg'),
                      child: Text(l.diagnosticsPullMessage),
                    ),
                    // The radio's own restart (`CMD_REBOOT` 0x13). It is the
                    // only way out of a radio that has stopped answering its
                    // own screens, and it silently drops any message it was
                    // holding, so it asks first and says what it costs.
                    OutlinedButton.icon(
                      onPressed: mc.isReady ? () => _restartRadio(mc, l) : null,
                      icon: const Icon(Icons.restart_alt, size: 18),
                      label: Text(l.diagnosticsRestartRadio),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: _msg,
                          decoration: InputDecoration(
                              labelText: l.diagnosticsTestMessage),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () => _send(
                          mc,
                          MeshcoreFrameCodec.sendChannelTextMessage(
                            channelIdx: 0,
                            timestamp: nowUnix,
                            text: _msg.text,
                          ),
                          'ch0 message',
                        ),
                        child: Text(l.diagnosticsSend),
                      ),
                    ],
                  ),
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
    final bool? forget = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(l.diagnosticsForgetConfirmTitle),
        content: Text(l.diagnosticsForgetConfirmBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.diagnosticsForgetShort),
          ),
        ],
      ),
    );
    if (forget == true) await mc.forgetDevice();
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
