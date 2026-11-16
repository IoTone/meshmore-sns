// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package io.iotone.meshcore.model;

/**
 * Decoded {@code PUSH_CODE_LOGIN_SUCCESS} (0x85) or
 * {@code PUSH_CODE_LOGIN_FAIL} (0x86), {@code MyMesh.cpp:677-707}.
 *
 * <pre>
 * success (new):    [85][permissions][pub6][server_ts u32][acl][fw_level]
 * success (legacy): [85][0][pub6]
 * fail:             [86][0][pub6]
 * </pre>
 *
 * <p>The frame grew in place once, so a reply shorter than a whole extension
 * is the legacy form and not a truncated new one. {@link #isLegacy()} is the
 * only honest way to tell them apart, because both continue with the same
 * six-byte prefix.</p>
 *
 * @param success         whether the server accepted the password
 * @param permissions     {@code data[6]} of the server reply (an admin bit,
 *                        among others); 0 for a failure
 * @param pubKeyPrefix    the six-byte prefix naming the server that answered
 * @param serverTimestamp the server's clock, new format only
 * @param aclPermissions  the ACL byte, new format only
 * @param firmwareLevel   the server's firmware level, new format only
 */
public record LoginResult(
        boolean success,
        int permissions,
        byte[] pubKeyPrefix,
        Long serverTimestamp,
        Integer aclPermissions,
        Integer firmwareLevel) {

    /**
     * True for a legacy repeater reply, which carries no extras.
     *
     * @return {@code true} when the reply succeeded with no timestamp
     */
    public boolean isLegacy() {
        return success && serverTimestamp == null;
    }

    @Override
    public String toString() {
        return "LoginResult(success=" + success + ", perm=" + permissions
                + (isLegacy() ? ", legacy)" : ")");
    }
}
