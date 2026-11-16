// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package io.iotone.meshcore.frames;

import io.iotone.meshcore.model.DiscoverResponse;

/**
 * {@code PUSH_CODE_CONTROL_DATA} (0x8E) — a control packet another node
 * sent, with the physical-layer readings our radio recorded for it.
 *
 * <p>The firmware copies the payload straight after {@code path_len}, with
 * no path bytes whatever the length says ({@code MyMesh.cpp:2830-2840}), so
 * the payload is kept whole: a discover response is decoded out of it when
 * it is one, and everything else stays available unparsed.</p>
 *
 * @param snrDb    SNR our radio measured
 * @param rssi     RSSI our radio measured
 * @param pathLen  the path-length byte the packet carried
 * @param payload  the control payload, owned by the record
 * @param discover the decoded discover response, or {@code null} when the
 *                 payload is some other control packet
 */
public record ControlDataFrame(
        double snrDb,
        int rssi,
        int pathLen,
        byte[] payload,
        DiscoverResponse discover) implements MeshcoreInbound {

    @Override
    public String toString() {
        return "ControlDataFrame("
                + (discover != null ? discover : payload.length + "B") + ")";
    }
}
