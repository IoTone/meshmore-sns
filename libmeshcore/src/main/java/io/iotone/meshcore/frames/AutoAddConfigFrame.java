// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package io.iotone.meshcore.frames;

import io.iotone.meshcore.model.AutoAddConfig;

/**
 * {@code RESP_CODE_AUTOADD_CONFIG} (0x19) — the radio's own contact add
 * policy.
 *
 * @param config the flags byte and the hop limit
 */
public record AutoAddConfigFrame(AutoAddConfig config)
        implements MeshcoreInbound {

    @Override
    public String toString() {
        return "AutoAddConfigFrame(" + config + ")";
    }
}
