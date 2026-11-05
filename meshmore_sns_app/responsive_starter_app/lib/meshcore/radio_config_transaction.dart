// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:meshcore/meshcore.dart';

/// The four parameters that can strand a radio plus the two that cannot.
///
/// Frequency, bandwidth, spreading factor and coding rate decide whether this
/// radio can hear its own mesh: get them wrong and the node is alone in the
/// band with no way back except a cable. TX power cannot strand it (a quiet
/// radio still receives), and the path-hash size only decides what this radio
/// stamps on what it sends — forwarders honour each packet's own length
/// (`Mesh.cpp:89`), so nodes need not agree on it. So all four stranding
/// parameters travel as ONE transaction, and a refusal anywhere stops it.
class RadioOperatingPoint {
  const RadioOperatingPoint({
    required this.frequencyMhz,
    required this.bandwidthKhz,
    required this.spreadingFactor,
    required this.codingRate,
    required this.txPowerDbm,
    required this.pathHashMode,
  });

  final double frequencyMhz;
  final double bandwidthKhz;
  final int spreadingFactor;
  final int codingRate;
  final int txPowerDbm;

  /// 0 = 1 byte, 1 = 2 bytes, 2 = 4 bytes. Reported by `RESP_CODE_DEVICE_INFO`
  /// as its last byte (v10+, `MyMesh.cpp:1034-1050`).
  final int pathHashMode;

  /// What the radio is running now, or null when either half is unknown.
  ///
  /// The path-hash mode is the reason this can refuse: it arrives in the
  /// device info, not in the self info, so a radio that has not answered a
  /// device query yet has no recorded value to come back to.
  static RadioOperatingPoint? known(SelfInfo? self, DeviceInfo? device) {
    if (self == null || device == null) return null;
    return RadioOperatingPoint(
      frequencyMhz: self.frequencyMhz,
      bandwidthKhz: self.bandwidthKhz,
      spreadingFactor: self.spreadingFactor,
      codingRate: self.codingRate,
      txPowerDbm: self.txPowerDbm,
      pathHashMode: device.pathHashMode,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'freqMhz': frequencyMhz,
        'bwKhz': bandwidthKhz,
        'sf': spreadingFactor,
        'cr': codingRate,
        'txDbm': txPowerDbm,
        'pathHash': pathHashMode,
      };

  static RadioOperatingPoint? fromJson(Map<String, Object?> j) {
    final Object? f = j['freqMhz'];
    final Object? b = j['bwKhz'];
    final Object? sf = j['sf'];
    final Object? cr = j['cr'];
    final Object? tx = j['txDbm'];
    final Object? ph = j['pathHash'];
    if (f is! num || b is! num || sf is! int || cr is! int || tx is! int || ph is! int) {
      return null;
    }
    return RadioOperatingPoint(
      frequencyMhz: f.toDouble(),
      bandwidthKhz: b.toDouble(),
      spreadingFactor: sf,
      codingRate: cr,
      txPowerDbm: tx,
      pathHashMode: ph,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RadioOperatingPoint &&
      other.frequencyMhz == frequencyMhz &&
      other.bandwidthKhz == bandwidthKhz &&
      other.spreadingFactor == spreadingFactor &&
      other.codingRate == codingRate &&
      other.txPowerDbm == txPowerDbm &&
      other.pathHashMode == pathHashMode;

  @override
  int get hashCode => Object.hash(frequencyMhz, bandwidthKhz,
      spreadingFactor, codingRate, txPowerDbm, pathHashMode);

  @override
  String toString() => 'RadioOperatingPoint(${frequencyMhz}MHz, '
      '${bandwidthKhz}kHz, SF$spreadingFactor, CR$codingRate, '
      '${txPowerDbm}dBm, pathHash$pathHashMode)';
}

/// The three writes the operating point is made of, and the order they go in.
///
/// The order is the safety property, not a convention: the stranding tuple
/// goes first so an outright refusal never leaves a half-written radio, power
/// second because a refused power still transmits at the old value, and the
/// path-hash size last because it changes nothing about whether this radio can
/// be reached.
enum RadioConfigStep { params, txPower, pathHash }

/// What the radio answered to one step.
enum RadioAnswerStatus { ok, refused, noAnswer }

class RadioAnswer {
  const RadioAnswer.accepted()
      : status = RadioAnswerStatus.ok,
        errorCode = null;

  /// A refusal. [errorCode] is null when the radio sent a bare `ERR` with no
  /// code byte, which says "refused" and nothing more.
  const RadioAnswer.refused(this.errorCode)
      : status = RadioAnswerStatus.refused;

  const RadioAnswer.silent()
      : status = RadioAnswerStatus.noAnswer,
        errorCode = null;

  final RadioAnswerStatus status;

  /// The radio's `ERR_CODE_*` for a refusal, when it sent one.
  final int? errorCode;

  bool get isAccepted => status == RadioAnswerStatus.ok;

  /// The firmware does not have this command at all, as opposed to refusing
  /// this particular request (`ERR_CODE_UNSUPPORTED_CMD`).
  bool get isUnsupported =>
      status == RadioAnswerStatus.refused &&
      errorCode == MeshcoreErrorCode.unsupportedCmd.code;

  @override
  String toString() => 'RadioAnswer(${status.name}'
      '${errorCode == null ? '' : ', err $errorCode'})';
}

/// One transaction's result: either every step applied, or the step that did
/// not and why. The steps after a refusal were not sent.
class RadioConfigOutcome {
  const RadioConfigOutcome.applied(this.target)
      : failedStep = null,
        answer = null;

  const RadioConfigOutcome.refused(
      this.target, RadioConfigStep this.failedStep, RadioAnswer this.answer);

  final RadioOperatingPoint target;
  final RadioConfigStep? failedStep;
  final RadioAnswer? answer;

  bool get isApplied => failedStep == null;
}

/// Applies an operating point as one ordered transaction.
///
/// The transaction writes nothing itself: [send] is the app's awaitable
/// command path, which returns the radio's own answer rather than the moment
/// the bytes were accepted. That is the whole point — the previous code
/// reported "sent" for a command the radio had refused.
abstract final class RadioConfigTransaction {
  static const List<RadioConfigStep> order = <RadioConfigStep>[
    RadioConfigStep.params,
    RadioConfigStep.txPower,
    RadioConfigStep.pathHash,
  ];

  /// The frame for [step]. Each of the three is answered with a bare `OK` or
  /// `ERR(ERR_CODE_ILLEGAL_ARG)` (`MyMesh.cpp:1386-1478`).
  static Uint8List frameFor(RadioConfigStep step, RadioOperatingPoint p) =>
      switch (step) {
        RadioConfigStep.params => MeshcoreFrameCodec.setRadioParams(RadioParams(
            frequencyMhz: p.frequencyMhz,
            bandwidthKhz: p.bandwidthKhz,
            spreadingFactor: p.spreadingFactor,
            codingRate: p.codingRate,
          )),
        RadioConfigStep.txPower =>
          MeshcoreFrameCodec.setRadioTxPower(p.txPowerDbm),
        RadioConfigStep.pathHash =>
          MeshcoreFrameCodec.setPathHashMode(p.pathHashMode),
      };

  static Future<RadioConfigOutcome> run(
    RadioOperatingPoint target,
    Future<RadioAnswer> Function(Uint8List frame) send,
  ) async {
    for (final RadioConfigStep step in order) {
      final RadioAnswer answer = await send(frameFor(step, target));
      if (!answer.isAccepted) {
        return RadioConfigOutcome.refused(target, step, answer);
      }
    }
    return RadioConfigOutcome.applied(target);
  }
}
