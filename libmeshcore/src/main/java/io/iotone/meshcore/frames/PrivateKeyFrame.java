// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package io.iotone.meshcore.frames;

/**
 * {@code RESP_CODE_PRIVATE_KEY} (0x0E) — the radio's own private key,
 * exported.
 *
 * <p>The key is a secret, so {@link #toString()} redacts it: a decoded frame
 * reaches logs and diagnostics dumps, and a key in a log is a key leaked.</p>
 *
 * @param privateKey the 64-byte private key; owned by the record
 */
public record PrivateKeyFrame(byte[] privateKey) implements MeshcoreInbound {

    @Override
    public String toString() {
        return "PrivateKeyFrame(<redacted " + privateKey.length + "B>)";
    }
}
