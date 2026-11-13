// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:meshcore/meshcore.dart';
import 'package:provider/provider.dart';

import '../gen/app_localizations.dart';
import '../meshcore/failure.dart';
import '../meshcore/meshcore_controller.dart';
import '../meshcore/pair_scanner.dart';
import '../perms/permissions_service.dart';
import '../theme/mm_skin.dart';
import '../ui/mm_scaffold.dart';
import '../ui/mm_shape.dart';

/// The in-app pairing flow: find a radio, connect to it, and confirm which one
/// it is, without leaving the app.
///
/// Every step is one state with one action, because the five ways this can
/// fail (permission refused, adapter off, nothing in range, the open fails, the
/// user leaves mid-scan) are what a person actually meets; a scan list with no
/// state on top of it reports all five the same way.
///
/// The store's declaration video needs this to be an app screen, not a hop
/// through the phone's Bluetooth menu — which is also why the flow owns the
/// permission request instead of relying on a screen that happens to ask later.
class PairRadioScreen extends StatefulWidget {
  const PairRadioScreen({
    super.key,
    this.scanner = const BlePairScanner(),
    this.scanWindow = const Duration(seconds: 12),
  });

  /// The platform, behind a seam: the real scanner talks to flutter_blue_plus,
  /// a test scanner hands the screen its five failure paths.
  final PairScanner scanner;

  /// How long one scan listens before it reports what it heard.
  final Duration scanWindow;

  @override
  State<PairRadioScreen> createState() => _PairRadioScreenState();
}

/// Where the flow is. One step at a time; the step decides the copy and the
/// single action under it.
enum _Step { permission, adapter, scan, connect, confirm }

class _PairRadioScreenState extends State<PairRadioScreen> {
  _Step _step = _Step.permission;

  /// The current scan's hits, keyed by remote id so a device whose RSSI
  /// updates does not appear twice.
  final Map<String, PairHit> _hits = <String, PairHit>{};
  StreamSubscription<List<PairHit>>? _scanSub;
  StreamSubscription<AdapterState>? _adapterSub;
  bool _scanning = false;

  /// Why the last attempt stopped. Null while nothing has gone wrong.
  Failure? _failure;

  /// The hit being opened, so the connecting copy can name it.
  PairHit? _opening;

  /// The radio the flow ended on, named by the radio itself when it answers.
  String? _connectedName;

  @override
  void initState() {
    super.initState();
    // A harness (and the accessibility floor) can register a scanner above the
    // router, because the real one talks to the platform and cannot run in a
    // widget test. Without a registration the screen keeps its own default.
    _scanner = context.read<PairScanner?>() ?? widget.scanner;
    WidgetsBinding.instance.addPostFrameCallback((_) => _begin());
  }

  late final PairScanner _scanner;

  @override
  void dispose() {
    // Leaving mid-scan must stop the radio's scanning: the platform keeps the
    // scan alive otherwise, and a background scan is the one thing this screen
    // promises it will not do.
    unawaited(_scanner.stopScan());
    unawaited(_scanSub?.cancel());
    unawaited(_adapterSub?.cancel());
    super.dispose();
  }

  Future<void> _begin() async {
    final PermissionsService perms = context.read<PermissionsService>();
    if (await perms.bleGranted()) {
      await _checkAdapter();
      return;
    }
    if (mounted) setState(() => _step = _Step.permission);
  }

  Future<void> _requestPermission() async {
    final PermissionsService perms = context.read<PermissionsService>();
    final PermissionResult r = await perms.requestBle();
    if (!mounted) return;
    if (r == PermissionResult.granted ||
        r == PermissionResult.notApplicable) {
      await _checkAdapter();
      return;
    }
    setState(() {
      _step = _Step.permission;
      _failure = Failure(FailureCause.blePermissionsDenied);
    });
  }

