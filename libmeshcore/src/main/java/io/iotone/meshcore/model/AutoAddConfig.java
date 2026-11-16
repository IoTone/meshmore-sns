// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package io.iotone.meshcore.model;

import io.iotone.meshcore.MeshcoreConstants;

/**
 * Decoded {@code RESP_CODE_AUTOADD_CONFIG} (0x19), {@code MyMesh.cpp:1988-1993}.
 *
 * <pre>
 * [19][flags][max_hops]
 * </pre>
 *
 * <p>This is the radio's own policy for storing a node it hears. It is the
 * radio's table, not the app's, so the app reads it and writes it back
 * whole rather than owning a parallel preference.</p>
 *
 * @param flags   the add-policy bit field; see the {@code AUTO_ADD_*} constants
 * @param maxHops 0 = no limit, 1 = direct only, N = up to N&#8722;1 hops
 */
public record AutoAddConfig(int flags, int maxHops) {

    /**
     * Whether a full table evicts its oldest non-favourite row.
     *
     * @return {@code true} when the overwrite-oldest bit is set
     */
    public boolean overwriteOldest() {
        return (flags & MeshcoreConstants.AUTO_ADD_OVERWRITE_OLDEST) != 0;
    }

    /**
     * Whether newly heard chat nodes are stored.
     *
     * @return {@code true} when the chat bit is set
     */
    public boolean chat() {
        return (flags & MeshcoreConstants.AUTO_ADD_CHAT) != 0;
    }

    /**
     * Whether newly heard repeaters are stored.
     *
     * @return {@code true} when the repeater bit is set
     */
    public boolean repeater() {
        return (flags & MeshcoreConstants.AUTO_ADD_REPEATER) != 0;
    }

    /**
     * Whether newly heard room servers are stored.
     *
     * @return {@code true} when the room-server bit is set
     */
    public boolean roomServer() {
        return (flags & MeshcoreConstants.AUTO_ADD_ROOM_SERVER) != 0;
    }

    /**
     * Whether newly heard sensors are stored.
     *
     * @return {@code true} when the sensor bit is set
     */
    public boolean sensor() {
        return (flags & MeshcoreConstants.AUTO_ADD_SENSOR) != 0;
    }

    @Override
    public String toString() {
        return String.format("AutoAddConfig(0x%02x, maxHops %d)", flags,
                maxHops);
    }
}
