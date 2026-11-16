// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package io.iotone.meshcore.frames;

/**
 * {@code PUSH_CODE_CONTACT_DELETED} (0x8F) — the radio removed a contact,
 * either because the user did or because auto-add overwrote the oldest
 * non-favourite row to make space.
 *
 * <p>A mirror of the table that does not follow this push shows a contact
 * that can no longer be addressed.</p>
 *
 * @param publicKey the 32-byte key of the removed contact; owned by the
 *                  record
 */
public record ContactDeletedFrame(byte[] publicKey) implements MeshcoreInbound {

    @Override
    public String toString() {
        return "ContactDeletedFrame()";
    }
}
