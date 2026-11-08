// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package io.iotone.meshcore.frames;

/**
 * {@code PUSH_CODE_PATH_UPDATED} (0x81) — the radio replaced a contact's
 * stored route.
 *
 * <p>The push names only the key, so the record has to be re-read
 * ({@code CMD_GET_CONTACT_BY_KEY}) to learn the new route: the firmware
 * replaces a stored path wholesale and never ages one out, so a route that
 * died stays dead until it is overwritten.</p>
 *
 * @param publicKey the 32-byte key of the contact whose route changed;
 *                  owned by the record
 */
public record PathUpdatedFrame(byte[] publicKey) implements MeshcoreInbound {

    @Override
    public String toString() {
        return "PathUpdatedFrame()";
    }
}
