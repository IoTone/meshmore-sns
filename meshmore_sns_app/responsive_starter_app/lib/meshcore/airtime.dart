// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:meshcore/meshcore.dart';

import 'region_presets.dart';

/// How much airtime this end allows itself to spend.
///
/// A budget is a policy, not a property of the link. The default is a
/// voluntary 1 % duty cycle, which is the legal limit in the EU and UK and a
/// deliberate safety margin anywhere else. A private frequency nobody else
/// uses does not need that margin, and pretending otherwise makes a link that
/// could be responsive feel broken.
///
/// Neither mode is a regulatory permission. The radio enforces the radio's own
/// limit; a person choosing [ownedChannel] is asserting that the channel is
/// theirs to occupy.
enum AirtimePolicy {
  /// Voluntary 1 % duty cycle: 36 s of transmitter airtime per rolling hour.
  onePercentDutyCycle,

  /// No voluntary cap. Intended for a private frequency the operator controls,
  /// where there is no other traffic to be fair to.
  ownedChannel;

  /// Airtime allowed per rolling hour, or null for no voluntary cap.
  Duration? get hourlyBudget => switch (this) {
        AirtimePolicy.onePercentDutyCycle => const Duration(seconds: 36),
        AirtimePolicy.ownedChannel => null,
      };

  /// Whether this end meters itself. Always true; a policy with no cap still
  /// charges what it spends, so the figure stays honest.
  bool get isUnlimited => hourlyBudget == null;
}

/// Time-on-air estimate for a record of a given length.
///
/// The default, 4 ms/byte, is calibrated to the USA/Canada preset only
/// (910.525 MHz / 62.5 kHz / SF7 / CR5: a 176-byte packet is 613 ms, 3.48
/// ms/byte). It is **not** conservative for slower presets: the same packet is
/// ~9.4 ms/byte on EU/UK Narrow (62.5 kHz / SF8 / CR8) and ~9.5 on EU/UK
/// Deprecated (250 kHz / SF11). A radio on any other preset must be given
/// [AirtimeEstimator.lora] built from its real parameters, or the estimate
/// under-counts airtime.
class AirtimeEstimator {
  const AirtimeEstimator({this.millisPerByte = 4})
      : overheadBytes = 0,
        _lora = null;

  /// Exact LoRa time-on-air (Semtech AN1200.13) for explicit header, CRC on,
  /// preamble as MeshCore sets it (32 symbols for SF<=8, else 16;
  /// `RadioLibWrappers.h:56`). [codingRate] is the 5..8 value MeshCore stores
  /// (4/5 .. 4/8). [overheadBytes] is added to the record: the radio frames a
  /// record with path and header bytes on top of the payload.
  const AirtimeEstimator.lora({
    required int bandwidthHz,
    required int spreadingFactor,
    required int codingRate,
    this.overheadBytes = 0,
  })  : millisPerByte = 0,
        _lora = (bandwidthHz, spreadingFactor, codingRate);

  /// Flat per-byte figure. Zero when built with [AirtimeEstimator.lora].
  final int millisPerByte;

  /// Bytes the radio adds around the record (lora mode only).
  final int overheadBytes;

  final (int, int, int)? _lora;

  Duration forBytes(int bytes) {
    final (int, int, int)? p = _lora;
    if (p == null) return Duration(milliseconds: millisPerByte * bytes);
    final int bw = p.$1, sf = p.$2, cr = p.$3;
    final double symbol = (1 << sf) / bw; // seconds
    final int lowDataRate = symbol > 0.016 ? 1 : 0;
    final int payload = bytes + overheadBytes;
    final int numerator = 8 * payload - 4 * sf + 28 + 16;
    final int denominator = 4 * (sf - 2 * lowDataRate);
    int symbols = ((numerator + denominator - 1) ~/ denominator) * cr;
    if (symbols < 0) symbols = 0;
    final int preamble = sf <= 8 ? 32 : 16;
    final double seconds = (preamble + 4.25 + 8 + symbols) * symbol;
    return Duration(microseconds: (seconds * 1e6).ceil());
  }
}

/// The largest record a path leaves room for: `rawDataPayloadMax(2)`, i.e.
/// `MAX_FRAME_SIZE - opcode - path_len - a 2-byte path`. Used only to compare
/// presets against each other, so any fixed length at the ceiling will do.
const int _recordCeiling = MeshCarryLimits.maxFrameSize - 4;

/// The estimator for the radio's CURRENT parameters.
///
/// With no radio parameters yet (before SelfInfo), the slowest preset in
/// [kRegionPresets] is used, because an under-count would let a send exceed
/// its budget on a slow radio.
AirtimeEstimator estimatorFor(SelfInfo? radio, {int overheadBytes = 16}) {
  if (radio != null) {
    return AirtimeEstimator.lora(
      bandwidthHz: (radio.bandwidthKhz * 1000).round(),
      spreadingFactor: radio.spreadingFactor,
      codingRate: radio.codingRate,
      overheadBytes: overheadBytes,
    );
  }
  AirtimeEstimator worst = AirtimeEstimator.lora(
    bandwidthHz: (kRegionPresets.first.bandwidthKhz * 1000).round(),
    spreadingFactor: kRegionPresets.first.spreadingFactor,
    codingRate: kRegionPresets.first.codingRate,
    overheadBytes: overheadBytes,
  );
  for (final RegionPreset p in kRegionPresets) {
    final AirtimeEstimator e = AirtimeEstimator.lora(
      bandwidthHz: (p.bandwidthKhz * 1000).round(),
      spreadingFactor: p.spreadingFactor,
      codingRate: p.codingRate,
      overheadBytes: overheadBytes,
    );
    if (e.forBytes(_recordCeiling) > worst.forBytes(_recordCeiling)) {
      worst = e;
    }
  }
  return worst;
}
