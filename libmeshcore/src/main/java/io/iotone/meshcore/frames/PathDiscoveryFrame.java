// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package io.iotone.meshcore.frames;

import io.iotone.meshcore.model.PathDiscoveryResult;

/**
 * {@code PUSH_CODE_PATH_DISCOVERY_RESPONSE} (0x8D) — the routes a node
 * found in both directions.
 *
 * @param result the answering prefix and both paths
 */
public record PathDiscoveryFrame(PathDiscoveryResult result)
        implements MeshcoreInbound {

    @Override
    public String toString() {
        return "PathDiscoveryFrame(" + result + ")";
    }
}
