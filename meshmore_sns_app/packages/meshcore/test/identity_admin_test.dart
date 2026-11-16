// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
//
// Identity, signing, device admin, tuning and auto-add. Firmware
// companion-v1.17.1 (d929643), `examples/companion_radio/MyMesh.cpp`:
//
//   CMD_REBOOT 19 :1474            CMD_GET_TUNING_PARAMS 43 :1443
//   CMD_EXPORT_PRIVATE_KEY 23 :1490 CMD_IMPORT_PRIVATE_KEY 24 :1499
//   CMD_SIGN_START 33 :1739        CMD_SIGN_DATA 34 :1751
//   CMD_SIGN_FINISH 35 :1759       CMD_SET_DEVICE_PIN 37 :1797
//   CMD_FACTORY_RESET 51 :1923     CMD_SET_AUTOADD_CONFIG 58 :1981
//   CMD_GET_AUTOADD_CONFIG 59 :1988  RESP_CODE_DISABLED :160-163

import 'dart:io';
import 'dart:typed_data';

import 'package:meshcore/meshcore.dart';
import 'package:test/test.dart';

Uint8List _h(String s) {
  final String c = s.replaceAll(' ', '');
  final Uint8List out = Uint8List(c.length ~/ 2);
  for (int i = 0; i < out.length; i++) {
    out[i] = int.parse(c.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

String _x(Uint8List b) =>
    b.map((int v) => v.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('reboot and factory reset', () {
    test('reboot is the opcode plus the ASCII word (MyMesh.cpp:1474)', () {
      expect(_x(MeshcoreFrameCodec.reboot()), '13726562 6f6f74'.replaceAll(' ', ''));
    });
    test('factory reset is the opcode plus "reset" (MyMesh.cpp:1923)', () {
      expect(_x(MeshcoreFrameCodec.factoryReset(confirmed: true)),
          '337265736574');
    });
    test('factory reset refuses to build without confirmation', () {
      expect(() => MeshcoreFrameCodec.factoryReset(confirmed: false),
          throwsArgumentError);
    });
  });

  group('private key', () {
    test('export is a bare opcode', () {
      expect(_x(MeshcoreFrameCodec.exportPrivateKey()), '17');
    });
    test('reply 0x0E carries 64 bytes and redacts itself when printed', () {
      final String key = 'ab' * 64;
      final MeshcoreInbound r = MeshcoreFrameCodec.decode(_h('0e$key'));
      expect(_x((r as PrivateKeyFrame).privateKey), key);
      expect(r.toString(), isNot(contains('abab')));
      expect(r.toString(), contains('redacted'));
    });
    test('a 63-byte key is a decode failure', () {
      expect(MeshcoreFrameCodec.decode(_h('0e${'ab' * 63}')),
          isA<DecodeFailure>());
    });
    test('RESP_CODE_DISABLED (0x0F) is its own frame, not an error', () {
      // Firmware without ENABLE_PRIVATE_KEY_EXPORT/IMPORT, MyMesh.cpp:1495.
      expect(MeshcoreFrameCodec.decode(_h('0f')), isA<DisabledFrame>());
    });
    test('import needs 64 bytes and explicit confirmation', () {
      final Uint8List f = MeshcoreFrameCodec.importPrivateKey(
          Uint8List(64),
          confirmed: true);
      expect(f.length, 65);
      expect(f[0], 0x18);
      expect(
          () => MeshcoreFrameCodec.importPrivateKey(Uint8List(64),
              confirmed: false),
          throwsArgumentError);
      expect(
          () => MeshcoreFrameCodec.importPrivateKey(Uint8List(63),
              confirmed: true),
          throwsArgumentError);
      expect(
          () => MeshcoreFrameCodec.importPrivateKey(Uint8List(65),
              confirmed: true),
          throwsArgumentError);
    });
  });

  group('signing', () {
    test('start and finish are bare opcodes', () {
      expect(_x(MeshcoreFrameCodec.signStart()), '21');
      expect(_x(MeshcoreFrameCodec.signFinish()), '23');
    });
    test('start reply: reserved byte then the 8 KiB limit', () {
      // 8192 = 0x2000 -> 00 20 00 00 little-endian (MyMesh.cpp:1740-1743)
      final MeshcoreInbound r = MeshcoreFrameCodec.decode(_h('13 00 00200000'));
      expect((r as SignStartFrame).maxLength, 8192);
      expect(r.maxLength, kMaxSignDataLen);
    });
    test('start reply truncated', () {
      expect(MeshcoreFrameCodec.decode(_h('13 00 0020')),
          isA<DecodeFailure>());
    });
    test('data chunk: 1..175 bytes', () {
      expect(_x(MeshcoreFrameCodec.signData(_h('aabb'))), '22aabb');
      expect(MeshcoreFrameCodec.signData(Uint8List(175)).length, 176);
      expect(() => MeshcoreFrameCodec.signData(Uint8List(0)),
          throwsArgumentError);
      expect(() => MeshcoreFrameCodec.signData(Uint8List(176)),
          throwsArgumentError);
    });
    test('signDataFrames splits 400 bytes as 175 + 175 + 50', () {
      final List<Uint8List> f =
          MeshcoreFrameCodec.signDataFrames(Uint8List(400));
      expect(f.map((Uint8List b) => b.length - 1).toList(), <int>[175, 175, 50]);
      expect(f.every((Uint8List b) => b[0] == 0x22), isTrue);
    });
    test('signDataFrames covers an exact multiple without an empty tail', () {
      final List<Uint8List> f =
          MeshcoreFrameCodec.signDataFrames(Uint8List(350));
      expect(f.length, 2);
    });
    test('signDataFrames accepts the 8 KiB buffer and refuses one byte more',
        () {
      expect(MeshcoreFrameCodec.signDataFrames(Uint8List(8192)), isNotEmpty);
      expect(() => MeshcoreFrameCodec.signDataFrames(Uint8List(8193)),
          throwsArgumentError);
      expect(() => MeshcoreFrameCodec.signDataFrames(Uint8List(0)),
          throwsArgumentError);
    });
    test('signature reply is 64 bytes (MyMesh.cpp:1766-1767)', () {
      final MeshcoreInbound r =
          MeshcoreFrameCodec.decode(_h('14${'cd' * 64}'));
      expect((r as SignatureFrame).signature.length, 64);
      expect(MeshcoreFrameCodec.decode(_h('14${'cd' * 63}')),
          isA<DecodeFailure>());
    });
  });

  group('setDevicePin (0x25)', () {
    test('little-endian u32', () {
      // 123456 = 0x0001E240
      expect(_x(MeshcoreFrameCodec.setDevicePin(123456)), '2540e20100');
    });
    test('0 clears the PIN', () {
      expect(_x(MeshcoreFrameCodec.setDevicePin(0)), '2500000000');
    });
    test('boundaries of the six-digit range (MyMesh.cpp:1806)', () {
      MeshcoreFrameCodec.setDevicePin(100000);
      MeshcoreFrameCodec.setDevicePin(999999);
      for (final int bad in <int>[1, 99999, 1000000, -1]) {
        expect(() => MeshcoreFrameCodec.setDevicePin(bad), throwsArgumentError,
            reason: '$bad');
      }
    });
  });

  group('tuning params', () {
    test('request is a bare opcode', () {
      expect(_x(MeshcoreFrameCodec.getTuningParams()), '2b');
    });
    test('reply is two u32 scaled by 1000 (MyMesh.cpp:1443-1450)', () {
      // rx 1000 -> 1.0 s, af 500 -> 0.5
      final TuningParams p = (MeshcoreFrameCodec.decode(
              _h('17 e8030000 f4010000')) as TuningParamsFrame)
          .params;
      expect(p.rxDelayBaseSeconds, 1.0);
      expect(p.airtimeFactor, 0.5);
    });
    test('round-trips the existing setTuningParams encoder', () {
      final Uint8List set = MeshcoreFrameCodec.setTuningParams(
          rxDelayBaseSeconds: 2.5, airtimeFactor: 3.0);
      final Uint8List reply = Uint8List.fromList(<int>[0x17, ...set.sublist(1)]);
      final TuningParams p =
          (MeshcoreFrameCodec.decode(reply) as TuningParamsFrame).params;
      expect(p.rxDelayBaseSeconds, 2.5);
      expect(p.airtimeFactor, 3.0);
    });
    test('truncated reply', () {
      expect(MeshcoreFrameCodec.decode(_h('17 e8030000')),
          isA<DecodeFailure>());
    });
  });

  group('auto-add config', () {
    test('get is a bare opcode', () {
      expect(_x(MeshcoreFrameCodec.getAutoAddConfig()), '3b');
    });
    test('set without max_hops leaves the stored value alone', () {
      // Firmware only touches max_hops when len >= 3 (MyMesh.cpp:1983).
      expect(_x(MeshcoreFrameCodec.setAutoAddConfig(0x1E)), '3a1e');
    });
    test('set with max_hops', () {
      expect(_x(MeshcoreFrameCodec.setAutoAddConfig(0x06, maxHops: 5)),
          '3a0605');
    });
    test('max_hops 64 passes, 65 is refused (firmware clamps silently)', () {
      MeshcoreFrameCodec.setAutoAddConfig(0, maxHops: 64);
      expect(() => MeshcoreFrameCodec.setAutoAddConfig(0, maxHops: 65),
          throwsArgumentError);
      expect(() => MeshcoreFrameCodec.setAutoAddConfig(0, maxHops: -1),
          throwsArgumentError);
    });
    test('flags must fit a byte', () {
      expect(() => MeshcoreFrameCodec.setAutoAddConfig(256),
          throwsArgumentError);
      expect(() => MeshcoreFrameCodec.setAutoAddConfig(-1),
          throwsArgumentError);
    });
    test('reply exposes the named bits (MyMesh.cpp:140-146)', () {
      final AutoAddConfig c =
          (MeshcoreFrameCodec.decode(_h('19 0f 03')) as AutoAddConfigFrame)
              .config;
      expect(c.overwriteOldest, isTrue);
      expect(c.chat, isTrue);
      expect(c.repeater, isTrue);
      expect(c.roomServer, isTrue);
      expect(c.sensor, isFalse);
      expect(c.maxHops, 3);
    });
    test('reply truncated', () {
      expect(MeshcoreFrameCodec.decode(_h('19 0f')), isA<DecodeFailure>());
    });
  });

  group('opcode registry', () {
    test('the 21 new opcodes carry the firmware numbers', () {
      final Map<MeshcoreCommand, int> expected = <MeshcoreCommand, int>{
        MeshcoreCommand.shareContact: 16,
        MeshcoreCommand.exportContact: 17,
        MeshcoreCommand.importContact: 18,
        MeshcoreCommand.reboot: 19,
        MeshcoreCommand.exportPrivateKey: 23,
        MeshcoreCommand.importPrivateKey: 24,
        MeshcoreCommand.sendLogin: 26,
        MeshcoreCommand.hasConnection: 28,
        MeshcoreCommand.logout: 29,
        MeshcoreCommand.getContactByKey: 30,
        MeshcoreCommand.signStart: 33,
        MeshcoreCommand.signData: 34,
        MeshcoreCommand.signFinish: 35,
        MeshcoreCommand.setDevicePin: 37,
        MeshcoreCommand.getAdvertPath: 42,
        MeshcoreCommand.getTuningParams: 43,
        MeshcoreCommand.factoryReset: 51,
        MeshcoreCommand.sendPathDiscoveryReq: 52,
        MeshcoreCommand.sendAnonReq: 57,
        MeshcoreCommand.setAutoAddConfig: 58,
        MeshcoreCommand.getAutoAddConfig: 59,
      };
      expected.forEach((MeshcoreCommand c, int n) => expect(c.code, n));
      expect(expected.length, 21);
    });

    test('no two command constants share an opcode, nor two responses', () {
      final String src =
          File('lib/src/codec/constants.dart').readAsStringSync();
      for (final String kind in <String>['MeshcoreCommand', 'MeshcoreResponse']) {
        final RegExp re = RegExp(
            r'static const ' + kind + r' (\w+)\s*=\s*' + kind + r'\(0x([0-9A-Fa-f]+)\)');
        final Map<int, String> seen = <int, String>{};
        for (final RegExpMatch m in re.allMatches(src)) {
          final int code = int.parse(m.group(2)!, radix: 16);
          expect(seen.containsKey(code), isFalse,
              reason: '$kind ${m.group(1)} collides with ${seen[code]} (0x${code.toRadixString(16)})');
          seen[code] = m.group(1)!;
        }
        expect(seen.length, greaterThan(20), reason: '$kind regex matched');
      }
    });
  });
}
