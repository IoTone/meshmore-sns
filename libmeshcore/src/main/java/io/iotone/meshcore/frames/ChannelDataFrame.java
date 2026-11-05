// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package io.iotone.meshcore.frames;

import io.iotone.meshcore.model.ChannelData;

/**
 * {@code RESP_CODE_CHANNEL_DATA_RECV} (0x1B) — a channel datagram.
 *
 * @param data the decoded datagram (application type, body, profile tag)
 */
public record ChannelDataFrame(ChannelData data) implements MeshcoreInbound {

    @Override
    public String toString() {
        return "ChannelDataFrame(" + data + ")";
    }
}
