// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package io.iotone.meshcore.model;

/**
 * Decoded {@code RESP_CODE_CHANNEL_INFO} (0x12) — reply to GET_CHANNEL.
 *
 * <pre>
 * [12][ch_idx][name 32B NUL-padded][secret 16B]
 * </pre>
 *
 * <p>The secret field has two widths, and the frame length is the only
 * signal: an ordinary request is answered with 16 bytes (the AES-128 key,
 * {@code examples/companion_radio/MyMesh.cpp:1715-1721}), and a request that
 * asked for the full secret with a third byte of 32
 * ({@code 1F <index> 20}) is answered with all 32 bytes of
 * {@code GroupChannel.secret}. Both are accepted; a third width is a
 * failure rather than a guess. See
 * {@link io.iotone.meshcore.MeshcoreConstants#CHANNEL_SECRET_SIZE} and
 * {@link io.iotone.meshcore.crypto.ChannelCrypto#channelSecretFromPsk(byte[])}.</p>
 *
 * @param channelIdx channel slot index
 * @param name       channel name (NUL-trimmed)
 * @param psk        the channel pre-shared key as carried by the companion
 *                   protocol — 16 or 32 bytes; owned by the record — do not
 *                   mutate
 */
public record ChannelInfo(int channelIdx, String name, byte[] psk) {

    @Override
    public String toString() {
        return "ChannelInfo(idx: " + channelIdx + ", name: \"" + name + "\")";
    }
}
