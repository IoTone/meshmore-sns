// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package io.iotone.meshcore.frames;

/**
 * {@code PUSH_CODE_ONE_KEY_DM_REJECTED} (0x91) — the radio refused a
 * stranger's direct message for want of a signed introduction.
 *
 * <p>Without this the sender is indistinguishable from silence: the message
 * never appears, so nothing says an attempt was made.</p>
 *
 * @param publicKey the 32-byte key of the sender whose message was refused;
 *                  owned by the record
 */
public record OneKeyRejectedFrame(byte[] publicKey) implements MeshcoreInbound {

    @Override
    public String toString() {
        return "OneKeyRejectedFrame(" + publicKey.length + " bytes)";
    }
}
