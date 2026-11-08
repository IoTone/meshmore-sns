// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package io.iotone.meshcore.frames;

import io.iotone.meshcore.model.Contact;

/**
 * {@code PUSH_CODE_NEW_ADVERT} (0x8A) — the radio stored a newly heard node
 * by itself, and pushes the whole record.
 *
 * @param contact the record, byte-identical to a streamed contact
 */
public record NewAdvertFrame(Contact contact) implements MeshcoreInbound {

    @Override
    public String toString() {
        return "NewAdvertFrame(" + contact + ")";
    }
}
