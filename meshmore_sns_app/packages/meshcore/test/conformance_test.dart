// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
//
// Conformance suite: the checks a firmware change has to break.
//
// Every constant asserted here is traced to firmware source rather than to this
// package's own arithmetic, so a firmware that moves a cap fails this file
// before it fails on a device. The CEILINGS group is the four byte budgets the
// protocol stacks: channel text, datagram blob, one BLE frame, and the queued
// packet slot text must stay under. The PATH_LEN group is the packed path byte.
// The AIRTIME group is the estimate the 36 s/h policy charges against. The
// INVENTORY group is a ratchet: it refuses a new encoder that nobody wrote a
// check for.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:meshcore/meshcore.dart';
import 'package:test/test.dart';

/// A transport that records what it was asked to send and never connects.
class _RecordingTransport implements MeshcoreTransport {
  final List<Uint8List> sent = <Uint8List>[];
  final StreamController<bool> _connected = StreamController<bool>.broadcast();

  @override
  int? get mtu => 179;

  @override
  bool get isConnected => true;

  @override
  Stream<bool> get connected => _connected.stream;

  @override
  Stream<Uint8List> get incoming => const Stream<Uint8List>.empty();

  @override
  Future<void> send(Uint8List frame) async => sent.add(frame);

  @override
  Future<void> close() async => _connected.close();
}

