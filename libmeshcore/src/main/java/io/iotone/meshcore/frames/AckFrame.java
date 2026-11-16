// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package io.iotone.meshcore.frames;

import java.util.OptionalLong;

/**
 * {@code PUSH_CODE_SEND_CONFIRMED} (0x82) — delivery acknowledgement for a
 * sent (direct) message.
 *
 * <p>Carries the 4-byte CRC tag the device reported as
 * {@link io.iotone.meshcore.model.MsgSent#expectedAck()}, so the client
 * can match it back to the originating message and mark it delivered.
 * Broadcast/channel messages are flood-routed and never produce an ACK.</p>
 *
 * <p>The firmware writes the round-trip time after the tag — a 9-byte frame
 * in total ({@code examples/companion_radio/MyMesh.cpp:418-422}) — so a
 * decoder that stops at the tag leaves bytes unexplained. A short frame
 * that carries only the tag is still accepted, with the trip time
 * absent.</p>
 *
 * @param ackCrc       the acknowledged message's CRC tag (u32 LE), equal to
 *                     the {@code expectedAck} returned when the message was
 *                     submitted
 * @param roundTripMs  milliseconds between send and ACK, when the frame
 *                     carried it
 */
public record AckFrame(long ackCrc, OptionalLong roundTripMs)
        implements MeshcoreInbound {

    /**
     * Convenience constructor for the tag-only form.
     *
     * @param ackCrc the acknowledged message's CRC tag
     */
    public AckFrame(long ackCrc) {
        this(ackCrc, OptionalLong.empty());
    }

    @Override
    public String toString() {
        return String.format("AckFrame(0x%08x%s)", ackCrc,
                roundTripMs.isPresent()
                        ? ", rtt " + roundTripMs.getAsLong() + " ms"
                        : "");
    }
}
