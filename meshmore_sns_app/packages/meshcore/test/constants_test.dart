// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:meshcore/meshcore.dart';
import 'package:test/test.dart';

void main() {
  group('firmware pin', () {
    test('pin metadata is recorded', () {
      expect(kMeshcoreFirmwarePinTag, 'companion-v1.15.0');
      expect(kMeshcoreFirmwarePinCommit, hasLength(40));
      expect(
        kMeshcoreFirmwarePinCommit,
        matches(RegExp(r'^[0-9a-f]{40}$')),
        reason: 'pin must be a full 40-char git SHA',
      );
    });
  });

  group('BLE transport identifiers', () {
    test('service + characteristic UUIDs match the pinned doc', () {
      expect(MeshcoreBle.serviceUuid,
          equalsIgnoringCase('6E400001-B5A3-F393-E0A9-E50E24DCCA9E'));
      expect(MeshcoreBle.rxCharacteristicUuid,
          equalsIgnoringCase('6E400002-B5A3-F393-E0A9-E50E24DCCA9E'));
      expect(MeshcoreBle.txCharacteristicUuid,
          equalsIgnoringCase('6E400003-B5A3-F393-E0A9-E50E24DCCA9E'));
    });
  });

  group('opcodes', () {
    test('core command opcodes', () {
      expect(MeshcoreCommand.appStart.code, 0x01);
      expect(MeshcoreCommand.sendChannelMessage.code, 0x03);
      expect(MeshcoreCommand.getContacts.code, 0x04);
      expect(MeshcoreCommand.getDeviceTime.code, 0x05);
      expect(MeshcoreCommand.setDeviceTime.code, 0x06);
      expect(MeshcoreCommand.syncNextMessage.code, 0x0A);
      expect(MeshcoreCommand.setChannel.code, 0x20);
    });

    test('core response opcodes', () {
      expect(MeshcoreResponse.ok.code, 0x00);
      expect(MeshcoreResponse.selfInfo.code, 0x05);
      expect(MeshcoreResponse.channelMsgRecv.code, 0x08);
    });

    test('push codes are >= 0x80 and flagged', () {
      expect(MeshcoreResponse.advertisement.isPush, isTrue);
      expect(MeshcoreResponse.messagesWaiting.isPush, isTrue);
      expect(MeshcoreResponse.ok.isPush, isFalse);
      expect(MeshcoreResponse.selfInfo.isPush, isFalse);
    });

    test('every code the firmware defines lands on the right side', () {
      // The tables are the firmware's own defines: RESP_CODE_* 0..29 and
      // PUSH_CODE_* 0x80..0x90, from `examples/companion_radio/MyMesh.cpp`
      // at the pin and from the two-profile tree that adds 0x1D. A new
      // code has to be added here and to a decoder, which is the point.
      const Map<int, String> replies = <int, String>{
        0: 'OK',
        1: 'ERR',
        2: 'CONTACTS_START',
        3: 'CONTACT',
        4: 'END_OF_CONTACTS',
        5: 'SELF_INFO',
        6: 'SENT',
        7: 'CONTACT_MSG_RECV',
        8: 'CHANNEL_MSG_RECV',
        9: 'CURR_TIME',
        10: 'NO_MORE_MESSAGES',
        11: 'EXPORT_CONTACT',
        12: 'BATT_AND_STORAGE',
        13: 'DEVICE_INFO',
        14: 'PRIVATE_KEY',
        15: 'DISABLED',
        16: 'CONTACT_MSG_RECV_V3',
        17: 'CHANNEL_MSG_RECV_V3',
        18: 'CHANNEL_INFO',
        19: 'SIGN_START',
        20: 'SIGNATURE',
        21: 'CUSTOM_VARS',
        22: 'ADVERT_PATH',
        23: 'TUNING_PARAMS',
        24: 'STATS',
        25: 'AUTOADD_CONFIG',
        26: 'ALLOWED_REPEAT_FREQ',
        27: 'CHANNEL_DATA_RECV',
        28: 'DEFAULT_FLOOD_SCOPE',
        29: 'CLI_REPLY',
      };
      const Map<int, String> pushes = <int, String>{
        0x80: 'ADVERT',
        0x81: 'PATH_UPDATED',
        0x82: 'SEND_CONFIRMED',
        0x83: 'MSG_WAITING',
        0x84: 'RAW_DATA',
        0x85: 'LOGIN_SUCCESS',
        0x86: 'LOGIN_FAIL',
        0x87: 'STATUS_RESPONSE',
        0x88: 'LOG_RX_DATA',
        0x89: 'TRACE_DATA',
        0x8A: 'NEW_ADVERT',
        0x8B: 'TELEMETRY_RESPONSE',
        0x8C: 'BINARY_RESPONSE',
        0x8D: 'PATH_DISCOVERY_RESPONSE',
        0x8E: 'CONTROL_DATA',
        0x8F: 'CONTACT_DELETED',
        0x90: 'CONTACTS_FULL',
      };

      replies.forEach((int code, String name) {
        expect(MeshcoreResponse(code).isPush, isFalse,
            reason: 'RESP_CODE_$name (0x${code.toRadixString(16)}) '
                'is a reply, not a push');
      });
      pushes.forEach((int code, String name) {
        expect(MeshcoreResponse(code).isPush, isTrue,
            reason: 'PUSH_CODE_$name (0x${code.toRadixString(16)}) '
                'may arrive at any time');
      });
      // The two replies that arrive without the app having to ask again:
      // a queued datagram drained by CMD_SYNC_NEXT_MESSAGE, and the output
      // stream of CMD_RUN_CLI_COMMAND. They are still answers to a command
      // the app sent, so neither is a push.
      expect(MeshcoreResponse.channelDataRecv.isPush, isFalse);
      expect(MeshcoreResponse.cliReply.isPush, isFalse);
      expect(MeshcoreResponse.cliReply.code, 0x1D);
    });
  });

  group('RxVia (receive profile tag)', () {
    test('maps the two tags the firmware writes', () {
      expect(RxVia.fromWireByte(kRxViaPrimaryTag), RxVia.primary);
      expect(RxVia.fromWireByte(kRxViaSecondaryTag), RxVia.secondary);
    });

    test('anything else is unknown, including both none values', () {
      // 0 is the channel-datagram none value, 0xFF the raw-data one.
      expect(RxVia.fromWireByte(0), RxVia.unknown);
      expect(RxVia.fromWireByte(0xFF), RxVia.unknown);
      expect(RxVia.fromWireByte(0x01), RxVia.unknown);
    });

    test('names are stable for diagnostics', () {
      expect(<String>[for (final RxVia v in RxVia.values) v.name],
          <String>['unknown', 'primary', 'secondary']);
    });
  });

  group('snrByteToDb', () {
    test('positive and negative (two’s complement) bytes', () {
      expect(snrByteToDb(0x00), 0.0);
      expect(snrByteToDb(0x04), 1.0); // 4 / 4
      expect(snrByteToDb(0xFC), -1.0); // (252-256)/4 = -1
      expect(snrByteToDb(0x80), -32.0); // (128-256)/4
    });
  });
}
