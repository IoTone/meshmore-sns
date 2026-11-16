// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package io.iotone.meshcore.model;

import io.iotone.meshcore.MeshcoreConstants;

/**
 * A MeshCore {@code path_len} byte: top 2 bits = hash size &#8722; 1, low
 * 6 bits = hop count ({@code src/Packet.cpp:20-30}, {@code Packet::writePath}).
 *
 * <p>The byte is otherwise arbitrary, so a phone can hold one the radio
 * rejects: a hash size of 4 is reserved and refused outright, and the path
 * must fit {@link MeshcoreConstants#MAX_PATH_SIZE}.</p>
 */
public record PathLen(int raw) {

    /**
     * Bytes per hash on this path.
     *
     * @return 1..4, where 4 is the reserved code
     */
    public int hashSize() {
        return (raw >> MeshcoreConstants.PATH_HASH_SIZE_SHIFT) + 1;
    }

    /**
     * Hops this path names.
     *
     * @return 0..63
     */
    public int hopCount() {
        return raw & MeshcoreConstants.PATH_HOP_MASK;
    }

    /**
     * Bytes of path data that follow the length byte.
     *
     * @return {@code hashSize &#215; hopCount}
     */
    public int byteLength() {
        return hashSize() * hopCount();
    }

    /**
     * Whether the firmware would accept this byte as a path length.
     *
     * <p>Two rules, both from {@code Packet::isValidPathLen}
     * ({@code src/Packet.cpp:17-22}).</p>
     *
     * @return {@code true} when the hash code is not the reserved one and
     *         the path fits the buffer
     */
    public boolean isValid() {
        return (raw >> MeshcoreConstants.PATH_HASH_SIZE_SHIFT)
                != MeshcoreConstants.PATH_HASH_SIZE_RESERVED_CODE
                && byteLength() <= MeshcoreConstants.MAX_PATH_SIZE;
    }

    @Override
    public String toString() {
        return "PathLen(" + hopCount() + " hop x " + hashSize() + " B)";
    }
}
