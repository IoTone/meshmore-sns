// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../meshcore/meshcore_controller.dart';
import '../meshcore/own_location.dart';
import 'coverage_model.dart';
import 'coverage_pacing.dart';
import 'geohash.dart';

/// One responder that answered a coverage ping.
final class CoverageResponder {
  const CoverageResponder({
    required this.key,
    this.rssi,
    this.snr,
    this.hops,
  });

  final List<int> key;
  final int? rssi;
  final int? snr;
  final int? hops;
}

/// Sends one ping and reports who answered it.
///
/// A seam rather than a call into the tools: the session must be testable
/// without a radio, and the app's discover tool is the only thing that knows
/// how to ask (`CMD_SEND_CONTROL_DATA` with `DISCOVER_REQ`).
typedef CoveragePinger = Future<List<CoverageResponder>> Function();

/// What one ping did.
enum CoveragePingOutcome { sent, noFix, refused, failed }

/// A coverage session: pings from where we are, recorded until the app stops.
///
/// Session-only, by decision: persisting positions is a privacy commitment the
/// data-safety declaration would have to carry, and the register settled on
/// not carrying it. Nothing here is written to disk; closing the app ends the
/// record, and the screen says so before it starts.
final class CoverageSession extends ChangeNotifier {
  CoverageSession({
    required MeshcoreController mc,
    CoveragePinger? pinger,
    DateTime Function()? clock,
    Random? random,
    this.capacity = 2000,
  })  : _mc = mc,
        _pinger = pinger,
        _clock = clock ?? DateTime.now,
        _pacing = CoveragePacing(clock: clock ?? DateTime.now, random: random);

  final MeshcoreController _mc;
  final CoveragePinger? _pinger;
  final DateTime Function() _clock;
  final CoveragePacing _pacing;

  /// Samples a session keeps. A day of pings at one a minute is well under
  /// this; the cap only stops a stuck loop from growing a list forever.
  final int capacity;

  bool _running = false;
  bool _busy = false;
  final List<CoverageSample> _samples = <CoverageSample>[];
  int _tried = 0;
  int _answeredPings = 0;
  int _unmatched = 0;
  CoveragePacingRefusal? _lastRefusal;

  bool get running => _running;
  bool get busy => _busy;
  List<CoverageSample> get samples =>
      List<CoverageSample>.unmodifiable(_samples);

  /// Pings attempted, and how many of them produced any answer. The
  /// denominator is what was tried, never what exists
  /// (`meshmore-telemetry-coverage-spec.md` §10).
  int get tried => _tried;
  int get answeredPings => _answeredPings;

  /// Replies the correlation could not attribute. The current ping path
  /// matches on an exact tag, so this can only rise if a pinger reports one;
  /// it is shown rather than hidden, because an unattributable reply is still
  /// evidence that something heard us.
  int get unmatched => _unmatched;
  void countUnmatched() {
    _unmatched++;
    notifyListeners();
  }

  CoveragePacingRefusal? get lastRefusal => _lastRefusal;

  /// The cell we are in, or null without a fix.
  String? get cell {
    final OwnLocation? own = _mc.ownLocation;
    if (own == null) return null;
    return geohash6(own.latitude, own.longitude);
  }

  void start() {
    if (_running) return;
    _running = true;
    _pacing.reset();
    notifyListeners();
  }

  void stop() {
    if (!_running) return;
    _running = false;
    notifyListeners();
  }

  /// Clears the record. The session keeps running, because a user starting
  /// over does not want the pacing reset as well.
  void clearSamples() {
    _samples.clear();
    _tried = 0;
    _answeredPings = 0;
    _unmatched = 0;
    notifyListeners();
  }

  /// Sends one ping if pacing allows it.
  ///
  /// [manual] is the user's "ping now": it overrides the cell limit once an
  /// hour and never the thirty-second floor.
  Future<CoveragePingOutcome> ping({bool manual = false}) async {
    if (!_running || _busy) return CoveragePingOutcome.refused;
    final OwnLocation? own = _mc.ownLocation;
    final String? c = cell;
    if (own == null || c == null) {
      _lastRefusal = null;
      notifyListeners();
      return CoveragePingOutcome.noFix;
    }
    final CoveragePacingRefusal? refusal = _pacing.check(cell: c, manual: manual);
    if (refusal != null) {
      _lastRefusal = refusal;
      notifyListeners();
      return CoveragePingOutcome.refused;
    }
    final CoveragePinger? pinger = _pinger;
    if (pinger == null) return CoveragePingOutcome.failed;
    _lastRefusal = null;
    _busy = true;
    notifyListeners();
    try {
      if (!_pacing.markPinged(cell: c, manual: manual)) {
        return CoveragePingOutcome.refused;
      }
      _tried++;
      final DateTime at = _clock();
      final List<CoverageResponder> responders = await pinger();
      for (final CoverageResponder r in responders) {
        _add(CoverageSample(
          lat: own.latitude,
          lon: own.longitude,
          at: at,
          answered: true,
          responderKey: r.key,
          rssi: r.rssi,
          snr: r.snr,
          hops: r.hops,
        ));
      }
      if (responders.isEmpty) {
        // One unanswered sample per ping: "nobody answered here" is one
        // observation, not zero observations.
        _add(CoverageSample(
          lat: own.latitude,
          lon: own.longitude,
          at: at,
          answered: false,
        ));
      } else {
        _answeredPings++;
      }
      return CoveragePingOutcome.sent;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void _add(CoverageSample s) {
    _samples.add(s);
    if (_samples.length > capacity) {
      _samples.removeRange(0, _samples.length - capacity);
    }
  }

  /// When this cell next allows a ping, for the countdown.
  DateTime? get nextAllowedAt {
    final String? c = cell;
    if (c == null) return null;
    return _pacing.nextAllowedAt(c);
  }

  /// The cells seen so far, scored, with their sample counts.
  List<CoverageCellSummary> summaries({Set<String> blockedKeys = const <String>{}}) {
    final Map<String, List<CoverageSample>> byCell =
        <String, List<CoverageSample>>{};
    for (final CoverageSample s in _samples) {
      (byCell[s.cell] ??= <CoverageSample>[]).add(s);
    }
    final DateTime now = _clock();
    return <CoverageCellSummary>[
      for (final List<CoverageSample> rows in byCell.values)
        summariseCell(rows, now: now, blockedKeys: blockedKeys),
    ]..sort((CoverageCellSummary a, CoverageCellSummary b) =>
        b.samples.compareTo(a.samples));
  }

  /// Observed-only edges: a responder that actually answered.
  List<CoverageEdge> edges({Set<String> blockedKeys = const <String>{}}) =>
      observedEdges(_samples, blockedKeys: blockedKeys);

  /// How many responders are hidden by the block list. Counted so the map does
  /// not silently understate the mesh.
  int hiddenCount({Set<String> blockedKeys = const <String>{}}) {
    int n = 0;
    for (final CoverageCellSummary c in summaries(blockedKeys: blockedKeys)) {
      n += c.hidden;
    }
    return n;
  }
}
