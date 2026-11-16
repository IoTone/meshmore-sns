// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package io.iotone.meshcore.model;

import io.iotone.meshcore.MeshcoreConstants;

/**
 * Decoded {@code PUSH_CODE_TRACE_DATA} (0x89): a TRACE packet that reached
 * the end of its path.
 *
 * <pre>
 * [reserved][path_len][flags][tag u32][auth u32][hashes][snr x hops][final snr]
 * </pre>
 *
 * <p>{@code hopSnrsDb} has one entry per hop — the SNR at which that
 * repeater heard the packet — and {@code finalSnrDb} is what our own radio
 * heard the last hop at. The hop count is derived from {@code path_len} and
 * the hash width the flags announce, so the SNR block's length is not
 * carried anywhere.</p>
 *
 * @param tag        the trace tag the request named
 * @param authCode   the trace authentication code
 * @param flags      the trace flags; the low two bits are the hash code
 * @param pathHashes the raw hash bytes, {@link #hashSize()} per hop
 * @param hopSnrsDb  per-hop SNR in dB
 * @param finalSnrDb the SNR of the final hop into our own radio
 */
public record TraceResult(
        long tag,
        long authCode,
        int flags,
        byte[] pathHashes,
        double[] hopSnrsDb,
        double finalSnrDb) {

    /**
     * Bytes per path hash, from the flags.
     *
     * @return {@code 1 << (flags &amp; 3)}
     */
    public int hashSize() {
        return 1 << (flags & 0x03);
    }

    /**
     * Hops the trace crossed.
     *
     * @return the number of per-hop SNR readings
     */
    public int hopCount() {
        return hopSnrsDb.length;
    }

    @Override
    public String toString() {
        return "TraceResult(tag 0x" + Long.toHexString(tag) + ", "
                + hopCount() + " hops, final " + finalSnrDb + " dB)";
    }
}
