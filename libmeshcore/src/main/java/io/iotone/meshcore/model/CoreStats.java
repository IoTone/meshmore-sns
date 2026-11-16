// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package io.iotone.meshcore.model;

/**
 * {@code RESP_CODE_STATS} (0x18) sub-type 0: the radio's own housekeeping.
 *
 * @param batteryMilliVolts battery voltage in millivolts
 * @param uptimeSecs        seconds since the radio booted
 * @param errFlags          the firmware's error-event bit field
 * @param queueLen          frames waiting in the radio's outbound queue
 */
public record CoreStats(
        int batteryMilliVolts, long uptimeSecs, int errFlags, int queueLen) {

    @Override
    public String toString() {
        return String.format(
                "CoreStats(batt %dmV, up %ds, err 0x%04x, queue %d)",
                batteryMilliVolts, uptimeSecs, errFlags, queueLen);
    }
}
