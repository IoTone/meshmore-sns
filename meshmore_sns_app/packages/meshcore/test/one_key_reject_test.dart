// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:meshcore/meshcore.dart';
import 'package:test/test.dart';

Uint8List _key(int seed) =>
    Uint8List.fromList(List<int>.generate(32, (int i) => (seed + i) & 0xFF));

DecodeErrorKind _kindOf(MeshcoreInbound out) =>
    (out as DecodeFailure).error.kind;

void main() {
  group('PUSH_CODE_ONE_KEY_DM_REJECTED (0x91)', () {
    test('is a push, not a reply', () {
      expect(MeshcoreResponse.oneKeyDmRejected.isPush, isTrue);
    });

    test('decodes the sender key and nothing else', () {
      final Uint8List key = _key(7);
      final Uint8List frame = Uint8List.fromList(<int>[0x91, ...key]);
      final MeshcoreInbound out = MeshcoreFrameCodec.decode(frame);
      expect(out, isA<OneKeyRejectedFrame>());
      expect((out as OneKeyRejectedFrame).publicKey, equals(key));
    });

    test('a short frame is a named failure, not an exception', () {
      final Uint8List frame =
          Uint8List.fromList(<int>[0x91, ..._key(1).sublist(0, 31)]);
      final MeshcoreInbound out = MeshcoreFrameCodec.decode(frame);
      expect(out, isA<DecodeFailure>());
      expect(_kindOf(out), DecodeErrorKind.truncated);
    });

    test('trailing bytes are refused, so a longer frame cannot pass', () {
      final Uint8List frame = Uint8List.fromList(<int>[0x91, ..._key(2), 0x00]);
      final MeshcoreInbound out = MeshcoreFrameCodec.decode(frame);
      expect(out, isA<DecodeFailure>());
      expect(_kindOf(out), DecodeErrorKind.trailingBytes);
    });
  });
}
