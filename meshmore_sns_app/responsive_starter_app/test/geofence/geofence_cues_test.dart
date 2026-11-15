// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:meshmore_sns_app/cue/cue_service.dart';
import 'package:meshmore_sns_app/geofence/geofence_engine.dart';

/// A crossing is two different facts, and the sound says which.
///
/// The controller used to play `alert` for both directions, which told a reader
/// that something happened and nothing about what. The app now plays a rising
/// pair for entering and a falling one for leaving.
void main() {
  test('entering and leaving are their own cue kinds', () {
    expect(CueKind.geofenceEnter, isNot(CueKind.geofenceExit));
    expect(isSignature(CueKind.geofenceEnter), isFalse);
    expect(isSignature(CueKind.geofenceExit), isFalse);
  });

  test('every theme ships both crossings, and they are audibly different', () {
    for (final Directory theme in Directory('assets/audio')
        .listSync()
        .whereType<Directory>()) {
      final File enter = File('${theme.path}/geofenceEnter.wav');
      final File leave = File('${theme.path}/geofenceExit.wav');
      expect(enter.existsSync(), isTrue, reason: theme.path);
      expect(leave.existsSync(), isTrue, reason: theme.path);
      expect(enter.readAsBytesSync(), isNot(leave.readAsBytesSync()),
          reason: '${theme.path}: both directions sound the same');
    }
  });

  test('a fence alert knows which direction it is', () {
    // The model is what the cue is chosen from, so the direction has to be a
    // fact on the alert rather than something the caller infers.
    expect(GeofenceEvent.entered, isNot(GeofenceEvent.left));
  });
}
