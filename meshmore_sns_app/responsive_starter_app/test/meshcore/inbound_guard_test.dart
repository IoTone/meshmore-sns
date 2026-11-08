// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/app/app_errors.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';

import 'fake_transport.dart';

/// A frame runs through every tracker, and the count of frames that lost one
/// starts and stays at zero when nothing is wrong.
///
/// The isolation itself is tested where it lives (`runFrameTrackers`, in
/// `test/util/frame_trackers_test.dart`) with trackers that throw on purpose:
/// no production tracker throws today, and planting one in the controller to
/// make this file fail would put a test hook in shipped code. What this file
/// pins is the wiring — the counter exists, no frame loses a tracker on a
/// normal path, and the trackers that sit at the end of the list really do run,
/// because a throw in an earlier one used to take them with it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    AppErrors.clear();
  });

  Future<void> settle() async {
    for (int i = 0; i < 8; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('a channel message reaches the trackers at the end of the list',
      () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc =
        MeshcoreController(transportFactory: () async => fake);
    await mc.connect();
    fake.emit(selfInfoFrame());
    await settle();
    expect(mc.framesDropped, 0);

    fake.emit(channelMsgFrame(text: 'hello from the mesh'));
    await settle();

    // `_ingestChat` records the row, `_trackMessageHeat` scores it, and
    // `_logEvent` appends the feed line — three trackers in that order, so a
    // throw in any earlier one would have left all three undone.
    expect(mc.messagesFor(0).any((dynamic m) => '${m.text}'.contains('hello')),
        isTrue);
    expect(mc.messageHeatCounts(), isNotEmpty);
    expect(mc.framesDropped, 0);
    expect(AppErrors.records, isEmpty,
        reason: 'nothing threw, so nothing was recorded');
    mc.dispose();
  });

  test('a burst of frames keeps the counter at zero', () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc =
        MeshcoreController(transportFactory: () async => fake);
    await mc.connect();
    fake.emit(selfInfoFrame());
    fake.emit(deviceInfoFrame());
    fake.emit(batteryFrame(4000));
    fake.emit(currentTimeFrame());
    fake.emit(msgsWaitingFrame(count: 0));
    // A frame the codec cannot decode: the connection reports it as its own
    // error, so it never reaches a tracker and cannot be a lost frame.
    fake.emit(Uint8List.fromList(<int>[0x00, 0x00]));
    fake.emit(channelMsgFrame(text: 'still here'));
    await settle();
    expect(mc.framesDropped, 0);
    mc.dispose();
  });
}
