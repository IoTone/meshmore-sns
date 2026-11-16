// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package io.iotone.meshcore.model;

/**
 * Decoded {@code RESP_CODE_ADVERT_PATH} (0x16), {@code MyMesh.cpp:1864-1869}.
 *
 * <pre>
 * [16][recv_timestamp u32 LE][path_len][path hashes]
 * </pre>
 *
 * <p>The route a contact's last advert actually took, read from the radio's
 * own record: no mesh traffic is spent asking for it.</p>
 *
 * @param receivedAt device clock, seconds, when the advert was received
 * @param pathLen    the path-length byte, which decides the hash width
 * @param path       the path bytes; owned by the record — do not mutate
 */
public record AdvertPath(long receivedAt, PathLen pathLen, byte[] path) {

    @Override
    public String toString() {
        return "AdvertPath(" + pathLen + ", at " + receivedAt + ")";
    }
}