void main() {
  group('CEILINGS — channel text', () {
    test('160 bytes of text is accepted and stays inside one frame', () {
      final String text = 'a' * ChannelTextLimits.maxTextBytes;
      final Uint8List frame = MeshcoreFrameCodec.sendChannelTextMessage(
        channelIdx: 0,
        timestamp: 0x01020304,
        text: text,
      );
      // 0x03 [txt_type] [channel_idx] [timestamp u32] [text]
      expect(frame.length, 1 + 1 + 1 + 4 + 160);
      expect(frame.length, lessThanOrEqualTo(ChannelTextLimits.maxFrameBytes));
      expect(frame[0], MeshcoreCommand.sendChannelMessage.code);
    });

    test('161 bytes is refused here, not truncated at the radio', () {
      expect(
        () => MeshcoreFrameCodec.sendChannelTextMessage(
          channelIdx: 0,
          timestamp: 0,
          text: 'a' * (ChannelTextLimits.maxTextBytes + 1),
        ),
        throwsA(isA<ChannelTextException>()
            .having((ChannelTextException e) => e.refusal, 'refusal',
                ChannelTextRefusal.textTooLong)
            .having((ChannelTextException e) => e.actual, 'actual', 161)
            .having((ChannelTextException e) => e.maximum, 'maximum', 160)),
      );
    });

    test('the budget is bytes, so a Japanese message is shorter', () {
      // Three bytes per kana: 53 kana = 159 bytes fit, 54 = 162 do not.
      expect(ChannelTextLimits.bytesOf('あ' * 53), 159);
      expect(
        () => MeshcoreFrameCodec.sendChannelTextMessage(
          channelIdx: 3,
          timestamp: 0,
          text: 'あ' * 54,
        ),
        throwsA(isA<ChannelTextException>()),
      );
      expect(
        MeshcoreFrameCodec.sendChannelTextMessage(
          channelIdx: 3,
          timestamp: 0,
          text: 'あ' * 53,
        ).length,
        1 + 1 + 1 + 4 + 159,
      );
    });

    test('the sender prefix the app adds is inside the same 160', () {
      const String prefix = 'Alex: ';
      final String exact = prefix + 'a' * (160 - prefix.length);
      expect(ChannelTextLimits.bytesOf(exact), 160);
      expect(
        () => MeshcoreFrameCodec.sendChannelTextMessage(
          channelIdx: 0,
          timestamp: 0,
          text: '$exact!',
        ),
        throwsA(isA<ChannelTextException>()),
      );
    });

    test('the queued-packet slot is 177 and text stays below it', () {
      // MAX_PACKET_PAYLOAD(184) - 4 - CIPHER_MAC_SIZE(2) - 1 = 177.
      expect(ChannelTextLimits.queueSlotBytes, 184 - 4 - 2 - 1);
      expect(ChannelTextLimits.maxTextBytes,
          lessThan(ChannelTextLimits.queueSlotBytes));
    });
  });

  group('CEILINGS — channel datagram blob', () {
    test('162 bytes of blob is accepted (165 - 3 header)', () {
      expect(ChannelDataLimits.maxBlob, 162);
      final Uint8List frame = MeshcoreFrameCodec.sendChannelData(
        channelIdx: 0,
        dataType: 0xFF01,
        blob: List<int>.filled(162, 0x41),
      );
      expect(frame.length, ChannelDataLimits.headerBytes + 162);
      expect(frame.length, lessThanOrEqualTo(ChannelTextLimits.maxFrameBytes));
    });

    test('163 bytes is refused with the datagram bound named', () {
      expect(
        () => MeshcoreFrameCodec.sendChannelData(
          channelIdx: 0,
          dataType: 0xFF01,
          blob: List<int>.filled(163, 0x41),
        ),
        throwsA(isA<ChannelDataException>().having(
            (ChannelDataException e) => e.refusal,
            'refusal',
            ChannelDataRefusal.blobTooLongForDatagram)),
      );
    });

    test('a direct send spends frame bytes on its path, and flood spends none',
        () {
      // Flood carries no path byte, so the frame is 5 + blob.
      final Uint8List flood = MeshcoreFrameCodec.sendChannelData(
        channelIdx: 0,
        dataType: 0xFF01,
        blob: List<int>.filled(10, 1),
      );
      expect(flood.length, 5 + 10);
      // A one-hop, 1-byte-hash path (path_len 0x00) adds one byte on the wire.
      final Uint8List direct = MeshcoreFrameCodec.sendChannelData(
        channelIdx: 0,
        dataType: 0xFF01,
        blob: List<int>.filled(10, 1),
        pathLen: 0x01,
        path: const <int>[0xAB],
      );
      expect(direct.length, flood.length + 1);
      // The datagram cap binds first until the path is long enough that the
      // frame does: 176 - 5 - 10 = 161 < 162.
      expect(ChannelDataLimits.blobMaxForPath(1), ChannelDataLimits.maxBlob);
      expect(ChannelDataLimits.blobMaxForPath(10),
          ChannelTextLimits.maxFrameBytes - 5 - 10);
      // A 64-byte path leaves 107, so the frame binds and the blob shrinks.
      expect(ChannelDataLimits.blobMaxForPath(64),
          ChannelTextLimits.maxFrameBytes - 5 - 64);
    });
  });

  group('CEILINGS — one frame on the link', () {
    test('176 bytes crosses, 177 is refused before the platform write',
        () async {
      final MeshcoreConnection conn = MeshcoreConnection();
      final _RecordingTransport t = _RecordingTransport();
      conn.attach(t);
      await conn.sendCommand(Uint8List(176));
      expect(t.sent.last.length, 176);
      expect(ChannelTextLimits.maxFrameBytes, MeshcoreBle.maxFrameSize);
      expect(
        () => conn.sendCommand(Uint8List(177)),
        throwsA(isA<FrameLengthException>()
            .having((FrameLengthException e) => e.actual, 'actual', 177)
            .having((FrameLengthException e) => e.maximum, 'maximum', 176)),
      );
      await conn.dispose();
    });
  });

  group('PATH_LEN — width in bits 7-6, hops in 5-0', () {
    test('every width and hop count unpacks to its byte length', () {
      for (int width = 0; width < 4; width++) {
        final int hashSize = width + 1;
        for (final int hops in <int>[0, 1, 2, 31, 32, 63]) {
          final PathLen len = PathLen((width << 6) | hops);
          expect(len.hashSize, hashSize);
          expect(len.hopCount, hops);
          expect(len.byteLength, hashSize * hops);
        }
      }
    });

    test('a reserved hash size and an over-long path are the only refusals',
        () {
      // Hash size 4 (width code 3) is reserved: Packet::isValidPathLen.
      expect(const PathLen(0xC0).isValid, isFalse);
      expect(const PathLen(0xC1).isValid, isFalse);
      // 64 bytes is MAX_PATH_SIZE and fits; 65 does not.
      expect(PathLen(0x00 | 63).byteLength, 63);
      expect(const PathLen(0x3F).isValid, isTrue); // 63 hops x 1 byte
      expect(const PathLen(0xFF).isValid, isFalse); // 63 hops x 4 bytes = 252
      expect(const PathLen(0x7F).isValid, isFalse); // 63 hops x 2 bytes = 126
      // 32 hops x 2 bytes = 64, exactly MAX_PATH_SIZE.
      expect(PathLen(0x40 | 32).byteLength, kMaxPathSize);
      expect(const PathLen(0x40 | 32).isValid, isTrue);
      expect(const PathLen(0x40 | 33).isValid, isFalse);
    });

    test('the flood sentinel is not a path length', () {
      expect(kPathLenFlood, 0xFF);
      // 0xFF is a legal-looking byte whose unpacked size is 252, over the cap.
      expect(const PathLen(kPathLenFlood).isValid, isFalse);
    });
  });

  group('AIRTIME — the estimate the 36 s/h policy charges', () {
    test('one datagram costs its blob plus the bytes before it', () {
      expect(ChannelDataLimits.airtimeBytesFor(0),
          ChannelDataLimits.headerBytes - 1);
      expect(ChannelDataLimits.airtimeBytesFor(162), 4 + 162);
    });

    test('a full text and a full blob are inside one frame each', () {
      // Text: 0x03 + 1 + 1 + 4 + 160 = 167 <= 176.
      expect(1 + 1 + 1 + 4 + ChannelTextLimits.maxTextBytes,
          lessThanOrEqualTo(ChannelTextLimits.maxFrameBytes));
      // Datagram: 5 + 162 = 167 <= 176.
      expect(ChannelDataLimits.headerBytes + ChannelDataLimits.maxBlob,
          lessThanOrEqualTo(ChannelTextLimits.maxFrameBytes));
    });

    test('a 36 s budget at the default 4 ms/byte is a whole number of frames',
        () {
      const int budgetMillis = 36 * 1000;
      const int millisPerByte = 4;
      final int datagramBytes =
          ChannelDataLimits.airtimeBytesFor(ChannelDataLimits.maxBlob);
      // Floor, because a policy that rounds up would spend more than it has.
      final int datagrams = budgetMillis ~/ (millisPerByte * datagramBytes);
      expect(datagrams, 54);
      expect(datagrams * millisPerByte * datagramBytes,
          lessThanOrEqualTo(budgetMillis));
    });
  });

  group('DEVICE_INFO — the length decides what the tail means', () {
    /// `0x0D [fw_ver][max_contacts/2][max_channels][pin u32][build 12]
    /// [mfr 40][fw 20]` and then, only when the protocol version is new enough,
    /// `[client_repeat]` and `[path_hash_mode]`.
    Uint8List deviceInfo({required int ver, int tail = 2, int tailBytes = 2}) {
      final Uint8List f = Uint8List(82);
      f[0] = 0x0D;
      f[1] = ver;
      f[2] = 175; // 350 contacts after the ×2
      f[3] = 40;
      // pin at 4..7, build 8..19, mfr 20..59, version 60..79
      if (tailBytes >= 1) f[80] = tail & 0xFF;
      if (tailBytes >= 2) f[81] = (tail >> 8) & 0xFF;
      return Uint8List.sublistView(f, 0, 80 + tailBytes);
    }

    test('a version-8 radio (80 bytes) decodes, with no tail reading', () {
      final MeshcoreInbound got =
          MeshcoreFrameCodec.decode(deviceInfo(ver: 8, tailBytes: 0));
      expect(got, isA<DeviceInfoFrame>(),
          reason: 'the tail is optional, so its absence is not truncation');
      final DeviceInfo d = (got as DeviceInfoFrame).info;
      expect(d.maxContacts, 350);
      expect(d.maxGroupChannels, 40);
      expect(d.hasClientRepeat, isFalse);
      expect(d.hasPathHashMode, isFalse);
      expect(d.pathHashMode, 0,
          reason: 'pre-10 radios can only use one-byte hashes');
    });

    test('a version-9 radio (81 bytes) reports repeat and no path mode', () {
      final DeviceInfo d =
          (MeshcoreFrameCodec.decode(deviceInfo(ver: 9, tail: 1, tailBytes: 1))
                  as DeviceInfoFrame)
              .info;
      expect(d.hasClientRepeat, isTrue);
      expect(d.clientRepeat, 1);
      expect(d.hasPathHashMode, isFalse);
      expect(d.pathHashMode, 0);
    });

    test('a version-10 radio (82 bytes) reports both', () {
      final DeviceInfo d = (MeshcoreFrameCodec.decode(
                  deviceInfo(ver: 10, tail: 0x0102, tailBytes: 2))
              as DeviceInfoFrame)
          .info;
      expect(d.hasClientRepeat, isTrue);
      expect(d.clientRepeat, 2);
      expect(d.hasPathHashMode, isTrue);
      expect(d.pathHashMode, 1);
    });

    test(
        'a frame that advertises version 10 but stops at 80 bytes does not '
        'read past its end', () {
      final MeshcoreInbound got =
          MeshcoreFrameCodec.decode(deviceInfo(ver: 10, tailBytes: 0));
      expect(got, isA<DeviceInfoFrame>(),
          reason: 'the version is a claim; the length is the fact');
      final DeviceInfo d = (got as DeviceInfoFrame).info;
      expect(d.hasPathHashMode, isFalse);
    });

    test('a frame shorter than the fixed fields is still a truncation', () {
      final MeshcoreInbound got = MeshcoreFrameCodec.decode(
          Uint8List.fromList(<int>[0x0D, 10, 175, 40, 0]));
      expect(got, isA<DecodeFailure>());
      expect((got as DecodeFailure).error.kind, DecodeErrorKind.truncated);
    });
  });

  group('MULTI-FORM frames — discriminated by length, never by assumption', () {
    test(
        'DEFAULT_FLOOD_SCOPE: the bare reply means unset, the 48-byte reply '
        'carries a name and a key', () {
      expect(
          MeshcoreFrameCodec.decodeDefaultFloodScope(
              Uint8List.fromList(<int>[0x1C])),
          isNull);
      final Uint8List full = Uint8List(1 + 31 + 16)..[0] = 0x1C;
      full.setRange(1, 5, utf8.encode('#reg'));
      for (int i = 0; i < 16; i++) {
        full[32 + i] = i;
      }
      final ({String name, Uint8List key})? got =
          MeshcoreFrameCodec.decodeDefaultFloodScope(full);
      expect(got, isNotNull);
      expect(got!.name, '#reg');
      expect(got.key.length, 16);
    });

    test(
        'LOGIN_SUCCESS: the 8-byte legacy form and the 15-byte form both '
        'decode', () {
      // 0x85 [permissions][reserved 6][pubkey6] (+ serverTs, acl, fwLevel)
      final Uint8List legacy = Uint8List(8)..[0] = 0x85;
      legacy[1] = 3;
      final MeshcoreInbound a = MeshcoreFrameCodec.decode(legacy);
      expect(a, isA<LoginResultFrame>());
      final LoginResult la = (a as LoginResultFrame).result;
      expect(la.success, isTrue);
      expect(la.permissions, 3);
      expect(la.serverTimestamp, isNull);

      final Uint8List full = Uint8List(15)..[0] = 0x85;
      full[1] = 3;
      full.setRange(8, 12, <int>[0x10, 0x27, 0, 0]);
      full[12] = 5;
      full[13] = 7;
      final LoginResult lb =
          (MeshcoreFrameCodec.decode(full) as LoginResultFrame).result;
      expect(lb.serverTimestamp, 0x2710);
      expect(lb.aclPermissions, 5);
      expect(lb.firmwareLevel, 7);
    });

    test('STATS: recvErrors is read only when the struct carries it', () {
      // 0x18 [sub=2] then six u32 counters, optionally a seventh.
      Uint8List packets({required bool withErrors}) {
        final int n = 2 + (withErrors ? 28 : 24);
        final Uint8List f = Uint8List(n)..[0] = 0x18;
        f[1] = 2; // kStatsTypePackets
        for (int i = 0; i < (withErrors ? 7 : 6); i++) {
          f[2 + i * 4] = i + 1;
        }
        return f;
      }

      final StatsFrame short =
          (MeshcoreFrameCodec.decode(packets(withErrors: false)) as StatsFrame);
      expect(short.packets!.receiveErrors, isNull);
      final StatsFrame long =
          (MeshcoreFrameCodec.decode(packets(withErrors: true)) as StatsFrame);
      expect(long.packets!.receiveErrors, isNotNull);
    });
  });

  group('ERRORS - the six firmware codes, and an unknown one degrades', () {
    test('1..6 map to the firmware constants and an unknown code degrades', () {
      expect(MeshcoreErrorCode.unsupportedCmd.code, 1);
      expect(MeshcoreErrorCode.notFound.code, 2);
      expect(MeshcoreErrorCode.tableFull.code, 3);
      expect(MeshcoreErrorCode.badState.code, 4);
      expect(MeshcoreErrorCode.fileIoError.code, 5);
      expect(MeshcoreErrorCode.illegalArg.code, 6);

      // 0x01 [code] decodes for every value, including ones this build has
      // never seen: a newer firmware's code must not crash the decoder.
      for (final int code in <int>[0, 1, 2, 3, 4, 5, 6, 7, 42, 255]) {
        final MeshcoreInbound got =
            MeshcoreFrameCodec.decode(Uint8List.fromList(<int>[0x01, code]));
        expect(got, isA<ErrorFrame>());
        expect((got as ErrorFrame).code, code);
      }
    });

    test('the obsolete nine-entry table is not what this build implements', () {
      // The v1.12 document lists 0x03 as "channel not found"; the firmware's
      // own constants say 0x03 is table-full. A client built on the old table
      // would mislabel every refusal.
      expect(MeshcoreErrorCode.tableFull.code, 3);
      expect(MeshcoreErrorCode(3).name, 'table_full');
      expect(MeshcoreErrorCode(3), MeshcoreErrorCode.tableFull);
    });
  });

  group('INVENTORY — a new encoder cannot arrive without a check', () {
    // Committed inventory of the public encoders in
    // lib/src/codec/frame_codec.dart. Adding or renaming one fails this test on
    // purpose: the entry must come with a golden vector under test/vectors/ or
    // an assertion in this file, and then the list is updated.
    const Set<String> encoders = <String>{
      'appStart',
      'getContacts',
      'getDeviceTime',
      'setDeviceTime',
      'syncNextMessage',
      'sendChannelTextMessage',
      'sendChannelData',
      'sendTextMessage',
      'sendSelfAdvert',
      'setAdvertName',
      'removeContact',
      'addUpdateContact',
      'setRadioParams',
      'setPathHashMode',
      'setFloodScopeKey',
      'sendUnscopedFlood',
      'setDefaultFloodScope',
      'getDefaultFloodScope',
      'getAllowedRepeatFreq',
      'setRadioTxPower',
      'setAdvertLatLon',
      'setOtherParams',
      'getCustomVars',
      'setCustomVar',
      'sendTelemetryReq',
      'setTuningParams',
      'deviceQuery',
      'getBatteryStorage',
      'getChannel',
      'setChannel',
      'getStats',
      'sendStatusReq',
      'resetPath',
      'sendTracePath',
      'sendDiscoverReq',
      'shareContact',
      'exportContact',
      'importContact',
      'reboot',
      'factoryReset',
      'exportPrivateKey',
      'importPrivateKey',
      'sendLogin',
      'hasConnection',
      'logout',
      'getContactByKey',
      'signStart',
      'signData',
      'signDataFrames',
      'signFinish',
      'setDevicePin',
      'getAdvertPath',
      'getTuningParams',
      'sendPathDiscoveryReq',
      'sendAnonReq',
      'setAutoAddConfig',
      'getAutoAddConfig',
    };

    // Encoders no test names yet. This list may only shrink: an encoder that
    // leaves it must be covered by a vector or an assertion above.
    const Set<String> unexercised = <String>{
      'getAllowedRepeatFreq',
      'getDefaultFloodScope',
      'removeContact',
    };

    test('the source has exactly the committed encoders', () {
      final String src =
          File('lib/src/codec/frame_codec.dart').readAsStringSync();
      final RegExp re =
          RegExp(r'static (?:Uint8List|List<Uint8List>) ([A-Za-z0-9]+)\(');
      final Set<String> found = <String>{
        for (final RegExpMatch m in re.allMatches(src))
          if (!m.group(1)!.startsWith('_')) m.group(1)!,
      };
      expect(found.difference(encoders), isEmpty,
          reason: 'new encoder(s) with no committed check: '
              '${found.difference(encoders).join(', ')}');
      expect(encoders.difference(found), isEmpty,
          reason: 'inventory names an encoder the source no longer has: '
              '${encoders.difference(found).join(', ')}');
    });

    test('every encoder is either checked somewhere or on the known-gap list',
        () {
      final StringBuffer all = StringBuffer();
      for (final FileSystemEntity e
          in Directory('test').listSync(recursive: true)) {
        if (e is File &&
            e.path.endsWith('.dart') &&
            !e.path.endsWith('conformance_test.dart')) {
          all.write(e.readAsStringSync());
        }
      }
      final String haystack = all.toString();
      final Set<String> unchecked = <String>{
        for (final String name in encoders)
          if (!haystack.contains(name)) name,
      };
      final Set<String> regression = unchecked.difference(unexercised);
      expect(regression, isEmpty,
          reason: 'encoder(s) no test names and not on the gap list: '
              '${regression.join(', ')}');
      // Ratchet, the other way: an encoder that is now covered must leave the
      // gap list, so the list can only shrink.
      expect(unexercised.difference(unchecked), isEmpty,
          reason: 'now covered, so remove from the gap list: '
              '${unexercised.difference(unchecked).join(', ')}');
    });
  });
}
