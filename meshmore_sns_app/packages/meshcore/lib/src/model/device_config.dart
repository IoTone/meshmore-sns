// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
/// Radio parameters for `CMD_SET_RADIO_PARAMS` (0x0B).
///
/// On wire: `freq_kHz = round(frequencyMhz × 1000)` and
/// `bw_Hz-ish = round(bandwidthKhz × 1000)` as uint32 LE, then SF/CR
/// bytes (`MyMesh.cpp`, pinned commit).
class RadioParams {
  const RadioParams({
    required this.frequencyMhz,
    required this.bandwidthKhz,
    required this.spreadingFactor,
    required this.codingRate,
    this.repeat,
  });

  final double frequencyMhz;
  final double bandwidthKhz;

  /// 5–12.
  final int spreadingFactor;

  /// 5–8.
  final int codingRate;

  /// Optional repeat flag (firmware v9+); omitted from the frame when
  /// null.
  final int? repeat;

  @override
  String toString() => 'RadioParams(${frequencyMhz}MHz/${bandwidthKhz}kHz '
      'SF$spreadingFactor CR$codingRate)';
}

/// Decoded `RESP_CODE_DEVICE_INFO` (0x0D).
///
/// ```
/// [0D][fw_ver][max_contacts/2][max_group_channels][ble_pin u32 LE]
/// [build_date 12][manufacturer 40][firmware_version 20]
/// [client_repeat][path_hash_mode]
/// ```
class DeviceInfo {
  const DeviceInfo({
    required this.firmwareVerCode,
    required this.maxContacts,
    required this.maxGroupChannels,
    required this.blePin,
    required this.firmwareBuildDate,
    required this.manufacturer,
    required this.firmwareVersion,
    required this.clientRepeat,
    required this.pathHashMode,
    this.hasClientRepeat = true,
    this.hasPathHashMode = true,
  });

  final int firmwareVerCode;

  /// Already doubled back from the on-wire `max_contacts / 2`.
  final int maxContacts;
  final int maxGroupChannels;
  final int blePin;
  final String firmwareBuildDate;
  final String manufacturer;
  final String firmwareVersion;
  /// `repeat_enabled` at offset 80. Added at companion protocol version 9;
  /// a frame from an older radio stops at offset 79 and reports `0` here,
  /// which is also what a radio that does not repeat says.
  final int clientRepeat;

  /// True when the frame actually carried [clientRepeat]. False means the
  /// radio predates version 9, and `0` is the firmware's own default rather
  /// than a reading.
  final bool hasClientRepeat;

  /// `path_hash_mode` at offset 81, the `set path.hash.mode` value: `0` is
  /// one-byte hashes (the legacy setting), `1` two bytes, `2` three. Added at
  /// version 10; an older frame stops at offset 80 and reports `0` here, which
  /// is the only mode those radios can use.
  final int pathHashMode;

  /// True when the frame actually carried [pathHashMode].
  final bool hasPathHashMode;

  @override
  String toString() => 'DeviceInfo(fw: $firmwareVersion '
      '($firmwareBuildDate), mfr: $manufacturer, maxContacts: '
      '$maxContacts, maxChannels: $maxGroupChannels)';
}

/// Decoded `RESP_CODE_BATT_AND_STORAGE` (0x0C).
///
/// `[0C][batt_mv u16 LE][used_kb u32 LE][total_kb u32 LE]`.
class BatteryStorage {
  const BatteryStorage({
    required this.batteryMillivolts,
    required this.storageUsedKb,
    required this.storageTotalKb,
  });

  final int batteryMillivolts;
  final int storageUsedKb;
  final int storageTotalKb;

  double get batteryVolts => batteryMillivolts / 1000.0;

  @override
  String toString() => 'BatteryStorage(${batteryVolts}V, '
      '$storageUsedKb/$storageTotalKb KB)';
}
