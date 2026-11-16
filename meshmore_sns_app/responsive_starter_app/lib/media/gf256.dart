// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

/// GF(2^8) arithmetic for the media forward-error-correction block.
///
/// The field is the one every Reed-Solomon implementation in this space uses:
/// the primitive polynomial `x^8 + x^4 + x^3 + x^2 + 1` (0x11D) with generator
/// element 2. Keeping the primitive explicit matters because two "GF(256)"
/// implementations that pick different polynomials produce codewords that
/// cannot repair each other.
final class Gf256 {
  Gf256()
      : _exp = Uint8List(512),
        _log = Int16List(256) {
    int x = 1;
    for (int i = 0; i < 255; i++) {
      _exp[i] = x;
      _log[x] = i;
      x <<= 1;
      if (x & 0x100 != 0) x ^= 0x11D;
    }
    // The table is doubled so multiplication can add logarithms without a
    // modulo on every call.
    for (int i = 255; i < 512; i++) {
      _exp[i] = _exp[i - 255];
    }
    _log[0] = 0; // never read: division by zero is refused before it is used
  }

  final Uint8List _exp;
  final Int16List _log;

  int add(int a, int b) => a ^ b;

  int mul(int a, int b) {
    if (a == 0 || b == 0) return 0;
    return _exp[_log[a] + _log[b]];
  }

  int div(int a, int b) {
    if (b == 0) throw ArgumentError.value(b, 'b', 'division by zero in GF');
    if (a == 0) return 0;
    return _exp[(_log[a] - _log[b] + 255) % 255];
  }

  /// The inverse, used by the interpolation the erasure decoder is built on.
  int inv(int a) {
    if (a == 0) throw ArgumentError.value(a, 'a', '0 has no inverse in GF');
    return _exp[255 - _log[a]];
  }

  /// `alpha^i` — the i-th evaluation point of a codeword. Distinct for every
  /// `i < 255`, which is why a block can be shorter than the field.
  int alpha(int i) => _exp[i % 255];

  /// Lagrange evaluation of the polynomial through [xs]/[ys] at [at].
  ///
  /// This is the whole of both directions: encoding evaluates the message
  /// polynomial at points past the message, and erasure decoding evaluates it
  /// at the points that never arrived. No Berlekamp-Massey is needed because
  /// the missing-chunk map already says *where* the holes are, which is an
  /// erasure code's easier case.
  int interpolate({
    required List<int> xs,
    required List<int> ys,
    required int at,
  }) {
    if (xs.length != ys.length || xs.isEmpty) {
      throw ArgumentError('xs and ys must be the same non-zero length');
    }
    int acc = 0;
    for (int i = 0; i < xs.length; i++) {
      int basis = 1;
      for (int j = 0; j < xs.length; j++) {
        if (i == j) continue;
        basis = mul(basis, div(add(at, xs[j]), add(xs[i], xs[j])));
      }
      acc = add(acc, mul(ys[i], basis));
    }
    return acc;
  }
}
