// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package io.iotone.meshcore.frames;

import io.iotone.meshcore.model.TraceResult;

/**
 * {@code PUSH_CODE_TRACE_DATA} (0x89) — a trace that completed its path.
 *
 * @param trace the route, its per-hop SNR and the final hop into our radio
 */
public record TraceDataFrame(TraceResult trace) implements MeshcoreInbound {

    @Override
    public String toString() {
        return "TraceDataFrame(" + trace + ")";
    }
}
