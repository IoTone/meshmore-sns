// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package io.iotone.meshcore.frames;

import io.iotone.meshcore.model.FrameStats;

/**
 * {@code RESP_CODE_STATS} (0x18) — one reading of the radio's counters.
 *
 * @param stats the reading; one struct is present per sub-type
 */
public record StatsFrame(FrameStats stats) implements MeshcoreInbound {

    @Override
    public String toString() {
        return "StatsFrame(" + stats + ")";
    }
}
