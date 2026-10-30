// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT

/// How much airtime this end allows itself to spend.
///
/// A budget is a policy, not a property of the link. `meshmore-sns-architecture.md`
/// §5.5b: the default is a voluntary 1 % duty cycle, which is the legal limit in
/// the EU and UK and a deliberate safety margin anywhere else. A private
/// frequency nobody else uses does not need that margin, and a mode that pretends
/// otherwise makes a link that could be responsive feel broken.
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
  /// charges what it spends, so the figure stays honest in `STATUS`.
  bool get isUnlimited => hourlyBudget == null;
}

/// Airtime accounting for the gateway's **own** transmissions.
///
/// An airtime budget belongs to the transmitter that spends it. This meters
/// only the records this gateway sends uplink. It does not and cannot throttle
/// the peer: the peer's transmissions are the peer's airtime, counted against
/// its own duty cycle (`meshmore-sns-architecture.md` §5.5).
///
/// The figures are **estimates**: they come from the record length, not from a
/// measurement, and cannot see repeater retransmissions or collisions.
class Governor {
  Governor({
    Duration? budget = const Duration(seconds: 36),
    Duration window = const Duration(hours: 1),
    DateTime Function()? clock,
    AirtimePolicy policy = AirtimePolicy.onePercentDutyCycle,
  })  : _budget = budget,
        _policy = policy,
        _window = window,
        _clock = clock ?? DateTime.now;

  /// Built from a policy rather than a figure, so the two modes cannot drift
  /// from what they claim.
  Governor.forPolicy(
    AirtimePolicy policy, {
    Duration window = const Duration(hours: 1),
    DateTime Function()? clock,
  }) : this(
          budget: policy.hourlyBudget,
          window: window,
          clock: clock,
          policy: policy,
        );

  /// Null means no voluntary cap ([AirtimePolicy.ownedChannel]).
  final Duration? _budget;
  final AirtimePolicy _policy;
  final Duration _window;
  final DateTime Function() _clock;

  /// Rolling charges, oldest first. Pruned on every read.
  final List<({DateTime at, Duration amount})> _charges =
      <({DateTime at, Duration amount})>[];

  /// The policy this governor meters under.
  AirtimePolicy get policy => _policy;

  /// True when there is no voluntary cap. The meter still charges, so `used`
  /// and `STATUS` keep telling the truth.
  bool get unlimited => _budget == null;

  /// The cap, or one window when there is none. A caller that shows a number
  /// must check [unlimited] first rather than present this as a limit.
  Duration get budget => _budget ?? _window;
  Duration get window => _window;

  /// Airtime spent inside the current rolling window.
  Duration get used {
    final DateTime now = _clock();
    _charges.removeWhere(
        (({DateTime at, Duration amount}) c) => now.difference(c.at) >= _window);
    Duration total = Duration.zero;
    for (final ({DateTime at, Duration amount}) c in _charges) {
      total += c.amount;
    }
    return total;
  }

  Duration get remaining {
    final Duration? cap = _budget;
    if (cap == null) return _window; // one window is as much as time allows
    final Duration left = cap - used;
    return left.isNegative ? Duration.zero : left;
  }

  int get remainingMs => remaining.inMilliseconds;

  /// Airtime used this hour in 0.1 s units, the unit `STATUS` carries.
  int get usedTenthsThisHour => used.inMilliseconds ~/ 100;

  /// How many records costing [perRecord] each still fit this hour, clamped
  /// to 0..255 (the one byte `STATUS` carries; 255 means "255 or more").
  ///
  /// The gateway owns this figure because it alone knows the radio's preset:
  /// a client that had to compute it would need radio parameters, which the
  /// architecture keeps out of LDMUX. Zero when [perRecord] is not positive,
  /// so an unusable estimator never reads as unlimited.
  int opsLeft(Duration perRecord) {
    if (perRecord <= Duration.zero) return 0;
    final int n = remaining.inMicroseconds ~/ perRecord.inMicroseconds;
    return n > 255 ? 255 : n;
  }

  /// Whether [estimate] still fits. There is no raise path in v1.
  bool canSend(Duration estimate) {
    if (estimate <= Duration.zero) return true;
    return estimate <= remaining;
  }

  /// Record that airtime was spent. Never call this for a send the radio
  /// refused before transmitting.
  void charge(Duration airtime) {
    if (airtime <= Duration.zero) return;
    _charges.add((at: _clock(), amount: airtime));
  }

  void reset() => _charges.clear();
}

/// Time-on-air estimate for a record of a given length.
///
/// The default, 4 ms/byte, is calibrated to the USA/Canada preset only
/// (910.525 MHz / 62.5 kHz / SF7 / CR5: a 176-byte packet is 613 ms, 3.48
/// ms/byte, `meshmore-sns-architecture.md` §5.5a). It is **not** conservative
/// for slower presets: the same packet is ~9.4 ms/byte on EU/UK Narrow
/// (62.5 kHz / SF8 / CR8) and ~9.5 on EU/UK Deprecated (250 kHz / SF11).
/// A gateway on any other preset must be given [AirtimeEstimator.lora] built
/// from the radio's real parameters, or the governor under-counts airtime.
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
