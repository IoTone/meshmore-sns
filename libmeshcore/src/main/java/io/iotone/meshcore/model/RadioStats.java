// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package io.iotone.meshcore.model;

/**
 * {@code RESP_CODE_STATS} (0x18) sub-type 1: what the radio hears.
 *
 * @param noiseFloorDbm the radio's own noise floor, signed dBm
 * @param lastRssi      RSSI of the last packet it heard, signed dBm
 * @param lastSnrDb     SNR of that packet, in dB
 * @param txAirSecs     seconds spent transmitting
 * @param rxAirSecs     seconds spent receiving
 */
public record RadioStats(
        int noiseFloorDbm,
        int lastRssi,
        double lastSnrDb,
        long txAirSecs,
        long rxAirSecs) {

    @Override
    public String toString() {
        return "RadioStats(noise " + noiseFloorDbm + " dBm, rssi " + lastRssi
                + ", snr " + lastSnrDb + ", tx " + txAirSecs + "s, rx "
                + rxAirSecs + "s)";
    }
}
