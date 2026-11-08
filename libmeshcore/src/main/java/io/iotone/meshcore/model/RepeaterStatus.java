// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package io.iotone.meshcore.model;

/**
 * A repeater's (or sensor's) answer to {@code CMD_SEND_STATUS_REQ}: the
 * {@code RepeaterStats} struct as forwarded inside
 * {@code PUSH_CODE_STATUS_RESPONSE} (0x87).
 *
 * <p>The first 24 bytes are required; every later field was added by a
 * firmware release and is therefore nullable. A short struct decodes to the
 * fields it actually carried rather than failing, because an old repeater's
 * answer is still an answer.</p>
 *
 * @param batteryMilliVolts battery voltage in millivolts
 * @param txQueueLen        frames waiting in its outbound queue
 * @param noiseFloorDbm     its noise floor, signed dBm
 * @param lastRssi          RSSI of the last packet it heard
 * @param packetsReceived   packets received
 * @param packetsSent       packets sent
 * @param airTimeSecs       airtime used, seconds
 * @param uptimeSecs        seconds since it booted
 * @param sentFlood         flood-routed sends, when reported
 * @param sentDirect        path-routed sends, when reported
 * @param receivedFlood     flood-routed receives, when reported
 * @param receivedDirect    path-routed receives, when reported
 * @param errEvents         error events, when reported
 * @param lastSnrDb         SNR of the last packet, when reported
 * @param directDups        direct duplicates, when reported
 * @param floodDups         flood duplicates, when reported
 * @param rxAirTimeSecs     receive airtime, when reported
 * @param receiveErrors     receive errors, when reported
 */
public record RepeaterStatus(
        int batteryMilliVolts,
        int txQueueLen,
        int noiseFloorDbm,
        int lastRssi,
        long packetsReceived,
        long packetsSent,
        long airTimeSecs,
        long uptimeSecs,
        Long sentFlood,
        Long sentDirect,
        Long receivedFlood,
        Long receivedDirect,
        Integer errEvents,
        Double lastSnrDb,
        Integer directDups,
        Integer floodDups,
        Long rxAirTimeSecs,
        Long receiveErrors) {

    @Override
    public String toString() {
        return "RepeaterStatus(batt " + batteryMilliVolts + "mV, up "
                + uptimeSecs + "s, noise " + noiseFloorDbm + ", rssi "
                + lastRssi + ", rx " + packetsReceived + ", tx "
                + packetsSent + ")";
    }
}