  Future<void> _checkAdapter() async {
    final AdapterState state = await _scanner.adapterNow();
    if (!mounted) return;
    if (state == AdapterState.on) {
      setState(() {
        _failure = null;
        _step = _Step.scan;
      });
      await _startScan();
      return;
    }
    // Watch for the user switching Bluetooth on in the OS; the flow continues
    // by itself rather than making them come back and press a button.
    await _adapterSub?.cancel();
    _adapterSub = _scanner.adapter.listen((AdapterState s) {
      if (!mounted || s != AdapterState.on || _step != _Step.adapter) return;
      unawaited(_adapterSub?.cancel());
      _adapterSub = null;
      setState(() => _step = _Step.scan);
      unawaited(_startScan());
    });
    if (!mounted) return;
    setState(() {
      _step = _Step.adapter;
      _failure = state == AdapterState.off
          ? Failure(FailureCause.bluetoothOff)
          : null;
    });
  }

  Future<void> _startScan() async {
    await _scanSub?.cancel();
    setState(() {
      _scanning = true;
      _hits.clear();
      _failure = null;
      _step = _Step.scan;
    });
    _scanSub = _scanner.scan(timeout: widget.scanWindow).listen(
      (List<PairHit> snapshot) {
        if (!mounted) return;
        setState(() {
          for (final PairHit h in snapshot) {
            _hits[h.remoteId] = h;
          }
        });
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() {
          _scanning = false;
          _failure = Failure.from(e);
        });
      },
      onDone: () {
        if (!mounted) return;
        setState(() => _scanning = false);
      },
    );
  }

  Future<void> _open(PairHit hit) async {
    // Stop at the platform first, then drop the listener without waiting on
    // it: a cancel that waits for a queued event must not hold the open.
    await _scanner.stopScan();
    unawaited(_scanSub?.cancel());
    _scanSub = null;
    if (!mounted) return;
    setState(() {
      _step = _Step.connect;
      _opening = hit;
      _failure = null;
    });
    final MeshcoreController mc = context.read<MeshcoreController>();
    await mc.connectToPickedDevice(remoteId: hit.remoteId, name: hit.name);
    // `connectToPickedDevice` returns once the transport is attached; the link
    // is only proven when the handshake answers. Waiting for that is the
    // difference between "we opened a socket" and "this radio is talking".
    final MeshcoreConnectionState end = await _awaitLink(mc);
    if (!mounted) return;
    if (end == MeshcoreConnectionState.ready) {
      setState(() {
        _step = _Step.confirm;
        _connectedName = mc.selfInfo?.name ?? hit.name;
      });
      return;
    }
    setState(() {
      _step = _Step.scan;
      _failure = mc.failure ?? const Failure(FailureCause.pairingFailed);
    });
  }

  /// Wait until the link answers or the attempt fails.
  ///
  /// The bound is generous because a screen radio shows a PIN the user has to
  /// type: five seconds is a handshake timeout, not a pairing timeout.
  Future<MeshcoreConnectionState> _awaitLink(MeshcoreController mc) async {
    MeshcoreConnectionState settled() => mc.state;
    bool done() =>
        settled() == MeshcoreConnectionState.ready ||
        settled() == MeshcoreConnectionState.failed;
    if (done()) return settled();
    final Completer<void> reached = Completer<void>();
    void onState() {
      if (!reached.isCompleted && done()) reached.complete();
    }

    mc.addListener(onState);
    try {
      await reached.future.timeout(const Duration(seconds: 30));
    } catch (_) {
      // Timed out: the caller reads the state and reports it like any other
      // failure, with the copy the catalogue already has for a silent radio.
    } finally {
      mc.removeListener(onState);
    }
    return settled();
  }

  void _finish() {
    // The flow was pushed from wherever the user was, so popping returns them
    // there. Entered from a deep link there is still a page under it — the
    // shell — because the router's initial location is the shell.
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;
    return Scaffold(
      appBar: AppBar(title: Text(l.pairTitle)),
      body: MmScaffold(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: <Widget>[
            Text(
              l.pairStepOf(_step.index + 1, _Step.values.length),
              style: TextStyle(
                fontFamily: skin.type.monoFamily,
                fontSize: skin.type.sizeMicro,
                letterSpacing: 2,
                color: skin.color.fgMuted,
              ),
            ),
            SizedBox(height: skin.space.rowGap),
            if (_step == _Step.permission) ..._permission(context, l, skin),
            if (_step == _Step.adapter) ..._adapter(context, l, skin),
            if (_step == _Step.scan) ..._scan(context, l, skin),
            if (_step == _Step.connect) ..._connecting(context, l, skin),
            if (_step == _Step.confirm) ..._confirm(context, l, skin),
          ],
        ),
      ),
    );
  }

  List<Widget> _permission(
      BuildContext context, AppLocalizations l, MmSkin skin) {
    return <Widget>[
      _Headline(text: l.pairPermissionTitle, skin: skin),
      const SizedBox(height: 8),
      _Body(text: l.pairPermissionBody, skin: skin),
      if (_failure != null) ...<Widget>[
        const SizedBox(height: 12),
        _FailureNote(text: failureText(l, _failure!), skin: skin),
      ],
      SizedBox(height: skin.space.screenEdge),
      FilledButton.icon(
        onPressed: _requestPermission,
        icon: const Icon(Icons.bluetooth_searching, size: 18),
        label: Text(l.pairPermissionAllow),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: () => context.read<PermissionsService>().openAppSettingsPage(),
        icon: const Icon(Icons.settings_outlined, size: 18),
        label: Text(l.pairPermissionOpenSettings),
      ),
    ];
  }

  List<Widget> _adapter(
      BuildContext context, AppLocalizations l, MmSkin skin) {
    return <Widget>[
      _Headline(text: l.pairAdapterTitle, skin: skin),
      const SizedBox(height: 8),
      _Body(
        text: _failure?.cause == FailureCause.bluetoothOff
            ? l.pairAdapterBody
            : l.pairAdapterUnsupported,
        skin: skin,
      ),
      SizedBox(height: skin.space.screenEdge),
      FilledButton.icon(
        onPressed: _checkAdapter,
        icon: const Icon(Icons.refresh, size: 18),
        label: Text(l.pairRetry),
      ),
    ];
  }

  List<Widget> _scan(BuildContext context, AppLocalizations l, MmSkin skin) {
    final List<PairHit> sorted = _hits.values.toList()
      ..sort((PairHit a, PairHit b) => b.rssi.compareTo(a.rssi));
    return <Widget>[
      _Headline(text: l.pairScanTitle, skin: skin),
      const SizedBox(height: 8),
      _Body(text: l.pairScanBody, skin: skin),
      if (_failure != null) ...<Widget>[
        const SizedBox(height: 12),
        _FailureNote(text: failureText(l, _failure!), skin: skin),
      ],
      SizedBox(height: skin.space.rowInset),
      if (_scanning)
        Row(
          children: <Widget>[
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: skin.color.accent),
            ),
            SizedBox(width: skin.space.rowGap),
            Text(l.pairScanning,
                style: TextStyle(
                    fontSize: skin.type.sizeSm, color: skin.color.fgMuted)),
            const Spacer(),
            TextButton(
              onPressed: () async {
                await _scanner.stopScan();
                unawaited(_scanSub?.cancel());
                _scanSub = null;
                if (mounted) setState(() => _scanning = false);
              },
              child: Text(l.pairStopScan),
            ),
          ],
        )
      else
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: _startScan,
            icon: const Icon(Icons.search, size: 18),
            label: Text(l.pairScanAgain),
          ),
        ),
      if (!_scanning && sorted.isEmpty) ...<Widget>[
        SizedBox(height: skin.space.rowInset),
        // One sentence for one cause, shared with the failure text: the screen
        // and the diagnostics line were describing the same scan in two
        // different wordings.
        _Body(text: l.failureNoRadioFound, skin: skin),
      ],
      SizedBox(height: skin.space.rowGap),
      for (final PairHit h in sorted)
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Icon(Icons.radio, color: skin.color.accent),
            title: Text(h.name),
            subtitle: Text(
              '${h.remoteId}  ·  ${l.pairRssi(h.rssi)}',
              style: TextStyle(
                fontFamily: skin.type.monoFamily,
                fontSize: skin.type.sizeSm,
                color: skin.color.fgMuted,
              ),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _step == _Step.connect ? null : () => _open(h),
          ),
        ),
    ];
  }

  List<Widget> _connecting(
      BuildContext context, AppLocalizations l, MmSkin skin) {
    return <Widget>[
      _Headline(
          text: l.pairConnecting(_opening?.name ?? ''), skin: skin),
      const SizedBox(height: 12),
      Row(
        children: <Widget>[
          SizedBox.square(
            dimension: skin.space.screenEdge,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: skin.color.accent),
          ),
          const SizedBox(width: 12),
          Expanded(child: _Body(text: l.pairConnectingBody, skin: skin)),
        ],
      ),
    ];
  }

  List<Widget> _confirm(
      BuildContext context, AppLocalizations l, MmSkin skin) {
    final MeshcoreController mc = context.watch<MeshcoreController>();
    final String? firmware = mc.deviceInfo?.firmwareVersion;
    return <Widget>[
      _Headline(text: l.pairConfirmTitle, skin: skin),
      const SizedBox(height: 8),
      _Body(text: l.pairConfirmBody(_connectedName ?? ''), skin: skin),
      SizedBox(height: skin.space.rowInset),
      _Fact(label: l.pairConfirmNode, value: _connectedName ?? '', skin: skin),
      if (firmware != null && firmware.isNotEmpty) ...<Widget>[
        const SizedBox(height: 6),
        _Fact(label: l.pairConfirmFirmware, value: firmware, skin: skin),
      ],
      const SizedBox(height: 20),
      FilledButton.icon(
        onPressed: _finish,
        icon: const Icon(Icons.check, size: 18),
        label: Text(l.pairConfirmUse),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: () {
          setState(() {
            _step = _Step.scan;
            _connectedName = null;
          });
          unawaited(_startScan());
        },
        icon: const Icon(Icons.swap_horiz, size: 18),
        label: Text(l.pairChooseAnother),
      ),
    ];
  }
}

