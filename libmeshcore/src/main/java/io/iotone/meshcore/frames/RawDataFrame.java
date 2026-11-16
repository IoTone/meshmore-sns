// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package io.iotone.meshcore.frames;

import io.iotone.meshcore.model.RxVia;

/**
 * {@code PUSH_CODE_RAW_DATA} (0x84) — a raw-custom packet the radio heard.
 *
 * <p>It carries no sender identity and the firmware never queues it
 * ({@code MyMesh.cpp:801-818}), so an app that is not listening when it
 * arrives loses it.</p>
 *
 * @param snrDb   SNR our radio measured, in dB
 * @param rssi    RSSI our radio measured, signed dBm
 * @param payload the packet body; owned by the record
 * @param via     which radio profile delivered it, when reported (0xFF is
 *                the frame's own "none" value)
 */
public record RawDataFrame(double snrDb, int rssi, byte[] payload, RxVia via)
        implements MeshcoreInbound {

    @Override
    public String toString() {
        return "RawDataFrame(" + payload.length + "B, rssi " + rssi
                + ", via " + via + ")";
    }
}
