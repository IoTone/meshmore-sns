// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package io.iotone.meshcore;

/**
 * Response / push opcodes (Device &#8594; App) — the first byte of an
 * inbound frame.
 *
 * <p>Opcodes &#8805; 0x80 are asynchronous push notifications (not
 * direct replies to a command); see {@link #isPush()}.</p>
 *
 * <p>The split is the firmware's own, not a guess: every {@code PUSH_CODE_*}
 * sits at 0x80 and above under the block comment "these are _pushed_ to
 * client app at any time" ({@code examples/companion_radio/MyMesh.cpp:111-128}),
 * and every {@code RESP_CODE_*} below it — including the two that arrive
 * without the client asking for them in the same breath,
 * {@link #CHANNEL_DATA_RECV} (a queued item drained by
 * {@code CMD_SYNC_NEXT_MESSAGE}) and {@link #CLI_REPLY} (the output stream of
 * {@code CMD_RUN_CLI_COMMAND}) — because both answer a command the client
 * sent.</p>
 */
public enum MeshcoreResponse {

    /** {@code RESP_CODE_OK}. */
    OK(0x00),

    /** {@code RESP_CODE_ERR}. */
    ERROR(0x01),

    /** {@code RESP_CODE_CONTACTS_START}. */
    CONTACT_START(0x02),

    /** {@code RESP_CODE_CONTACT}. */
    CONTACT(0x03),

    /** {@code RESP_CODE_END_OF_CONTACTS}. */
    CONTACT_END(0x04),

    /** {@code RESP_CODE_SELF_INFO} — also the APP_START reply. */
    SELF_INFO(0x05),

    /** {@code RESP_CODE_SENT} — send confirmation. */
    MSG_SENT(0x06),

    /** {@code RESP_CODE_CONTACT_MSG_RECV} (legacy). */
    CONTACT_MSG_RECV(0x07),

    /** {@code RESP_CODE_CHANNEL_MSG_RECV} (legacy). */
    CHANNEL_MSG_RECV(0x08),

    /** {@code RESP_CODE_CURR_TIME}. */
    CURRENT_TIME(0x09),

    /** {@code RESP_CODE_NO_MORE_MESSAGES}. */
    NO_MORE_MSGS(0x0A),

    /** {@code RESP_CODE_EXPORT_CONTACT} — the radio's advert packet for a contact. */
    EXPORT_CONTACT(0x0B),

    /** {@code RESP_CODE_BATT_AND_STORAGE}. */
    BATTERY(0x0C),

    /** {@code RESP_CODE_PRIVATE_KEY} — a secret, redacted by the frame's toString. */
    PRIVATE_KEY(0x0E),

    /** {@code RESP_CODE_DISABLED} — the firmware was built without that command. */
    DISABLED(0x0F),

    /** {@code RESP_CODE_DEVICE_INFO}. */
    DEVICE_INFO(0x0D),

    /** {@code RESP_CODE_CONTACT_MSG_RECV_V3} (carries SNR). */
    CONTACT_MSG_RECV_V3(0x10),

    /** {@code RESP_CODE_CHANNEL_MSG_RECV_V3} (carries SNR). */
    CHANNEL_MSG_RECV_V3(0x11),

    /** {@code RESP_CODE_CHANNEL_INFO} — reply to GET_CHANNEL. */
    CHANNEL_INFO(0x12),

    /** {@code RESP_CODE_SIGN_START} — the radio will sign; names its buffer size. */
    SIGN_START(0x13),

    /** {@code RESP_CODE_SIGNATURE} — a 64-byte Ed25519 signature. */
    SIGNATURE(0x14),

    /** {@code RESP_CODE_ADVERT_PATH} — the route a contact's last advert took. */
    ADVERT_PATH(0x16),

    /** {@code RESP_CODE_TUNING_PARAMS} — the radio's own airtime limit. */
    TUNING_PARAMS(0x17),

    /** {@code RESP_CODE_STATS} — one reading, chosen by a sub-type byte. */
    STATS(0x18),

    /** {@code RESP_CODE_AUTOADD_CONFIG} — the radio's own contact add policy. */
    AUTOADD_CONFIG(0x19),

