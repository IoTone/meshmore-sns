// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package io.iotone.meshcore.frames;

import io.iotone.meshcore.model.AdvertPath;

/**
 * {@code RESP_CODE_ADVERT_PATH} (0x16) — the route a contact's last advert
 * took, read from the radio's own record.
 *
 * @param advertPath the receipt time, path length and path bytes
 */
public record AdvertPathFrame(AdvertPath advertPath) implements MeshcoreInbound {

    @Override
    public String toString() {
        return "AdvertPathFrame(" + advertPath + ")";
    }
}
