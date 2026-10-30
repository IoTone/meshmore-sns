// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:test/test.dart';
import 'package:meshcore_gateway/meshcore_gateway.dart';

void main() {
  // The budget is a policy (architecture §5.5b). The default is the voluntary
  // 1 % duty cycle; the other mode says the channel is ours, so the margin is
  // not needed. Neither mode is a regulatory permission: the radio keeps its
  // own limit, and a caller showing a number must know which mode it is in.
  test('the default policy is 36 s of airtime per hour', () {
    expect(AirtimePolicy.onePercentDutyCycle.hourlyBudget,
        const Duration(seconds: 36));
    final Governor g = Governor.forPolicy(AirtimePolicy.onePercentDutyCycle);
    expect(g.unlimited, isFalse);
    expect(g.budget, const Duration(seconds: 36));
    expect(g.policy, AirtimePolicy.onePercentDutyCycle);
  });

  test('the owned-channel policy has no voluntary cap but still meters', () {
    final Governor g = Governor.forPolicy(AirtimePolicy.ownedChannel);
    expect(g.unlimited, isTrue);
    expect(AirtimePolicy.ownedChannel.hourlyBudget, isNull);
    expect(AirtimePolicy.ownedChannel.isUnlimited, isTrue);

    // No cap means any single record fits and the count saturates the one byte
    // STATUS carries instead of reading as zero.
    expect(g.canSend(const Duration(seconds: 600)), isTrue);
    expect(g.opsLeft(const Duration(milliseconds: 613)), 255);

    // Charging still happens, so `used` and STATUS stay honest in this mode.
    g.charge(const Duration(seconds: 500));
    expect(g.used, const Duration(seconds: 500));
    expect(g.usedTenthsThisHour, 5000);
    expect(g.canSend(const Duration(seconds: 600)), isTrue);
  });

  test('a capped governor still refuses beyond its budget', () {
    final Governor g = Governor.forPolicy(AirtimePolicy.onePercentDutyCycle);
    g.charge(const Duration(seconds: 36));
    expect(g.canSend(const Duration(milliseconds: 613)), isFalse);
    expect(g.remaining, Duration.zero);
    expect(g.opsLeft(const Duration(milliseconds: 613)), 0);
  });
}
