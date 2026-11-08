// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package io.iotone.meshcore.model;

/**
 * One {@code RESP_CODE_STATS} (0x18) reading: exactly one of the three
 * structs is present, because the sub-type byte chooses which was sent.
 *
 * @param core    the housekeeping struct, when sub-type 0 was sent
 * @param radio   the receiver struct, when sub-type 1 was sent
 * @param packets the packet counters, when sub-type 2 was sent
 */
public record FrameStats(CoreStats core, RadioStats radio, PacketStats packets) {

    /**
     * The one struct this reading carries.
     *
     * @return whichever of the three is present, or {@code null} if none
     */
    public Object present() {
        if (core != null) {
            return core;
        }
        return radio != null ? radio : packets;
    }

    @Override
    public String toString() {
        return "FrameStats(" + present() + ")";
    }
}
