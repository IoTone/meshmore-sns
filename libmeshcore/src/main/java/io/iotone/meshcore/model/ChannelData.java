// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package io.iotone.meshcore.model;

/**
 * Decoded {@code RESP_CODE_CHANNEL_DATA_RECV} (0x1B) — a channel datagram
 * drained by {@code CMD_SYNC_NEXT_MESSAGE}.
 *
 * <pre>
 * [1B][snr*4][via][reserved][channel][path_len][data_type u16 LE][len][data]
 * </pre>
 *
 * <p>Unlike a channel message (0x08/0x11) the payload is an application
 * datagram, not text: {@code data_type} names the format and {@code data}
 * is that format's bytes. The {@code path_len} of 0xFF marks a flood.</p>
 *
 * @param snrDb        SNR of the received packet, in dB
 * @param channelIndex channel slot the datagram arrived on
 * @param pathLen      hops, or 0xFF for a flood
 * @param dataType     application data type (little-endian u16)
 * @param data         the datagram body; owned by the record — do not
 *                     mutate
 * @param via          which radio profile delivered it, when reported
 */
public record ChannelData(
        double snrDb,
        int channelIndex,
        int pathLen,
        int dataType,
        byte[] data,
        RxVia via) {

    /**
     * True when the datagram was flood-routed rather than path-routed.
     *
     * @return {@code true} when {@code path_len} is the 0xFF flood marker
     */
    public boolean isFlood() {
        return pathLen == 0xFF;
    }

    @Override
    public String toString() {
        return String.format(
                "ChannelData(ch %d, via %s, type 0x%04x, %d B)",
                channelIndex, via, dataType, data.length);
    }
}
