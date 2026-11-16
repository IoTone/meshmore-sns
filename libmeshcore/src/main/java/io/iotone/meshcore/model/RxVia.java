// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package io.iotone.meshcore.model;

import io.iotone.meshcore.MeshcoreConstants;

/**
 * Which radio profile a received packet arrived on.
 *
 * <p>The receive frames carry a byte that the mainline firmware leaves
 * reserved (writes 0) and that a two-profile radio fills in: {@code 0xA0}
 * the primary radio, {@code 0xA1} the second one; otherwise the frame's own
 * "none" value (0 for a channel datagram, 0xFF for raw data). The value is
 * only meaningful when a second profile is on, so everything else reports
 * {@link #UNKNOWN}, which is also what a single-profile radio always
 * sends.</p>
 */
public enum RxVia {

    /**
     * Not reported: single-profile radio, mainline firmware, or a packet
     * that arrived over a non-radio ingress.
     */
    UNKNOWN,

    /** The primary radio profile. */
    PRIMARY,

    /** The second radio profile. */
    SECONDARY;

    /**
     * Maps the wire byte to a profile.
     *
     * <p>Any value outside the two tags the firmware writes is
     * {@link #UNKNOWN}, including both "none" sentinels.</p>
     *
     * @param wireByte the byte after SNR on the receive frame
     * @return the profile that delivered the packet
     */
    public static RxVia fromWireByte(int wireByte) {
        if (wireByte == MeshcoreConstants.RX_VIA_PRIMARY_TAG) {
            return PRIMARY;
        }
        if (wireByte == MeshcoreConstants.RX_VIA_SECONDARY_TAG) {
            return SECONDARY;
        }
        return UNKNOWN;
    }
}
