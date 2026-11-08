// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package io.iotone.meshcore.model;

/**
 * Decoded {@code PUSH_CODE_PATH_DISCOVERY_RESPONSE} (0x8D),
 * {@code MyMesh.cpp:762-771}.
 *
 * <pre>
 * [8D][0][pub6][out_path_len][out_path][in_path_len][in_path]
 * </pre>
 *
 * <p>Both directions are carried because an asymmetric link is the
 * interesting answer: a route that works one way and not the other is what
 * path discovery exists to find.</p>
 *
 * @param pubKeyPrefix the six-byte prefix naming the node that answered
 * @param outPathLen   the route from us to it
 * @param outPath      those path bytes; owned by the record
 * @param inPathLen    the route from it to us
 * @param inPath       those path bytes; owned by the record
 */
public record PathDiscoveryResult(
        byte[] pubKeyPrefix,
        PathLen outPathLen,
        byte[] outPath,
        PathLen inPathLen,
        byte[] inPath) {

    @Override
    public String toString() {
        return "PathDiscoveryResult(out " + outPathLen + ", in " + inPathLen
                + ")";
    }
}
