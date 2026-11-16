// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:meshcore/meshcore.dart';
import 'package:test/test.dart';

void main() {
  group('capability is learned, never assumed', () {
    test('an unprobed command is unknown and refused', () {
      final RadioCapabilities caps = RadioCapabilities();
      expect(caps.stateOf(MeshcoreCommand.setAutoAddConfig),
          CapabilityState.unknown);
      expect(caps.refusalFor(MeshcoreCommand.setAutoAddConfig),
          CapabilityRefusal.unknown);
    });

    test('a reply flips an entry to supported', () {
      final RadioCapabilities caps = RadioCapabilities();
      caps.observeReply(MeshcoreCommand.getContacts);
      expect(caps.refusalFor(MeshcoreCommand.getContacts), isNull);
    });

    test('unsupported is absent, and any other error changes nothing', () {
      final RadioCapabilities caps = RadioCapabilities();
      caps.observeError(MeshcoreCommand.setAutoAddConfig,
          MeshcoreErrorCode.unsupportedCmd.code);
      expect(caps.stateOf(MeshcoreCommand.setAutoAddConfig),
          CapabilityState.absent);
      expect(caps.refusalFor(MeshcoreCommand.setAutoAddConfig),
          CapabilityRefusal.unsupported);

      caps.observeError(MeshcoreCommand.getContacts, 2); // not found
      expect(caps.stateOf(MeshcoreCommand.getContacts), CapabilityState.unknown);
    });

    test('a probe can establish either state without a reply', () {
      final RadioCapabilities caps = RadioCapabilities();
      caps.markSupported(MeshcoreCommand.getDeviceTime);
      caps.markAbsent(MeshcoreCommand.setDevicePin);
      expect(caps.refusalFor(MeshcoreCommand.getDeviceTime), isNull);
      expect(caps.refusalFor(MeshcoreCommand.setDevicePin),
          CapabilityRefusal.unsupported);
    });

    test('changing radio forgets the last radio answers', () {
      final RadioCapabilities caps = RadioCapabilities();
      caps.observeReply(MeshcoreCommand.getContacts);
      caps.reset();
      expect(caps.stateOf(MeshcoreCommand.getContacts), CapabilityState.unknown);
    });

    test('no version number decides a capability', () {
      final String source =
          File('lib/src/codec/capability.dart').readAsStringSync();
      for (final String forbidden in <String>[
        'appTargetVer',
        'kMeshcoreFirmwarePinTag',
        'kMeshcoreFirmwarePinCommit',
        'kProtocolVersion',
      ]) {
        expect(source.contains(forbidden), isFalse, reason: forbidden);
      }
    });
  });

  group('firmware OTA is status only', () {
    test('an unknown radio cannot start an install', () {
      expect(const FirmwareOta().startRefusalFor(RadioCapabilities()),
          OtaStartRefusal.capabilityUnknown);
    });

    test('a capable radio still cannot start: the queue drain is unhandled',
        () {
      final RadioCapabilities caps = RadioCapabilities()
        ..markSupported(FirmwareOta.control);
      expect(const FirmwareOta().startRefusalFor(caps),
          OtaStartRefusal.queueDrainUnhandled);
    });

    test('a radio without the OTA CLI is refused as unsupported', () {
      final RadioCapabilities caps = RadioCapabilities()
        ..markAbsent(FirmwareOta.control);
      expect(const FirmwareOta().startRefusalFor(caps),
          OtaStartRefusal.unsupportedByFirmware);
    });
  });
}
