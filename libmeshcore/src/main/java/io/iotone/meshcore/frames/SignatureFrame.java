// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package io.iotone.meshcore.frames;

/**
 * {@code RESP_CODE_SIGNATURE} (0x14) — a 64-byte Ed25519 signature.
 *
 * @param signature the signature bytes; owned by the record
 */
public record SignatureFrame(byte[] signature) implements MeshcoreInbound {

    @Override
    public String toString() {
        return "SignatureFrame(" + signature.length + "B)";
    }
}
