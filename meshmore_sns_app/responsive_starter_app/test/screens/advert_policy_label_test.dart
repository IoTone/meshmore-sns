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
  // the picker's "Pinned" sent 1 and its "Device GPS" sent 2 — the
  // opposite of the shared definition above, with no way for a user to
  // tell which one they had actually chosen.
  //
  // CAVEAT: the app talks to companion firmware, which distinguishes
  // only NONE from "advertise sensors.node_lat/lon"
  // (`examples/companion_radio/NodePrefs.h:9-10` and `MyMesh.cpp:1252,
  // 1336,2251` at `companion-v1.17.1`). On a companion, 1 and 2 behave
  // identically and neither pins anything. These labels follow the
  // SHARED definition, which is what the firmware documents and what
  // the repeater / room / sensor builds implement.
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