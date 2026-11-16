// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package io.iotone.meshcore.frames;

import io.iotone.meshcore.model.RepeaterStatus;

/**
 * {@code PUSH_CODE_STATUS_RESPONSE} (0x87) — a repeater's or sensor's
 * status reply, matched to our request by public-key prefix.
 *
 * <p>The firmware forwards the answering node's on-air status payload
 * verbatim ({@code MyMesh.cpp:718-724} copies {@code data[4..len]}), so its
 * length belongs to that node's firmware rather than to this layout; a tail
 * beyond the fields modelled here is consumed without being guessed at.</p>
 *
 * @param pubKeyPrefix the six-byte prefix naming the node that answered
 * @param status       the decoded struct, or {@code null} when the payload
 *                     is too short to be one
 */
public record StatusResponseFrame(byte[] pubKeyPrefix, RepeaterStatus status)
        implements MeshcoreInbound {

    @Override
    public String toString() {
        return "StatusResponseFrame(" + status + ")";
    }
}
