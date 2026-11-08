// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package io.iotone.meshcore.model;

/**
 * {@code RESP_CODE_STATS} (0x18) sub-type 2: packet counters since boot.
 *
 * <p>The struct grew in place once — the receive-error counter was appended
 * inside the same frame — so the last field is nullable: a firmware that
 * predates it sends six counters and a newer one sends seven, and neither
 * should lose the reading.</p>
 *
 * @param received      packets received
 * @param sent          packets sent
 * @param sentFlood     packets sent flood-routed
 * @param sentDirect    packets sent path-routed
 * @param receivedFlood packets received flood-routed
 * @param receivedDirect packets received path-routed
 * @param receiveErrors receive errors, absent on older firmware
 */
public record PacketStats(
        long received,
        long sent,
        long sentFlood,
        long sentDirect,
        long receivedFlood,
        long receivedDirect,
        Long receiveErrors) {

    @Override
    public String toString() {
        return "PacketStats(rx " + received + ", tx " + sent + ", txFlood "
                + sentFlood + ", txDirect " + sentDirect + ", rxFlood "
                + receivedFlood + ", rxDirect " + receivedDirect + ", rxErr "
                + receiveErrors + ")";
    }
}