/// A step's heading, in the skin's display face.
class _Headline extends StatelessWidget {
  const _Headline({required this.text, required this.skin});
  final String text;
  final MmSkin skin;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontFamily: skin.type.displayFamily,
        fontSize: skin.type.sizeXl,
        fontWeight: FontWeight.w600,
        color: skin.color.fg,
      ),
    );
  }
}

/// A step's explanation. Prose, so the skin's word face.
class _Body extends StatelessWidget {
  const _Body({required this.text, required this.skin});
  final String text;
  final MmSkin skin;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontFamily: skin.type.wordsMono,
        fontSize: skin.type.sizeBodyLg,
        height: 1.45,
        color: skin.color.fgMuted,
      ),
    );
  }
}

/// A failure, in the skin's alert colour and never as the only signal: the
/// copy says what happened, so colour is decoration rather than information.
class _FailureNote extends StatelessWidget {
  const _FailureNote({required this.text, required this.skin});
  final String text;
  final MmSkin skin;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: skin.space.pad(4),
      decoration: BoxDecoration(
        color: skin.color.surfaceAlt,
        borderRadius: mmRadius(context, 8),
        border: Border.all(color: skin.color.alert.withValues(alpha: .6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.error_outline, size: 18, color: skin.color.alert),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: skin.type.sizeBody,
                height: 1.4,
                color: skin.color.fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A label/value pair on the confirmation step.
class _Fact extends StatelessWidget {
  const _Fact({
    required this.label,
    required this.value,
    required this.skin,
  });
  final String label;
  final String value;
  final MmSkin skin;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Text(
          label,
          style: TextStyle(
            fontSize: skin.type.sizeSm,
            letterSpacing: 1,
            color: skin.color.fgMuted,
          ),
        ),
        SizedBox(width: skin.space.rowGap),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontFamily: skin.type.monoFamily,
              fontSize: skin.type.sizeBody,
              color: skin.color.fg,
            ),
          ),
        ),
      ],
    );
  }
}
