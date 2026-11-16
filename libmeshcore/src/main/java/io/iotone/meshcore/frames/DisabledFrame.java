// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package io.iotone.meshcore.frames;

/**
 * {@code RESP_CODE_DISABLED} (0x0F) — the radio's firmware was built without
 * the command that was just sent.
 *
 * <p>It is not an error and not silence: the command exists in the protocol,
 * this build has it switched off, and the answer arrives at once instead of
 * costing the caller a timeout.</p>
 */
public record DisabledFrame() implements MeshcoreInbound {

    @Override
    public String toString() {
        return "DisabledFrame()";
    }
}
