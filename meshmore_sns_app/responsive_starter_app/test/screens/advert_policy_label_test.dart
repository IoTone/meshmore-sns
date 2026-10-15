// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/screens/device_config_screen.dart';

void main() {
  // These integers are the FIRMWARE's, from MeshCore
  // `src/helpers/CommonCLI.h`:
  //   0 = ADVERT_LOC_NONE  — advertise no position at all
  //   1 = ADVERT_LOC_SHARE — advertise the LIVE sensor/GPS fix
  //   2 = ADVERT_LOC_PREFS — advertise the STORED (pinned) pair
  //
  // The labels used to be attached to 1 and 2 in the reverse order, so
  // selecting "Pinned" actually put the radio in SHARE (live) mode and a
  // typed coordinate pair was overwritten by the GPS reading.
  test('advert policy labels match the firmware integers: '
      '1 = Device GPS (SHARE, live fix), 2 = Pinned (PREFS, stored pair)',
      () async {
    final AppLocalizations en =
        await AppLocalizations.delegate.load(const Locale('en'));

    expect(advertPolicyLabel(en, 0), 'None');
    expect(advertPolicyLabel(en, 1), 'Device GPS',
        reason: 'ADVERT_LOC_SHARE (1) advertises the live sensor fix');
    expect(advertPolicyLabel(en, 2), 'Pinned',
        reason: 'ADVERT_LOC_PREFS (2) advertises the stored pair');
  });

  test('an out-of-range policy never throws (the value is device-supplied)',
      () async {
    final AppLocalizations en =
        await AppLocalizations.delegate.load(const Locale('en'));
    expect(advertPolicyLabel(en, 7), 'None');
    expect(advertPolicyLabel(en, -1), 'None');
  });

  test('Japanese labels map to the same integers', () async {
    final AppLocalizations ja =
        await AppLocalizations.delegate.load(const Locale('ja'));
    expect(advertPolicyLabel(ja, 1), 'デバイス GPS');
    expect(advertPolicyLabel(ja, 2), 'ピン留め');
  });
}