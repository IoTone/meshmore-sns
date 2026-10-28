// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
//
// Contact lifecycle, advert path, path discovery, login and anonymous
// request. Wire layouts transcribed from the firmware at companion-v1.17.1
// (d929643), `examples/companion_radio/MyMesh.cpp` unless stated:
//
//   CMD_SHARE_CONTACT 16          :1319      CMD_GET_CONTACT_BY_KEY 30  :1331
//   CMD_EXPORT_CONTACT 17         :1339      CMD_IMPORT_CONTACT 18      :1369
//   CMD_SEND_LOGIN 26             :1535      CMD_SEND_ANON_REQ 57       :1557
//   CMD_SEND_PATH_DISCOVERY_REQ 52 :1609     CMD_HAS_CONNECTION 28      :1699
//   CMD_LOGOUT 29                 :1706      CMD_GET_ADVERT_PATH 42     :1851
//   push login  :677-707   push path discovery :762-771
//   push contact deleted :340   push contacts full :348

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

final Uint8List _key = Uint8List.fromList(List<int>.filled(32, 0x01));
final String _keyHex = '01' * 32;

void main() {
  group('keyed commands take exactly 32 bytes', () {
    final Map<String, Uint8List Function(List<int>)> cmds =
        <String, Uint8List Function(List<int>)>{
      '10': MeshcoreFrameCodec.shareContact,
      '1c': MeshcoreFrameCodec.hasConnection,
      '1d': MeshcoreFrameCodec.logout,
      '1e': MeshcoreFrameCodec.getContactByKey,
    };
    cmds.forEach((String op, Uint8List Function(List<int>) f) {
      test('0x$op: opcode + key verbatim', () {
        expect(_x(f(_key)), '$op$_keyHex');
      });
      test('0x$op: 31 and 33 bytes are refused', () {
        // shareContact and getContactByKey have NO length guard in firmware
        // (MyMesh.cpp:1319,1331): a short frame would read stale bytes.
        expect(() => f(Uint8List(31)), throwsArgumentError);
        expect(() => f(Uint8List(33)), throwsArgumentError);
      });
    });
  });

  group('exportContact (0x11)', () {
    test('no key means self: a bare opcode (MyMesh.cpp:1339-1341)', () {
      expect(_x(MeshcoreFrameCodec.exportContact()), '11');
    });
    test('with key: opcode + 32 bytes', () {
      expect(_x(MeshcoreFrameCodec.exportContact(pubKey: _key)), '11$_keyHex');
    });
    test('a partial key is refused: <33 bytes would silently export SELF', () {
      expect(() => MeshcoreFrameCodec.exportContact(pubKey: Uint8List(10)),
          throwsArgumentError);
    });
    test('reply 0x0B carries the advert packet verbatim', () {
      final MeshcoreInbound r =
          MeshcoreFrameCodec.decode(_h('0b 11 22 33 44'));
      expect(r, isA<ExportedContactFrame>());
      expect(_x((r as ExportedContactFrame).advertPacket), '11223344');
    });
    test('bare 0x0B is an empty packet, not a crash', () {
      final MeshcoreInbound r = MeshcoreFrameCodec.decode(_h('0b'));
      expect((r as ExportedContactFrame).advertPacket, isEmpty);
    });
  });

  group('importContact (0x12)', () {
    test('98 bytes is the firmware minimum (len > 2+32+64 incl. opcode)', () {
      final Uint8List f = MeshcoreFrameCodec.importContact(Uint8List(98));
      expect(f.length, 99);
      expect(f[0], 0x12);
    });
    test('97 bytes is refused: the firmware would answer UNSUPPORTED_CMD', () {
      expect(() => MeshcoreFrameCodec.importContact(Uint8List(97)),
          throwsArgumentError);
    });
    test('175 bytes fills a frame, 176 does not', () {
      expect(MeshcoreFrameCodec.importContact(Uint8List(175)).length, 176);
      expect(() => MeshcoreFrameCodec.importContact(Uint8List(176)),
          throwsArgumentError);
    });
  });

  group('sendLogin (0x1A)', () {
    test('opcode + key + password bytes, no terminator', () {
      expect(_x(MeshcoreFrameCodec.sendLogin(_key, 'hello')),
          '1a${_keyHex}68656c6c6f');
    });
    test('an empty password is legal (guest login)', () {
      expect(_x(MeshcoreFrameCodec.sendLogin(_key, '')), '1a$_keyHex');
    });
    test('15 bytes pass, 16 are refused (firmware truncates silently)', () {
      MeshcoreFrameCodec.sendLogin(_key, 'a' * 15);
      expect(() => MeshcoreFrameCodec.sendLogin(_key, 'a' * 16),
          throwsArgumentError);
    });
    test('length is measured in UTF-8 bytes, not characters', () {
      // 8 x U+00E9 is 8 characters but 16 bytes.
      expect(() => MeshcoreFrameCodec.sendLogin(_key, 'é' * 8),
          throwsArgumentError);
    });
    test('an embedded NUL is refused: firmware stops reading there', () {
      expect(() => MeshcoreFrameCodec.sendLogin(_key, 'ab\u0000cd'),
          throwsArgumentError);
    });
  });

  group('login push (0x85 / 0x86)', () {
    test('new-format success carries timestamp, ACL and firmware level', () {
      // MyMesh.cpp:693-702
      final MeshcoreInbound r = MeshcoreFrameCodec.decode(
          _h('85 01 aabbccddeeff d2040000 07 0d'));
      final LoginResult l = (r as LoginResultFrame).result;
      expect(l.success, isTrue);
      expect(l.permissions, 1);
      expect(_x(l.pubKeyPrefix), 'aabbccddeeff');
      expect(l.serverTimestamp, 1234);
      expect(l.aclPermissions, 7);
      expect(l.firmwareLevel, 13);
      expect(l.isLegacy, isFalse);
    });
    test('legacy success is 8 bytes with no extras (MyMesh.cpp:684-689)', () {
      final LoginResult l = (MeshcoreFrameCodec.decode(
              _h('85 00 aabbccddeeff')) as LoginResultFrame)
          .result;
      expect(l.success, isTrue);
      expect(l.isLegacy, isTrue);
      expect(l.serverTimestamp, isNull);
    });
    test('trailing extras of 1..5 bytes are not mistaken for the new format',
        () {
      final LoginResult l = (MeshcoreFrameCodec.decode(
              _h('85 00 aabbccddeeff 01 02 03')) as LoginResultFrame)
          .result;
      expect(l.isLegacy, isTrue);
    });
    test('failure (MyMesh.cpp:703-707)', () {
      final LoginResult l = (MeshcoreFrameCodec.decode(
              _h('86 00 aabbccddeeff')) as LoginResultFrame)
          .result;
      expect(l.success, isFalse);
      expect(l.permissions, 0);
    });
    test('a truncated key prefix is a decode failure, not a throw', () {
      expect(MeshcoreFrameCodec.decode(_h('86 00 aabb')), isA<DecodeFailure>());
      expect(MeshcoreFrameCodec.decode(_h('85')), isA<DecodeFailure>());
    });
  });

  group('getAdvertPath (0x2A) and reply 0x16', () {
    test('request is opcode, reserved 0, 32-byte key', () {
      expect(_x(MeshcoreFrameCodec.getAdvertPath(_key)), '2a00$_keyHex');
      expect(() => MeshcoreFrameCodec.getAdvertPath(Uint8List(7)),
          throwsArgumentError);
    });
    test('reply with a 2-hop, 1-byte-hash path', () {
      final AdvertPath p = (MeshcoreFrameCodec.decode(
              _h('16 e8030000 02 aabb')) as AdvertPathFrame)
          .advertPath;
      expect(p.receivedAt, 1000);
      expect(p.pathLen.hopCount, 2);
      expect(p.pathLen.hashSize, 1);
      expect(_x(p.path), 'aabb');
    });
    test('hash size lives in the top two bits: 0x42 = 2 hops x 2 bytes', () {
      final AdvertPath p = (MeshcoreFrameCodec.decode(
              _h('16 00000000 42 aabbccdd')) as AdvertPathFrame)
          .advertPath;
      expect(p.pathLen.hashSize, 2);
      expect(p.pathLen.byteLength, 4);
      expect(_x(p.path), 'aabbccdd');
    });
    test('a direct advert has path_len 0 and no path bytes', () {
      final AdvertPath p = (MeshcoreFrameCodec.decode(
              _h('16 00000000 00')) as AdvertPathFrame)
          .advertPath;
      expect(p.path, isEmpty);
    });
    test('an over-long path_len yields an empty path, as the firmware writes',
        () {
      // 0xFF = hash size 4, 63 hops = 252 bytes > MAX_PATH_SIZE 64;
      // Packet::writePath emits nothing (Packet.cpp:24-27).
      final AdvertPath p = (MeshcoreFrameCodec.decode(
              _h('16 00000000 ff')) as AdvertPathFrame)
          .advertPath;
      expect(p.pathLen.isValid, isFalse);
      expect(p.path, isEmpty);
    });
    test('path shorter than path_len is a decode failure', () {
      expect(MeshcoreFrameCodec.decode(_h('16 00000000 03 aabb')),
          isA<DecodeFailure>());
    });
  });

  group('sendPathDiscoveryReq (0x34) and push 0x8D', () {
    test('request is opcode, reserved 0, key', () {
      expect(_x(MeshcoreFrameCodec.sendPathDiscoveryReq(_key)),
          '3400$_keyHex');
      expect(() => MeshcoreFrameCodec.sendPathDiscoveryReq(Uint8List(31)),
          throwsArgumentError);
    });
    test('push carries both directions', () {
      final PathDiscoveryResult r = (MeshcoreFrameCodec.decode(
              _h('8d 00 aabbccddeeff 02 1122 01 33')) as PathDiscoveryFrame)
          .result;
      expect(_x(r.pubKeyPrefix), 'aabbccddeeff');
      expect(r.outPathLen.hopCount, 2);
      expect(_x(r.outPath), '1122');
      expect(r.inPathLen.hopCount, 1);
      expect(_x(r.inPath), '33');
    });
    test('zero-hop both ways', () {
      final PathDiscoveryResult r = (MeshcoreFrameCodec.decode(
              _h('8d 00 aabbccddeeff 00 00')) as PathDiscoveryFrame)
          .result;
      expect(r.outPath, isEmpty);
      expect(r.inPath, isEmpty);
    });
    test('truncated second path is a decode failure', () {
      expect(MeshcoreFrameCodec.decode(_h('8d 00 aabbccddeeff 01 11 02 33')),
          isA<DecodeFailure>());
    });
  });

  group('sendAnonReq (0x39)', () {
    test('opcode + key + data', () {
      expect(_x(MeshcoreFrameCodec.sendAnonReq(_key, _h('aabb'))),
          '39${_keyHex}aabb');
    });
    test('1 byte is the firmware minimum (len > 1+32)', () {
      expect(MeshcoreFrameCodec.sendAnonReq(_key, _h('00')).length, 34);
      expect(() => MeshcoreFrameCodec.sendAnonReq(_key, Uint8List(0)),
          throwsArgumentError);
    });
    test('132 bytes is the ceiling createAnonDatagram accepts (Mesh.cpp:514)',
        () {
      expect(MeshcoreFrameCodec.sendAnonReq(_key, Uint8List(132)).length, 165);
      expect(() => MeshcoreFrameCodec.sendAnonReq(_key, Uint8List(133)),
          throwsArgumentError);
    });
    test('the limit is tighter than the 143 bytes a frame could hold', () {
      expect(kAnonReqDataMax, lessThan(176 - 33));
    });
    test('a wrong-length key is refused', () {
      expect(() => MeshcoreFrameCodec.sendAnonReq(Uint8List(5), _h('aa')),
          throwsArgumentError);
    });
  });

  group('contact pushes', () {
    test('0x8F carries the deleted key', () {
      final MeshcoreInbound r = MeshcoreFrameCodec.decode(_h('8f$_keyHex'));
      expect(_x((r as ContactDeletedFrame).publicKey), _keyHex);
    });
    test('0x8F with a short key is a decode failure', () {
      expect(MeshcoreFrameCodec.decode(_h('8f0102')), isA<DecodeFailure>());
    });
    test('0x90 is a bare code', () {
      expect(MeshcoreFrameCodec.decode(_h('90')), isA<ContactsFullFrame>());
    });
  });
}
