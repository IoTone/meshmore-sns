// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package io.iotone.meshcore.frames;

/**
 * {@code RESP_CODE_EXPORT_CONTACT} (0x0B) — the radio's own advert packet
 * for a contact, ready to hand to another node as {@code meshcore://<hex>}.
 *
 * @param advertPacket the packet exactly as the radio exported it; owned by
 *                     the record
 */
public record ExportedContactFrame(byte[] advertPacket)
        implements MeshcoreInbound {

    @Override
    public String toString() {
        return "ExportedContactFrame(" + advertPacket.length + "B)";
    }
}
