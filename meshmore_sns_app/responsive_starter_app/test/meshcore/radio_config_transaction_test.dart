// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/meshcore/radio_config_transaction.dart';
import 'package:meshcore/meshcore.dart';

const RadioOperatingPoint _target = RadioOperatingPoint(
  frequencyMhz: 910.525,
  bandwidthKhz: 62.5,
  spreadingFactor: 7,
  codingRate: 5,
  txPowerDbm: 22,
  pathHashMode: 2,
);

/// Records every frame the transaction sends and answers from a script.
class _ScriptedRadio {
  _ScriptedRadio(this.answers);

  final List<RadioAnswer> answers;
  final List<int> opcodes = <int>[];

  Future<RadioAnswer> send(Uint8List frame) async {
    opcodes.add(frame[0]);
    final RadioAnswer a =
        answers.length > opcodes.length - 1 ? answers[opcodes.length - 1]
            : const RadioAnswer.accepted();
    return a;
  }
}

void main() {
  test('the transaction writes the four stranding parameters first, in order',
      () async {
    final _ScriptedRadio radio = _ScriptedRadio(<RadioAnswer>[]);
    final RadioConfigOutcome out =
        await RadioConfigTransaction.run(_target, radio.send);
    expect(out.isApplied, isTrue);
    expect(radio.opcodes, <int>[
      MeshcoreCommand.setRadioParams.code,
      MeshcoreCommand.setRadioTxPower.code,
      MeshcoreCommand.setPathHashMode.code,
    ]);
  });

  test('a refusal at the parameters leaves the later steps unsent', () async {
    final _ScriptedRadio radio = _ScriptedRadio(<RadioAnswer>[
      const RadioAnswer.refused(7),
    ]);
    final RadioConfigOutcome out =
        await RadioConfigTransaction.run(_target, radio.send);
    expect(out.isApplied, isFalse);
    expect(out.failedStep, RadioConfigStep.params);
    expect(out.answer!.errorCode, 7);
    expect(radio.opcodes, <int>[MeshcoreCommand.setRadioParams.code]);
  });

  test('a refusal of the path-hash size names that step, not the write before',
      () async {
    final _ScriptedRadio radio = _ScriptedRadio(<RadioAnswer>[
      const RadioAnswer.accepted(),
      const RadioAnswer.accepted(),
      const RadioAnswer.refused(2),
    ]);
    final RadioConfigOutcome out =
        await RadioConfigTransaction.run(_target, radio.send);
    expect(out.failedStep, RadioConfigStep.pathHash);
    expect(out.answer!.errorCode, 2);
    expect(radio.opcodes.length, 3);
  });

  test('silence is not acceptance, and it stops the transaction', () async {
    final _ScriptedRadio radio = _ScriptedRadio(<RadioAnswer>[
      const RadioAnswer.accepted(),
      const RadioAnswer.silent(),
    ]);
    final RadioConfigOutcome out =
        await RadioConfigTransaction.run(_target, radio.send);
    expect(out.isApplied, isFalse);
    expect(out.failedStep, RadioConfigStep.txPower);
    expect(out.answer!.status, RadioAnswerStatus.noAnswer);
    expect(radio.opcodes.length, 2,
        reason: 'a terminal answer, even a silent one, ends the write');
  });

  test('an unsupported command is reported as such, not as a bad argument',
      () {
    final RadioAnswer a =
        RadioAnswer.refused(MeshcoreErrorCode.unsupportedCmd.code);
    expect(a.isUnsupported, isTrue);
    expect(const RadioAnswer.refused(7).isUnsupported, isFalse);
  });

  test('an operating point needs both halves, because the hash size is not '
      'in the self info', () {
    final SelfInfo self = SelfInfo(
      advType: 1,
      txPowerDbm: 22,
      maxTxPowerDbm: 30,
      publicKey: _emptyKey,
      latitude: 0,
      longitude: 0,
      multiAcks: 0,
      advertLocPolicy: 0,
      telemetryModeRaw: 0,
      manualAddContacts: false,
      frequencyMhz: 910.525,
      bandwidthKhz: 62.5,
      spreadingFactor: 7,
      codingRate: 5,
      name: 'radio',
    );
    expect(RadioOperatingPoint.known(self, null), isNull);
  });

  test('the point survives a round trip through the record on disk', () {
    final Map<String, Object?> json = _target.toJson();
    expect(RadioOperatingPoint.fromJson(json), _target);
    expect(RadioOperatingPoint.fromJson(<String, Object?>{'freqMhz': 1}),
        isNull);
  });
}

final Uint8List _emptyKey = Uint8List(32);
