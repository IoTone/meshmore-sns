// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';

import 'package:meshmore_sns_app/notifications/local_notifier.dart';

/// When the batch line goes away.
///
/// The call it guards is a platform cancel, so the rule that can be wrong is
/// this one: a batch standing for `ch:2` must not survive the user opening
/// `ch:2`, and must not be cleared by opening some other thread.
void main() {
  test('opening the thread the batch points at clears it', () {
    expect(digestClearedBy(opened: 'ch:2', digestPayload: 'ch:2'), isTrue);
    expect(digestClearedBy(opened: 'dm:beef', digestPayload: 'dm:beef'), isTrue);
  });

  test('another thread leaves it alone', () {
    expect(digestClearedBy(opened: 'ch:5', digestPayload: 'ch:2'), isFalse);
  });

  test('no batch showing means nothing to clear', () {
    expect(digestClearedBy(opened: 'ch:2', digestPayload: ''), isFalse);
    expect(digestClearedBy(opened: '', digestPayload: ''), isFalse);
  });
}
