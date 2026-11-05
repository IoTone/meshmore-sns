// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'capability.dart';
import 'constants.dart';

/// Why the app will not start a firmware install on the radio.
enum OtaStartRefusal {
  /// A firmware image install consumes the companion's offline queue:
  /// the radio keeps only `OTA_RETAINED_OFFLINE_FRAMES` of it while the
  /// image streams (`MyMesh.cpp:607-611`). Until the app handles that
  /// drain — re-syncing the messages the radio is about to discard — it
  /// must not start an install. Status is readable; starting is not.
  queueDrainUnhandled,

  /// Nothing is known about this radio's OTA commands yet.
  capabilityUnknown,

  /// The radio answered `ERR_CODE_UNSUPPORTED_CMD`: it was not built with
  /// the OTA CLI (`COMPANION_FEATURE_OTA_CLI`).
  unsupportedByFirmware,
}

/// The firmware-OTA gate. Status only, by decision: `0x4A`
/// (`CMD_EXEC_LOCAL_OTA_CONTROL`) and `0x4B` (`CMD_BLE_MOTA_SOURCE`) are
/// modelled so a status reply can be understood, but there is deliberately
/// no way here to start an install, and the refusal is a value a screen can
/// show rather than an exception a caller can swallow.
final class FirmwareOta {
  const FirmwareOta();

  static const MeshcoreCommand control = MeshcoreCommand(0x4A);
  static const MeshcoreCommand bleSource = MeshcoreCommand(0x4B);

  /// Null only if an install could be started. Today that is never.
  OtaStartRefusal? startRefusalFor(RadioCapabilities capabilities) =>
      switch (capabilities.stateOf(control)) {
        CapabilityState.supported => OtaStartRefusal.queueDrainUnhandled,
        CapabilityState.absent => OtaStartRefusal.unsupportedByFirmware,
        CapabilityState.unknown => OtaStartRefusal.capabilityUnknown,
      };
}
