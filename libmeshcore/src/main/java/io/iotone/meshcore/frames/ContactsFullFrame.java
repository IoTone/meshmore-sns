// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package io.iotone.meshcore.frames;

/**
 * {@code PUSH_CODE_CONTACTS_FULL} (0x90) — the radio could not store one
 * more contact.
 *
 * <p>A bare code with no payload: the useful fact is that the next advert
 * heard will be dropped, which is what the device-contacts screen says
 * rather than letting adverts disappear in silence.</p>
 */
public record ContactsFullFrame() implements MeshcoreInbound {

    @Override
    public String toString() {
        return "ContactsFullFrame()";
    }
}