    /**
     * {@code RESP_CODE_CHANNEL_DATA_RECV} (27) — a channel datagram,
     * drained by {@code CMD_SYNC_NEXT_MESSAGE}. A reply, not a push: it is
     * only ever the radio handing over an item the client asked for.
     */
    CHANNEL_DATA_RECV(0x1B),

    /**
     * {@code RESP_CODE_CLI_REPLY} (29) — one line of a
     * {@code CMD_RUN_CLI_COMMAND}'s output.
     */
    CLI_REPLY(0x1D),

    /**
     * {@code RESP_CODE_CUSTOM_VARS} (21 = 0x15) — reply to
     * {@link MeshcoreCommand#GET_CUSTOM_VARS}. Payload: comma-separated
     * {@code name:value} pairs (ASCII, no NUL).
     */
    CUSTOM_VARS(0x15),

    /** {@code PUSH_CODE_ADVERTISEMENT}. */
    ADVERTISEMENT(0x80),

    /** {@code PUSH_CODE_PATH_UPDATED} — the radio replaced a contact's route. */
    PATH_UPDATED(0x81),

    /** {@code PUSH_CODE_ACK} — delivery acknowledgement. */
    ACK(0x82),

    /** {@code PUSH_CODE_MSGS_WAITING} — inbound items are queued. */
    MESSAGES_WAITING(0x83),

    /** {@code PUSH_CODE_RAW_DATA} — a raw-custom packet the radio heard. */
    RAW_DATA(0x84),

    /** {@code PUSH_CODE_LOGIN_SUCCESS} — a repeater accepted the sign-in. */
    LOGIN_SUCCESS(0x85),

    /** {@code PUSH_CODE_LOGIN_FAIL} — it refused. */
    LOGIN_FAIL(0x86),

    /** {@code PUSH_CODE_STATUS_RESPONSE} — a repeater's status struct. */
    STATUS_RESPONSE(0x87),

    /** {@code PUSH_CODE_LOG_RX_DATA} — RF log; safely ignorable. */
    LOG_DATA(0x88),

    /** {@code PUSH_CODE_TRACE_DATA} — a trace that completed its path. */
    TRACE_DATA(0x89),

    /** {@code PUSH_CODE_NEW_ADVERT} — the radio stored a newly heard node. */
    NEW_ADVERT(0x8A),

    /**
     * {@code PUSH_CODE_TELEMETRY_RESPONSE} (0x8B). Async push delivering
     * a telemetry payload either for self (immediate after a
     * {@code CMD_SEND_TELEMETRY_REQ} with len==4) or for a peer (arrives
     * some seconds later after the OTA round-trip). Wire format:
     * {@code [0x8B][reserved 1B][pubkey_prefix 6B][CayenneLPP payload]}.
     */
    TELEMETRY_RESPONSE(0x8B),

    /** {@code PUSH_CODE_PATH_DISCOVERY_RESPONSE} — routes in both directions. */
    PATH_DISCOVERY_RESPONSE(0x8D),

    /** {@code PUSH_CODE_CONTROL_DATA} — a control packet, with our SNR and RSSI. */
    CONTROL_DATA(0x8E),

    /** {@code PUSH_CODE_CONTACT_DELETED} — the radio dropped a contact. */
    CONTACT_DELETED(0x8F),

    /** {@code PUSH_CODE_CONTACTS_FULL} — it could not store one more. */
    CONTACTS_FULL(0x90),

    /** {@code PUSH_CODE_ONE_KEY_DM_REJECTED} — a stranger's DM was refused. */
    ONE_KEY_DM_REJECTED(0x91);

    private final int code;

    MeshcoreResponse(int code) {
        this.code = code;
    }

    /**
     * Returns the on-wire opcode byte.
     *
     * @return opcode in {@code [0, 255]}
     */
    public int code() {
        return code;
    }

    /**
     * Returns whether this opcode is an asynchronous push notification
     * (opcodes &#8805; 0x80) rather than a direct command reply.
     *
     * @return {@code true} for push codes
     */
    public boolean isPush() {
        return code >= 0x80;
    }
}
