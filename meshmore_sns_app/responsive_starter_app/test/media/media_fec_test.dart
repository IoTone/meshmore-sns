// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:meshmore_sns_app/media/gf256.dart';
import 'package:meshmore_sns_app/media/media_fec.dart';

Uint8List block(int seed, int length) =>
    Uint8List.fromList(List<int>.generate(length, (int i) => (seed * 31 + i) & 0xFF));

void main() {
  final Gf256 gf = Gf256();

  test('GF(256) is the field the codeword claims', () {
    expect(gf.mul(0, 5), 0);
    expect(gf.mul(1, 5), 5);
    // 0x02 * 0x80 = 0x1D under x^8 + x^4 + x^3 + x^2 + 1 (0x11D).
    expect(gf.mul(0x02, 0x80), 0x1D);
    for (int a = 1; a < 256; a++) {
      expect(gf.mul(a, gf.inv(a)), 1, reason: 'no inverse for $a');
    }
  });

  test('interpolation reproduces a known polynomial through its points', () {
    // p(x) = 3x^2 + 5x + 7 evaluated by the same field.
    int p(int x) => gf.add(gf.add(gf.mul(3, gf.mul(x, x)), gf.mul(5, x)), 7);
    final List<int> xs = <int>[gf.alpha(0), gf.alpha(1), gf.alpha(2)];
    final List<int> ys = <int>[p(xs[0]), p(xs[1]), p(xs[2])];
    for (int i = 3; i < 8; i++) {
      expect(gf.interpolate(xs: xs, ys: ys, at: gf.alpha(i)), p(gf.alpha(i)));
    }
  });

  test('the block is 20 data chunks, and the parity counts are the ruling', () {
    expect(MediaFec.blockData, 20);
    expect(MediaFec.imageParity, 2);
    expect(MediaFec.voiceParity, 3);
    expect(MediaFec.imageParity / MediaFec.blockData, closeTo(0.10, 0.005));
    expect(MediaFec.voiceParity / MediaFec.blockData, closeTo(0.15, 0.005));
  });

  test('image parity repairs exactly 10 % of a block and no more', () {
    final MediaFec fec = MediaFec();
    final List<Uint8List> data = <Uint8List>[
      for (int i = 0; i < MediaFec.blockData; i++) block(i, 24),
    ];
    final List<Uint8List> parity =
        fec.encode(data, parity: MediaFec.imageParity);

    // Lose two of the twenty: recoverable.
    final List<Uint8List?> slots = <Uint8List?>[...data, ...parity];
    slots[3] = null;
    slots[17] = null;
    final List<Uint8List>? repaired = fec.repair(
      slots: slots,
      dataCount: MediaFec.blockData,
      parity: MediaFec.imageParity,
    );
    expect(repaired, isNotNull);
    expect(repaired![3], data[3]);
    expect(repaired[17], data[17]);
    expect(repaired[0], data[0]);

    // Lose a third: past the parity, and the decoder says so instead of
    // inventing bytes.
    final List<Uint8List?> tooMany = <Uint8List?>[...data, ...parity];
    tooMany[1] = null;
    tooMany[9] = null;
    tooMany[19] = null;
    expect(
      fec.repair(
          slots: tooMany,
          dataCount: MediaFec.blockData,
          parity: MediaFec.imageParity),
      isNull,
    );
  });

  test('voice parity repairs a fifteenth that image parity cannot', () {
    final MediaFec fec = MediaFec();
    final List<Uint8List> data = <Uint8List>[
      for (int i = 0; i < MediaFec.blockData; i++) block(i + 100, 8),
    ];
    final List<Uint8List> voice = fec.encode(data, parity: MediaFec.voiceParity);
    final List<Uint8List?> slots = <Uint8List?>[...data, ...voice];
    slots[0] = null;
    slots[10] = null;
    slots[19] = null;
    final List<Uint8List>? repaired = fec.repair(
        slots: slots, dataCount: MediaFec.blockData, parity: MediaFec.voiceParity);
    expect(repaired, isNotNull);
    expect(repaired![0], data[0]);
    expect(repaired[10], data[10]);
    expect(repaired[19], data[19]);
  });

  test('every parity byte is a real check, not a copy', () {
    final MediaFec fec = MediaFec();
    final List<Uint8List> data = <Uint8List>[
      for (int i = 0; i < 4; i++) block(i, 6),
    ];
    final List<Uint8List> parity = fec.encode(data, parity: 2);
    for (final Uint8List p in parity) {
      expect(data.any((Uint8List d) => d.toString() == p.toString()), isFalse);
    }
  });

  test('a block longer than the ruling is refused, not silently shortened', () {
    final MediaFec fec = MediaFec();
    expect(
      () => fec.encode(
        <Uint8List>[for (int i = 0; i <= MediaFec.blockData; i++) Uint8List(1)],
        parity: 2,
      ),
      throwsArgumentError,
    );
  });
}
