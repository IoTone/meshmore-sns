// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package io.iotone.meshcore.model;

/**
 * Decoded {@code RESP_CODE_TUNING_PARAMS} (0x17), {@code MyMesh.cpp:1443-1450}.
 *
 * <pre>
 * [17][rx_delay_base x1000 u32 LE][airtime_factor x1000 u32 LE]
 * </pre>
 *
 * @param rxDelayBaseSeconds the radio's receive-delay base, in seconds
 * @param airtimeFactor      the airtime factor {@code af}: the radio may
 *                           transmit {@code 1 / (1 + af)} of the time
 *                           ({@code src/Dispatcher.cpp:25-27}); 0 means no
 *                           limit
 */
public record TuningParams(double rxDelayBaseSeconds, double airtimeFactor) {

    @Override
    public String toString() {
        return "TuningParams(rx=" + rxDelayBaseSeconds + "s, af="
                + airtimeFactor + ")";
    }
}
