// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package io.iotone.meshcore.model;

/**
 * One node's answer to a zero-hop discover request, carried in a
 * {@code PUSH_CODE_CONTROL_DATA} (0x8E) whose payload is a
 * {@code NODE_DISCOVER_RESP} (0x9X).
 *
 * <pre>
 * [0x9X | node_type][their snr x4][tag u32][pub_key 32 or 8]
 * </pre>
 *
 * <p>Both SNRs are kept because they answer different questions: theirs is
 * how well the repeater heard us, ours is how well we heard it, and a link
 * that is only good one way is the case worth seeing.</p>
 *
 * @param nodeType  the answering node's advertised type
 * @param tag       the discover tag the request carried
 * @param publicKey 32 bytes, or 8 when the request asked for prefixes only
 * @param theirSnrDb how well the answering node heard us
 * @param ourSnrDb   how well we heard it
 * @param ourRssi    the RSSI our radio recorded for it
 */
public record DiscoverResponse(
        int nodeType,
        long tag,
        byte[] publicKey,
        double theirSnrDb,
        double ourSnrDb,
        int ourRssi) {

    @Override
    public String toString() {
        return "DiscoverResponse(type " + nodeType + ", tag 0x"
                + Long.toHexString(tag) + ", key " + publicKey.length
                + "B, them " + theirSnrDb + ", us " + ourSnrDb + ")";
    }
}
