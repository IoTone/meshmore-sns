// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package io.iotone.meshcore.frames;

/**
 * {@code RESP_CODE_SIGN_START} (0x13) — the radio will sign, and names the
 * buffer size it accepted.
 *
 * @param maxLength the signing buffer size in bytes
 */
public record SignStartFrame(long maxLength) implements MeshcoreInbound {

    @Override
    public String toString() {
        return "SignStartFrame(" + maxLength + ")";
    }
}
