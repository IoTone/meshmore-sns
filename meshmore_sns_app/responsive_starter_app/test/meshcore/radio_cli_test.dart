// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_transport.dart';

/// `CMD_RUN_CLI_COMMAND` (0x42) is the radio's whole shell, and the app may only
/// reach it through the closed whitelist in `packages/meshcore` (D8.24): two
/// commands ship — `get/set buzzer` and `get/set vibration` — because the
/// `notify.<selector>` grammar is not written down in the firmware this app is
/// built against.
///
/// The wire makes the answer awkward, and these cases are about that rather
/// than about the CLI itself: the text arrives as zero or more
/// `RESP_CODE_CLI_REPLY` (0x1D) frames tagged with a two-character prefix, then
/// a bare `OK` or `ERR` that carries no tag at all. So the prefix attributes the
/// text, the ledger attributes the verdict, and "the radio said nothing" must
/// stay a different outcome from "the radio refused".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  /// Let the controller finish what a frame started.
  ///
  /// Event-loop turns alone are enough when this file runs by itself, but the
  /// suite runs test files in parallel and the turns can stretch under load:
  /// this case then emitted its answer before the send that registers the
  /// marker for it, and timed out. One turn of real time removes the race
  /// without making the assertion any weaker.
  Future<void> settle() async {
    for (int i = 0; i < 8; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }

  Future<MeshcoreController> connected(FakeMeshcoreTransport fake) async {
    final MeshcoreController mc =
        MeshcoreController(transportFactory: () async => fake);
    await mc.connect();
    fake.emit(selfInfoFrame());
    await settle();
    return mc;
  }

  /// `RESP_CODE_CLI_REPLY` (0x1D): opcode + the line, including the tag the
  /// radio echoes back.
  Uint8List cliReply(String line) => Uint8List.fromList(<int>[
        0x1D,
        ...line.codeUnits,
      ]);

  Uint8List ok() => Uint8List.fromList(<int>[0x00]);
  Uint8List err(int code) => Uint8List.fromList(<int>[0x01, code]);

  test('the reply text and the verdict arrive separately and both are read',
      () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = await connected(fake);

    final Future<RadioCliResult> run =
        mc.runRadioCli(const BuzzerCommand.read(), correlation: 'b1');
    await settle();
    // The frame that went out is the typed command, not a string: opcode 0x42
    // followed by the tag, a bar, and the fixed text.
    final Uint8List sent = fake.sent.last;
    expect(sent.first, 0x42);
    expect(String.fromCharCodes(sent.skip(1)), 'b1|get buzzer');

    fake.emit(cliReply('b1buzzer: on'));
    fake.emit(cliReply('b1'));
    fake.emit(ok());
    final RadioCliResult r = await run;

    expect(r, isA<RadioCliAnswered>());
    expect(r.text, 'buzzer: on',
        reason: 'the tag belongs to the wire, not to the radio\'s words');
    expect((r as RadioCliAnswered).onOff, isTrue);
    expect(mc.cliBusy, isFalse, reason: 'the slot must be free again');
    mc.dispose();
  });

  test('a line carrying another prefix is not this command\'s answer',
      () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = await connected(fake);

    final Future<RadioCliResult> run =
        mc.runRadioCli(const VibrationCommand.read(), correlation: 'v1');
    await settle();
    // A late line from a different request, then this one's own.
    fake.emit(cliReply('b1buzzer: off'));
    fake.emit(cliReply('v1vibration: on'));
    fake.emit(ok());
    final RadioCliResult r = await run;

    expect(r.text, 'vibration: on');
    expect(r.text, isNot(contains('buzzer')));
    mc.dispose();
  });

  test('a refusal keeps the firmware\'s code and whatever text came with it',
      () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = await connected(fake);

    final Future<RadioCliResult> run =
        mc.runRadioCli(const BuzzerCommand(true), correlation: 'b2');
    await settle();
    fake.emit(cliReply('b2set buzzer on'));
    fake.emit(err(4));
    final RadioCliResult r = await run;

    expect(r, isA<RadioCliRejected>());
    expect((r as RadioCliRejected).code, 4,
        reason: 'ERR_CODE_BAD_STATE is what the firmware sends for a refused '
            'command, and the code is the actionable half');
    expect(r.text, 'set buzzer on');
    expect(mc.cliBusy, isFalse);
    mc.dispose();
  });

  test(
      'silence inside the window is its own outcome, with the text that did '
      'arrive', () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = await connected(fake);

    final RadioCliResult r = await mc.runRadioCli(
      const BuzzerCommand.read(),
      correlation: 'b3',
      timeout: const Duration(milliseconds: 40),
    );
    expect(r, isA<RadioCliSilent>());
    expect(r.text, isEmpty);
    expect(mc.cliBusy, isFalse,
        reason: 'a timed-out command must not hold the slot');
    mc.dispose();
  });

  test('a second command while one is waiting is refused, not queued',
      () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = await connected(fake);

    final Future<RadioCliResult> first =
        mc.runRadioCli(const BuzzerCommand.read(), correlation: 'b4');
    await settle();
    final RadioCliResult second =
        await mc.runRadioCli(const VibrationCommand.read(), correlation: 'v4');
    expect(second, isA<RadioCliBusy>());

    fake.emit(cliReply('b4buzzer: off'));
    fake.emit(ok());
    expect(await first, isA<RadioCliAnswered>());
    mc.dispose();
  });

  test('a command with no link is not sent at all', () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport();
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => fake,
    );
    final int before = fake.sent.length;
    final RadioCliResult r = await mc.runRadioCli(const BuzzerCommand.read());
    expect(r, isA<RadioCliUnavailable>());
    expect(fake.sent.length, before);
    mc.dispose();
  });

  test('only the whitelist can build a frame, so there is no text to send', () {
    // The type system is the guarantee: every `RadioCliCommand` is a sealed
    // subclass with fixed text, and `resolveRadioCliCommand` refuses anything
    // with shell syntax or `remote`. This case pins the two that ship and one
    // refusal, as the wire-level counterpart of the UI test that asserts there
    // is no text field.
    expect(const BuzzerCommand(true).cliText, 'set buzzer on');
    expect(const VibrationCommand(false).cliText, 'set vibration off');
    expect(
        resolveRadioCliCommand('remote set buzzer on'), isA<RadioCliRefused>());
    expect(resolveRadioCliCommand('set buzzer on; factory_reset'),
        isA<RadioCliRefused>());
  });
}
