// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT

/// The longest the app waits for a link teardown to finish.
///
/// `BleConnector` gives each of its own one-shot link operations five seconds
/// (`ble_connector.dart`), and a close that outlasts that is not going to
/// finish: the GATT is already gone or the phone's stack has stopped answering.
/// Waiting longer only keeps `_connecting` set, which is what made the screen
/// sit on "handshaking" with nothing happening behind it.
const Duration kLinkCloseTimeout = Duration(seconds: 5);

/// The longest the app waits for a transport to be acquired.
///
/// `BleConnector`'s own budget is a 15 s scan plus a 12 s connect, so 30 s is
/// the first round number that cannot abort a legitimate auto-connect. It is a
/// backstop against a platform call that never resolves, not a scan deadline:
/// every path that can finish quickly still does.
const Duration kLinkOpenTimeout = Duration(seconds: 30);

/// Which half of acquiring a link ran out of time.
enum LinkStage {
  /// Closing the transport the previous attempt left behind.
  close,

  /// Opening a new transport: scan, connect, discover.
  open,
}

/// A link operation that did not finish inside the wait the app allows.
///
/// Typed rather than a bare timeout so the screen can say which
/// half stalled, and so `Failure.from` can recognise it: a hung close and a
/// hung scan look identical in a log line and mean different things to the
/// person holding the phone.
class LinkAcquireTimeout implements Exception {
  const LinkAcquireTimeout(this.stage, this.waited);

  final LinkStage stage;
  final Duration waited;

  @override
  String toString() => 'LinkAcquireTimeout: ${stage.name} did not finish in '
      '${waited.inSeconds}s';
}
