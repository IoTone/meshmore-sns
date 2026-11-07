// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT

import 'package:meshcore/meshcore.dart';

import '../gen/app_localizations.dart';
import 'airtime_meter.dart';
import 'ble_connector.dart';

/// APP-N2 — one table for every refusal the app can show.
///
/// A cause, not a sentence: the same failure reaches a log line, a banner, a
/// diagnostics row and a message's retry subtitle, and only the last two are
/// read by a person. Keeping the cause typed is what lets the copy be
/// translated once instead of being spelled in English at each call site.
enum FailureCause {
  // The firmware's own `ERR_CODE_*` values
  // (`examples/companion_radio/MyMesh.cpp:130-135`,
  // `docs/companion_protocol.md:812-821`).
  unsupportedCommand,
  notFound,
  tableFull,
  badState,
  fileIoError,
  illegalArgument,
  unknownDeviceError,

  // The link, from `BleConnector`.
  blePermissionsDenied,
  bluetoothOff,
  noRadioFound,
  pairingFailed,
  stalePairing,
  pairingNotKept,
  serviceMissing,
  characteristicMissing,
  mtuTooSmall,

  // The app's own.
  frameTruncated,
  frameTrailingBytes,
  storageFull,
  radioSilent,

  /// The app's own duty-cycle meter refused the frame. The radio never saw it.
  airtimeBudget,

  /// The radio answered `RESP_CODE_DISABLED` (0x0F): the command exists but is
  /// switched off on this build, which is not the same as unsupported.
  commandDisabled,
}

/// One refusal: what happened, plus the numbers the copy needs.
class Failure {
  const Failure(this.cause, {this.firmwareCode, this.mtu});

  final FailureCause cause;

  /// The `RESP_CODE_ERR` code when the radio answered; null otherwise.
  final int? firmwareCode;

  /// The ATT MTU that was too small, when [cause] is [FailureCause.mtuTooSmall].
  final int? mtu;

  /// Maps a `RESP_CODE_ERR` code to its cause. The six values are the
  /// firmware's whole enum; anything else stays unknown on purpose, because
  /// inventing a cause for a code a newer firmware added would be worse than
  /// saying the radio refused.
  static FailureCause causeForDeviceError(int? code) => switch (code) {
        1 => FailureCause.unsupportedCommand,
        2 => FailureCause.notFound,
        3 => FailureCause.tableFull,
        4 => FailureCause.badState,
        5 => FailureCause.fileIoError,
        6 => FailureCause.illegalArgument,
        _ => FailureCause.unknownDeviceError,
      };

  static Failure deviceError(int? code) =>
      Failure(causeForDeviceError(code), firmwareCode: code);

  /// Classifies a thrown link error. Anything unrecognised becomes
  /// [FailureCause.unknownDeviceError] rather than being swallowed.
  static Failure from(Object error) {
    if (error is BleMtuTooSmall) {
      return Failure(FailureCause.mtuTooSmall, mtu: error.mtu);
    }
    if (error is BleConnectException) return Failure(error.cause);
    if (error is AirtimeRefused) {
      return const Failure(FailureCause.airtimeBudget);
    }
    return const Failure(FailureCause.unknownDeviceError);
  }

  @override
  String toString() => 'Failure(${cause.name}'
      '${firmwareCode == null ? '' : ' code=$firmwareCode'})';
}

/// The translated sentence for a cause, with its next action where one exists.
String failureText(AppLocalizations l, Failure f) => switch (f.cause) {
      FailureCause.unsupportedCommand => l.failureUnsupportedCommand,
      FailureCause.notFound => l.failureNotFound,
      FailureCause.tableFull => l.failureTableFull,
      FailureCause.badState => l.failureBadState,
      FailureCause.fileIoError => l.failureFileIoError,
      FailureCause.illegalArgument => l.failureIllegalArgument,
      FailureCause.unknownDeviceError => l.failureUnknownDeviceError,
      FailureCause.blePermissionsDenied => l.failureBlePermissions,
      FailureCause.commandDisabled => l.failureCommandDisabled,
      FailureCause.bluetoothOff => l.failureBluetoothOff,
      FailureCause.noRadioFound => l.failureNoRadioFound,
      FailureCause.pairingFailed => l.failurePairingFailed,
      FailureCause.stalePairing => l.failureStalePairing,
      FailureCause.pairingNotKept => l.failurePairingNotKept,
      FailureCause.serviceMissing => l.failureServiceMissing,
      FailureCause.characteristicMissing => l.failureCharacteristicMissing,
      FailureCause.mtuTooSmall => l.failureMtuTooSmall(
          '${f.mtu ?? 0}', '${MeshcoreBle.requiredMtu}'),
      FailureCause.frameTruncated => l.failureFrameTruncated,
      FailureCause.frameTrailingBytes => l.failureFrameTrailingBytes,
      FailureCause.storageFull => l.failureStorageFull,
      FailureCause.radioSilent => l.failureRadioSilent,
      FailureCause.airtimeBudget => l.failureAirtimeBudget,
    };
