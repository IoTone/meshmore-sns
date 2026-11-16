// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package io.iotone.meshcore.frames;

/**
 * {@code RESP_CODE_CLI_REPLY} (0x1D) — one line of a command's output.
 *
 * <p>A {@code CMD_RUN_CLI_COMMAND} produces zero or more of these, each its
 * own frame, followed by {@code OK}. The line is {@link #text()} and carries
 * no framing beyond the frame length.</p>
 *
 * <p>Numbered with the replies, not the pushes: it only ever follows a
 * command the client sent. See {@code MeshcoreResponse#isPush()}.</p>
 *
 * @param text the reply line, decoded as UTF-8
 */
public record CliReplyFrame(String text) implements MeshcoreInbound {

    @Override
    public String toString() {
        return "CliReplyFrame(\"" + text + "\")";
    }
}
