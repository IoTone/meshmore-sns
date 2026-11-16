// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package io.iotone.meshcore.frames;

import io.iotone.meshcore.model.LoginResult;

/**
 * {@code PUSH_CODE_LOGIN_SUCCESS} (0x85) or {@code PUSH_CODE_LOGIN_FAIL}
 * (0x86) — a repeater or room server's answer to a sign-in.
 *
 * @param result the answer, including whether it is the legacy eight-byte
 *               form
 */
public record LoginResultFrame(LoginResult result) implements MeshcoreInbound {

    @Override
    public String toString() {
        return "LoginResultFrame(success=" + result.success() + ")";
    }
}
