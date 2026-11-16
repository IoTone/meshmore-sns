// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_transport.dart';

/// The radio tags each received frame with the profile that heard it.
///
/// Two frame types carry the tag: `RESP_CODE_CHANNEL_DATA_RECV` (0x1B) and
/// `PUSH_CODE_RAW_DATA` (0x84). A two-profile radio writes `0xA0` for the
/// primary and `0xA1` for the second; everything else — a single-profile radio,
/// mainline firmware, a bridge — writes the frame's own "none" value, which
/// decodes to [RxVia.unknown].
///
/// The app reports that a second profile exists and refuses to configure it:
/// the codec has no command that writes one, and the cost (a second profile
/// takes nearly all of the radio's transmit time) belongs to the radio's own
/// configuration. These cases pin the reporting half, including the part that
/// is easy to get wrong: silence is not evidence of a single-profile radio.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// A `0x1B` channel datagram: snr, via, reserved, channel, pathLen,
  /// dataType (u16), len, payload.
  Uint8List channelDataFrame(int viaTag) => Uint8List.fromList(<int>[
        0x1B,
        0x20,
        viaTag,
        0x00,
        0x01,
        0xFF,
        0x0A,
        0x00,
        0x02,
        0xDE,
        0xAD,
      ]);

  /// A `0x84` raw-data push: snr, rssi, via, payload.
  Uint8List rawDataFrame(int viaTag) => Uint8List.fromList(<int>[
        0x84,
        0x20,
        0x40,
        viaTag,
        0xAA,
        0xBB,
        0xCC,
      ]);

  Future<void> settle() async {
    for (int i = 0; i < 6; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<MeshcoreController> connected(FakeMeshcoreTransport fake) async {
    final MeshcoreController mc =
        MeshcoreController(transportFactory: () async => fake);
    await mc.connect();
    fake.emit(selfInfoFrame());
    await settle();
    return mc;
  }

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test(
      'no frame on the second profile reads as "nothing heard", not as one '
      'profile', () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = await connected(fake);
    expect(mc.radio2Seen, isFalse);
    expect(mc.radio2LastSeen, isNull,
        reason: 'nothing heard is not a timestamp');
    mc.dispose();
  });

  test('a channel datagram heard on the second profile is recorded', () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = await connected(fake);
    fake.emit(channelDataFrame(kRxViaSecondaryTag));
    await settle();
    expect(mc.radio2Seen, isTrue);
    expect(mc.radio2LastSeen, isNotNull);
    mc.dispose();
  });

  test('a raw-data push heard on the second profile is recorded', () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = await connected(fake);
    fake.emit(rawDataFrame(kRxViaSecondaryTag));
    await settle();
    expect(mc.radio2Seen, isTrue);
    mc.dispose();
  });

  test('the primary profile and an untagged frame record nothing', () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = await connected(fake);
    fake.emit(channelDataFrame(kRxViaPrimaryTag));
    fake.emit(rawDataFrame(kRxViaPrimaryTag));
    // The "none" values both frame types write on a single-profile radio.
    fake.emit(channelDataFrame(0x00));
    fake.emit(rawDataFrame(0xFF));
    await settle();
    expect(mc.radio2LastSeen, isNull);
    mc.dispose();
  });

  test('a later frame on the second profile moves the time forward', () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = await connected(fake);
    fake.emit(channelDataFrame(kRxViaSecondaryTag));
    await settle();
    final DateTime first = mc.radio2LastSeen!;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    fake.emit(rawDataFrame(kRxViaSecondaryTag));
    await settle();
    expect(mc.radio2LastSeen!.isAfter(first), isTrue,
        reason: 'the line states when it was last heard, not when it was '
            'first heard');
    mc.dispose();
  });
}
