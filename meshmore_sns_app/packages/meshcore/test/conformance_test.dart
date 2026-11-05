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
import 'dart:io';
import 'dart:typed_data';

import 'package:meshcore/meshcore.dart';
import 'package:test/test.dart';

/// A transport that records what it was asked to send and never connects.
class _RecordingTransport implements MeshcoreTransport {
  final List<Uint8List> sent = <Uint8List>[];
  final StreamController<bool> _connected =
      StreamController<bool>.broadcast();

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
    test('176 bytes crosses, 177 is refused before the platform write', () async {
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
      final int datagramBytes = ChannelDataLimits.airtimeBytesFor(
          ChannelDataLimits.maxBlob);
      // Floor, because a policy that rounds up would spend more than it has.
      final int datagrams = budgetMillis ~/ (millisPerByte * datagramBytes);
      expect(datagrams, 54);
      expect(datagrams * millisPerByte * datagramBytes,
          lessThanOrEqualTo(budgetMillis));
    });
  });

  group('INVENTORY — a new encoder cannot arrive without a check', () {
    // Committed inventory of the public encoders in
    // lib/src/codec/frame_codec.dart. Adding or renaming one fails this test on
    // purpose: the entry must come with a golden vector under test/vectors/ or
    // an assertion in this file, and then the list is updated.
    const Set<String> encoders = <String>{
      'appStart', 'getContacts', 'getDeviceTime', 'setDeviceTime',
      'syncNextMessage', 'sendChannelTextMessage', 'sendChannelData',
      'sendTextMessage', 'sendSelfAdvert', 'setAdvertName', 'removeContact',
      'addUpdateContact', 'setRadioParams', 'setPathHashMode',
      'setFloodScopeKey', 'sendUnscopedFlood', 'setDefaultFloodScope',
      'getDefaultFloodScope', 'getAllowedRepeatFreq', 'setRadioTxPower',
      'setAdvertLatLon', 'setOtherParams', 'getCustomVars', 'setCustomVar',
      'sendTelemetryReq', 'setTuningParams', 'deviceQuery',
      'getBatteryStorage', 'getChannel', 'setChannel', 'getStats',
      'sendStatusReq', 'resetPath', 'sendTracePath', 'sendDiscoverReq',
      'shareContact', 'exportContact', 'importContact', 'reboot',
      'factoryReset', 'exportPrivateKey', 'importPrivateKey', 'sendLogin',
      'hasConnection', 'logout', 'getContactByKey', 'signStart', 'signData',
      'signDataFrames', 'signFinish', 'setDevicePin', 'getAdvertPath',
      'getTuningParams', 'sendPathDiscoveryReq', 'sendAnonReq',
      'setAutoAddConfig', 'getAutoAddConfig',
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
      for (final FileSystemEntity e in Directory('test').listSync(recursive: true)) {
        if (e is File && e.path.endsWith('.dart') &&
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
