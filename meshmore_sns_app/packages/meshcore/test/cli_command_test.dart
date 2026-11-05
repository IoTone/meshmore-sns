// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT

import 'package:meshcore/meshcore.dart';
import 'package:test/test.dart';

RadioCliResolution _resolve(String text) => resolveRadioCliCommand(text);

void main() {
  group('the whitelist accepts only typed commands', () {
    test('get buzzer is a read, not a toggle', () {
      final RadioCliResolution r = _resolve('get buzzer');
      expect(r, isA<RadioCliAccepted>());
      expect((r as RadioCliAccepted).command, isA<BuzzerCommand>());
      expect((r.command as BuzzerCommand).enabled, isNull);
      expect(r.command.cliText, 'get buzzer');
    });

    test('set vibration off carries the state explicitly', () {
      final RadioCliResolution r = _resolve('set vibration off');
      expect((r as RadioCliAccepted).command.cliText, 'set vibration off');
      expect((r.command as VibrationCommand).enabled, isFalse);
    });

    test('bytes are the command frame plus the text, and the tag is optional',
        () {
      const BuzzerCommand cmd = BuzzerCommand(true);
      expect(cmd.bytes(), equals(<int>[0x42, ...('set buzzer on'.codeUnits)]));
      expect(cmd.bytes(correlation: 'A7'),
          equals(<int>[0x42, ...('A7|set buzzer on'.codeUnits)]));
      expect(RadioCliCommand.isCorrelationTag('A7'), isTrue);
      expect(RadioCliCommand.isCorrelationTag('A'), isFalse);
      expect(RadioCliCommand.isCorrelationTag('A|'), isFalse);
    });
  });

  group('every refused form is named', () {
    test('raw text with shell syntax cannot chain a second command', () {
      for (final String text in <String>[
        'get buzzer; set leds off',
        'get buzzer | set leds off',
        'get buzzer\nset leds off',
        'get `buzzer`',
        '',
        '   ',
      ]) {
        final RadioCliResolution r = _resolve(text);
        expect((r as RadioCliRefused).reason, RadioCliRefusal.rawTextRejected,
            reason: text);
      }
    });

    test('remote is refused by name, because it acts on another node', () {
      for (final String text in <String>['remote', 'remote set buzzer on']) {
        final RadioCliResolution r = _resolve(text);
        expect((r as RadioCliRefused).reason, RadioCliRefusal.remoteRejected,
            reason: text);
      }
    });

    test('an unmodelled command is unsupported, not malformed', () {
      for (final String text in <String>[
        'get prv.key',
        'erase',
        'reboot',
        'get',
      ]) {
        final RadioCliResolution r = _resolve(text);
        expect((r as RadioCliRefused).reason,
            anyOf(RadioCliRefusal.unsupportedCommand,
                RadioCliRefusal.malformedArgument),
            reason: text);
      }
      expect((_resolve('get prv.key') as RadioCliRefused).reason,
          RadioCliRefusal.unsupportedCommand);
    });

    test('a modelled command with a bad argument is malformed', () {
      for (final String text in <String>[
        'set buzzer',
        'set buzzer yes',
        'set buzzer on off',
        'set vibration 1',
        'get buzzer on',
      ]) {
        final RadioCliResolution r = _resolve(text);
        expect((r as RadioCliRefused).reason, RadioCliRefusal.malformedArgument,
            reason: text);
      }
    });
  });
}
