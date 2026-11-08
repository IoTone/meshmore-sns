// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package io.iotone.meshcore.codec;

import io.iotone.meshcore.MeshcoreCommand;
import io.iotone.meshcore.MeshcoreConstants;
import io.iotone.meshcore.frames.AckFrame;
import io.iotone.meshcore.frames.AdvertFrame;
import io.iotone.meshcore.frames.AdvertPathFrame;
import io.iotone.meshcore.frames.AutoAddConfigFrame;
import io.iotone.meshcore.frames.BatteryStorageFrame;
import io.iotone.meshcore.frames.ChannelDataFrame;
import io.iotone.meshcore.frames.ChannelInfoFrame;
import io.iotone.meshcore.frames.ChannelMessageFrame;
import io.iotone.meshcore.frames.CliReplyFrame;
import io.iotone.meshcore.frames.ContactDeletedFrame;
import io.iotone.meshcore.frames.ContactFrame;
import io.iotone.meshcore.frames.ContactMessageFrame;
import io.iotone.meshcore.frames.ContactsFullFrame;
import io.iotone.meshcore.frames.ContactsStartFrame;
import io.iotone.meshcore.frames.ControlDataFrame;
import io.iotone.meshcore.frames.CurrentTimeFrame;
import io.iotone.meshcore.frames.CustomVarsFrame;
import io.iotone.meshcore.frames.DecodeFailure;
import io.iotone.meshcore.frames.DeviceInfoFrame;
import io.iotone.meshcore.frames.DisabledFrame;
import io.iotone.meshcore.frames.EndOfContactsFrame;
import io.iotone.meshcore.frames.ErrorFrame;
import io.iotone.meshcore.frames.ExportedContactFrame;
import io.iotone.meshcore.frames.LoginResultFrame;
import io.iotone.meshcore.frames.MeshcoreInbound;
import io.iotone.meshcore.frames.MessagesWaitingFrame;
import io.iotone.meshcore.frames.MsgSentFrame;
import io.iotone.meshcore.frames.NewAdvertFrame;
import io.iotone.meshcore.frames.NoMoreMessagesFrame;
import io.iotone.meshcore.frames.OkFrame;
import io.iotone.meshcore.frames.OneKeyRejectedFrame;
import io.iotone.meshcore.frames.PathDiscoveryFrame;
import io.iotone.meshcore.frames.PathUpdatedFrame;
import io.iotone.meshcore.frames.PrivateKeyFrame;
import io.iotone.meshcore.frames.RawDataFrame;
import io.iotone.meshcore.frames.RfLogFrame;
import io.iotone.meshcore.frames.SelfInfoFrame;
import io.iotone.meshcore.frames.SignStartFrame;
import io.iotone.meshcore.frames.SignatureFrame;
import io.iotone.meshcore.frames.StatsFrame;
import io.iotone.meshcore.frames.StatusResponseFrame;
import io.iotone.meshcore.frames.TelemetryResponseFrame;
import io.iotone.meshcore.frames.TraceDataFrame;
import io.iotone.meshcore.frames.TuningParamsFrame;
import io.iotone.meshcore.frames.UnsupportedFrame;
import io.iotone.meshcore.model.Advert;
import io.iotone.meshcore.model.AdvertPath;
import io.iotone.meshcore.model.AutoAddConfig;
import io.iotone.meshcore.model.BatteryStorage;
import io.iotone.meshcore.model.ChannelData;
import io.iotone.meshcore.model.ChannelInfo;
import io.iotone.meshcore.model.ChannelMessage;
import io.iotone.meshcore.model.Contact;
import io.iotone.meshcore.model.ContactMessage;
import io.iotone.meshcore.model.CoreStats;
import io.iotone.meshcore.model.DeviceInfo;
import io.iotone.meshcore.model.DiscoverResponse;
import io.iotone.meshcore.model.FrameStats;
import io.iotone.meshcore.model.LoginResult;
import io.iotone.meshcore.model.MsgSent;
import io.iotone.meshcore.model.PacketStats;
import io.iotone.meshcore.model.PathDiscoveryResult;
import io.iotone.meshcore.model.PathLen;
import io.iotone.meshcore.model.RadioParams;
import io.iotone.meshcore.model.RadioStats;
import io.iotone.meshcore.model.RepeaterStatus;
import io.iotone.meshcore.model.RfLog;
import io.iotone.meshcore.model.RxVia;
import io.iotone.meshcore.model.SelfInfo;
import io.iotone.meshcore.model.TraceResult;
import io.iotone.meshcore.model.TuningParams;

import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.OptionalInt;
import java.util.OptionalLong;

/**
 * Encodes app&#8594;device command frames and decodes device&#8594;app
 * frames.
 *
 * <p>Frame = {@code [opcode][payload]}, one frame per BLE
 * write/notification, little-endian. All layouts are pinned (see
 * {@link MeshcoreConstants#FIRMWARE_PIN_TAG}). This class mirrors the
 * Dart reference codec byte-for-byte; both are validated against the
 * same JSON golden vectors.</p>
 *
 * <p>{@link #decode(byte[])} is <strong>total</strong>: it returns a
 * {@link DecodeFailure} for malformed or truncated input and an
 * {@link UnsupportedFrame} for opcodes this codec does not model. It
 * never throws.</p>
 */
public final class MeshcoreFrameCodec {

    private MeshcoreFrameCodec() {
        // Static codec only.
    }

    // ---------------------------------------------------------------------
    // Encoders (App → Device)
    // ---------------------------------------------------------------------

    /**
     * {@code CMD_APP_START} (0x01): {@code 01 [7 reserved] [app name]}.
     *
     * <p>Firmware requires {@code len >= 8} and ignores bytes 1..7. The
     * app name is the trailing UTF-8 bytes (no NUL terminator;
     * frame-length delimited).</p>
     *
     * @param appName application name announced to the device
     * @return the encoded frame
     */
    public static byte[] appStart(String appName) {
        return new FrameBuilder()
                .u8(MeshcoreCommand.APP_START.code())
                .zeros(7)
                .utf8String(appName)
                .build();
    }

    /**
     * {@code CMD_GET_CONTACTS} (0x04), full dump.
     *
     * @return the encoded frame
     */
    public static byte[] getContacts() {
        return new FrameBuilder()
                .u8(MeshcoreCommand.GET_CONTACTS.code())
                .build();
    }

    /**
     * {@code CMD_GET_CONTACTS} (0x04), filtered to contacts modified
     * at/after {@code since} (uint32 unix seconds) for incremental sync.
     *
     * @param since lower bound on {@code lastMod}
     * @return the encoded frame
     */
    public static byte[] getContacts(long since) {
        return new FrameBuilder()
                .u8(MeshcoreCommand.GET_CONTACTS.code())
                .u32(since)
                .build();
    }

    /**
     * {@code CMD_GET_DEVICE_TIME} (0x05).
     *
     * @return the encoded frame
     */
    public static byte[] getDeviceTime() {
        return new FrameBuilder()
                .u8(MeshcoreCommand.GET_DEVICE_TIME.code())
                .build();
    }

    /**
     * {@code CMD_SET_DEVICE_TIME} (0x06): {@code 06 [unix uint32 LE]}.
     *
     * @param unixSeconds time to set, unix seconds
     * @return the encoded frame
     */
    public static byte[] setDeviceTime(long unixSeconds) {
        return new FrameBuilder()
                .u8(MeshcoreCommand.SET_DEVICE_TIME.code())
                .u32(unixSeconds)
                .build();
    }

    /**
     * {@code CMD_SYNC_NEXT_MESSAGE} (0x0A) — pull the next queued
     * inbound message.
     *
     * @return the encoded frame
     */
    public static byte[] syncNextMessage() {
        return new FrameBuilder()
                .u8(MeshcoreCommand.SYNC_NEXT_MESSAGE.code())
                .build();
    }

    /**
     * {@code CMD_SEND_CHANNEL_TXT_MSG} (0x03):
     * {@code 03 [txt_type] [channel_idx] [timestamp u32 LE] [text]}.
     *
     * <p>The app sends plaintext + channel index; the device performs
     * the over-the-air channel encryption.</p>
     *
     * @param channelIdx target channel slot
     * @param timestamp  sender timestamp (unix seconds)
     * @param text       message text (UTF-8)
     * @param txtType    text type (normally
     *                   {@link MeshcoreConstants#TXT_TYPE_PLAIN})
     * @return the encoded frame
     */
    public static byte[] sendChannelTextMessage(
            int channelIdx, long timestamp, String text, int txtType) {
        return new FrameBuilder()
                .u8(MeshcoreCommand.SEND_CHANNEL_MESSAGE.code())
                .u8(txtType)
                .u8(channelIdx)
                .u32(timestamp)
                .utf8String(text)
                .build();
    }

    /**
     * {@code CMD_SEND_CHANNEL_TXT_MSG} with
     * {@code txt_type = TXT_TYPE_PLAIN}.
     *
     * @param channelIdx target channel slot
     * @param timestamp  sender timestamp (unix seconds)
     * @param text       message text (UTF-8)
     * @return the encoded frame
     */
    public static byte[] sendChannelTextMessage(
            int channelIdx, long timestamp, String text) {
        return sendChannelTextMessage(channelIdx, timestamp, text,
                MeshcoreConstants.TXT_TYPE_PLAIN);
    }

    /**
     * {@code CMD_SEND_TXT_MSG} (0x02):
     * {@code 02 [txt_type] [attempt] [timestamp u32 LE]
     * [pubkey_prefix 6] [text]}.
     *
     * <p>The recipient is addressed by the first 6 bytes of its public
     * key (truncated/zero-padded to exactly 6).</p>
     *
     * @param pubKeyPrefix recipient public-key prefix
     * @param timestamp    sender timestamp (unix seconds)
     * @param text         message text (UTF-8)
     * @param txtType      text type
     * @param attempt      retry attempt counter
     * @return the encoded frame
     */
    public static byte[] sendTextMessage(
            byte[] pubKeyPrefix,
            long timestamp,
            String text,
            int txtType,
            int attempt) {
        return new FrameBuilder()
                .u8(MeshcoreCommand.SEND_TEXT_MESSAGE.code())
                .u8(txtType)
                .u8(attempt)
                .u32(timestamp)
                .fixed(pubKeyPrefix, MeshcoreConstants.PUB_KEY_PREFIX_SIZE)
                .utf8String(text)
                .build();
    }

    /**
     * {@code CMD_SEND_TXT_MSG} with plain text type and attempt 0.
     *
     * @param pubKeyPrefix recipient public-key prefix (6 bytes)
     * @param timestamp    sender timestamp (unix seconds)
     * @param text         message text (UTF-8)
     * @return the encoded frame
     */
    public static byte[] sendTextMessage(
            byte[] pubKeyPrefix, long timestamp, String text) {
        return sendTextMessage(pubKeyPrefix, timestamp, text,
                MeshcoreConstants.TXT_TYPE_PLAIN, 0);
    }

    /**
     * {@code CMD_SEND_SELF_ADVERT} (0x07):
     * {@code 07 [1=flood | 0=zero-hop]}.
     *
     * @param flood {@code true} = flood the advert, {@code false} =
     *              zero-hop only
     * @return the encoded frame
     */
    public static byte[] sendSelfAdvert(boolean flood) {
        return new FrameBuilder()
                .u8(MeshcoreCommand.SEND_SELF_ADVERT.code())
                .u8(flood ? 1 : 0)
                .build();
    }

    /**
     * {@code CMD_SET_ADVERT_NAME} (0x08):
     * {@code 08 [name UTF-8, ≤ 31 bytes]} (longer names are truncated
     * at the byte level).
     *
     * @param name advertised node name
     * @return the encoded frame
     */
    public static byte[] setAdvertName(String name) {
        byte[] n = name.getBytes(StandardCharsets.UTF_8);
        byte[] capped = n.length > MeshcoreConstants.MAX_ADVERT_NAME
                ? Arrays.copyOfRange(n, 0, MeshcoreConstants.MAX_ADVERT_NAME)
                : n;
        return new FrameBuilder()
                .u8(MeshcoreCommand.SET_ADVERT_NAME.code())
                .raw(capped)
                .build();
    }

    /**
     * {@code CMD_REMOVE_CONTACT} (0x0F): remove a contact by 32-byte
     * public key (frees a slot in the radio's contact table).
     *
     * @param publicKey the contact's full public key
     * @return the encoded frame
     */
    public static byte[] removeContact(byte[] publicKey) {
        return new FrameBuilder()
                .u8(MeshcoreCommand.REMOVE_CONTACT.code())
                .fixed(publicKey, MeshcoreConstants.PUB_KEY_SIZE)
                .build();
    }

    /**
     * {@code CMD_ADD_UPDATE_CONTACT} (0x09): the 148-byte contact body
     * (same layout as {@code RESP_CODE_CONTACT}).
     *
     * @param c contact to add or replace
     * @return the encoded frame
     */
    public static byte[] addUpdateContact(Contact c) {
        return new FrameBuilder()
                .u8(MeshcoreCommand.ADD_UPDATE_CONTACT.code())
                .fixed(c.publicKey(), MeshcoreConstants.PUB_KEY_SIZE)
                .u8(c.type())
                .u8(c.flags())
                .u8(c.outPathLen())
                .fixed(c.outPath(), MeshcoreConstants.MAX_PATH_SIZE)
                .fixed(c.name().getBytes(StandardCharsets.UTF_8),
                        MeshcoreConstants.CONTACT_NAME_SIZE)
                .u32(c.lastAdvertTimestamp())
                .i32(c.latitudeMicros())
                .i32(c.longitudeMicros())
                .u32(c.lastMod())
                .build();
    }

    // ---------------------------------------------------------------------
    // Device / radio configuration
    // ---------------------------------------------------------------------

    /**
     * {@code CMD_SET_RADIO_PARAMS} (0x0B):
     * {@code 0B [freq u32 LE ×1000] [bw u32 LE ×1000] [sf] [cr]
     * [repeat?]}.
     *
     * @param p radio parameters; the optional repeat byte is appended
     *          only when present
     * @return the encoded frame
     */
    public static byte[] setRadioParams(RadioParams p) {
        FrameBuilder b = new FrameBuilder()
                .u8(MeshcoreCommand.SET_RADIO_PARAMS.code())
                .u32(Math.round(p.frequencyMhz() * MeshcoreConstants.RADIO_SCALE))
                .u32(Math.round(p.bandwidthKhz() * MeshcoreConstants.RADIO_SCALE))
                .u8(p.spreadingFactor())
                .u8(p.codingRate());
        if (p.repeat().isPresent()) {
            b.u8(p.repeat().getAsInt());
        }
        return b.build();
    }

    /**
     * {@code CMD_SET_RADIO_TX_POWER} (0x0C): {@code 0C [power int8 dBm]}.
     *
     * @param dbm TX power in dBm (signed byte semantics)
     * @return the encoded frame
     */
    public static byte[] setRadioTxPower(int dbm) {
        return new FrameBuilder()
                .u8(MeshcoreCommand.SET_RADIO_TX_POWER.code())
                .u8(dbm & 0xFF)
                .build();
    }

    /**
     * {@code CMD_SET_ADVERT_LATLON} (0x0E):
     * {@code 0E [lat i32 LE ×1e6] [lon i32 LE ×1e6]}.
     *
     * @param latitudeMicros  latitude in signed micro-degrees
     * @param longitudeMicros longitude in signed micro-degrees
     * @return the encoded frame
     */
    public static byte[] setAdvertLatLon(
            int latitudeMicros, int longitudeMicros) {
        return new FrameBuilder()
                .u8(MeshcoreCommand.SET_ADVERT_LATLON.code())
                .i32(latitudeMicros)
                .i32(longitudeMicros)
                .build();
    }

    /**
     * {@code CMD_SET_ADVERT_LATLON} (0x0E) with the optional altitude:
     * {@code 0E [lat i32 LE ×1e6] [lon i32 LE ×1e6] [alt i32 LE]}.
     *
     * @param latitudeMicros  latitude in signed micro-degrees
     * @param longitudeMicros longitude in signed micro-degrees
     * @param altitudeMicros  altitude (micro-scaled, firmware-defined)
     * @return the encoded frame
     */
    public static byte[] setAdvertLatLon(
            int latitudeMicros, int longitudeMicros, int altitudeMicros) {
        return new FrameBuilder()
                .u8(MeshcoreCommand.SET_ADVERT_LATLON.code())
                .i32(latitudeMicros)
                .i32(longitudeMicros)
                .i32(altitudeMicros)
                .build();
    }

    /**
     * {@code CMD_SET_OTHER_PARAMS} (0x26):
     * {@code 26 [manual_add] [telemetry_packed] [loc_policy?]
     * [multi_acks?]}.
     *
     * <p>{@code advertLocPolicy} and {@code multiAcks} are optional
     * trailing bytes; {@code multiAcks} can only be sent when
     * {@code advertLocPolicy} is also present (wire order).</p>
     *
     * @param manualAddContacts   manual-add policy byte
     * @param telemetryModePacked packed per-class telemetry mode byte
     * @param advertLocPolicy     optional advert location policy
     * @param multiAcks           optional multi-ACK setting (requires
     *                            {@code advertLocPolicy})
     * @return the encoded frame
     */
    public static byte[] setOtherParams(
            int manualAddContacts,
            int telemetryModePacked,
            Integer advertLocPolicy,
            Integer multiAcks) {
        FrameBuilder b = new FrameBuilder()
                .u8(MeshcoreCommand.SET_OTHER_PARAMS.code())
                .u8(manualAddContacts)
                .u8(telemetryModePacked);
        if (advertLocPolicy != null) {
            b.u8(advertLocPolicy);
            if (multiAcks != null) {
                b.u8(multiAcks);
            }
        }
        return b.build();
    }

    /**
     * {@code CMD_GET_CUSTOM_VARS} (0x28): request the device's custom
     * string-keyed settings ({@code gps}, {@code gps_interval}, etc.).
     * Reply is {@code RESP_CODE_CUSTOM_VARS} (0x15) decoded into a
     * {@link CustomVarsFrame}.
     *
     * @return the encoded frame
     */
    public static byte[] getCustomVars() {
        return new FrameBuilder()
                .u8(MeshcoreCommand.GET_CUSTOM_VARS.code())
                .build();
    }

    /**
     * {@code CMD_SET_CUSTOM_VAR} (0x29): write a single string-keyed
     * setting. Body: {@code [opcode][name]:[value]} (ASCII, no NUL —
     * frame length defines the end).
     *
     * <p>The firmware splits on the first {@code :}, so the name must
     * not contain one; values containing {@code ,} are fine since the
     * comma is not a separator on the request path.</p>
     *
     * @param name  variable name (must not contain {@code :})
     * @param value variable value
     * @return the encoded frame
     * @throws IllegalArgumentException if {@code name} contains {@code :}
     */
    public static byte[] setCustomVar(String name, String value) {
        if (name.contains(":")) {
            throw new IllegalArgumentException(
                    "custom var name must not contain \":\" (frame separator)");
        }
        return new FrameBuilder()
                .u8(MeshcoreCommand.SET_CUSTOM_VAR.code())
                .utf8String(name + ":" + value)
                .build();
    }

    /**
     * {@code CMD_SEND_TELEMETRY_REQ} (0x27) for <em>self</em> telemetry:
     * {@code 27 [0 0 0]}. The device replies immediately (no OTA) with
     * {@code PUSH_CODE_TELEMETRY_RESPONSE} (0x8B) carrying its own
     * CayenneLPP payload.
     *
     * @return the encoded frame
     */
    public static byte[] sendTelemetryReq() {
        return new FrameBuilder()
                .u8(MeshcoreCommand.SEND_TELEMETRY_REQ.code())
                .zeros(3)
                .build();
    }

    /**
     * {@code CMD_SEND_TELEMETRY_REQ} (0x27) for a <em>peer</em>:
     * {@code 27 [0 0 0] [pub_key 32B]}. The device queries the peer
     * over the air; the same 0x8B push arrives later (seconds) if the
     * peer responds. The caller is responsible for batching/back-off.
     *
     * <p>The 3 bytes between opcode and pubkey are reserved (zero in
     * {@code companion-v1.15.0}); sending zeros is safe today.</p>
     *
     * @param peerPubKey the peer's full 32-byte public key
     * @return the encoded frame
     * @throws IllegalArgumentException if the key is not 32 bytes
     */
    public static byte[] sendTelemetryReq(byte[] peerPubKey) {
        if (peerPubKey.length != MeshcoreConstants.PUB_KEY_SIZE) {
            throw new IllegalArgumentException("peerPubKey must be exactly "
                    + MeshcoreConstants.PUB_KEY_SIZE + " bytes");
        }
        return new FrameBuilder()
                .u8(MeshcoreCommand.SEND_TELEMETRY_REQ.code())
                .zeros(3)
                .fixed(peerPubKey, MeshcoreConstants.PUB_KEY_SIZE)
                .build();
    }

    /**
     * {@code CMD_SET_TUNING_PARAMS} (0x15):
     * {@code 15 [rx_delay_base u32 LE ×1000] [airtime_factor u32 LE
     * ×1000]}.
     *
     * @param rxDelayBaseSeconds receive-delay base in seconds
     * @param airtimeFactor      airtime factor
     * @return the encoded frame
     */
    public static byte[] setTuningParams(
            double rxDelayBaseSeconds, double airtimeFactor) {
        return new FrameBuilder()
                .u8(MeshcoreCommand.SET_TUNING_PARAMS.code())
                .u32(Math.round(rxDelayBaseSeconds * MeshcoreConstants.RADIO_SCALE))
                .u32(Math.round(airtimeFactor * MeshcoreConstants.RADIO_SCALE))
                .build();
    }

    /**
     * {@code CMD_DEVICE_QUERY} (0x16): {@code 16 [app_target_ver]}, asking
     * for {@link MeshcoreConstants#APP_TARGET_PROTOCOL_VERSION} (3) — the
     * version whose receive frames carry per-message SNR.
     *
     * @return the encoded frame
     */
    public static byte[] deviceQuery() {
        return deviceQuery(MeshcoreConstants.APP_TARGET_PROTOCOL_VERSION);
    }

    /**
     * {@code CMD_DEVICE_QUERY} (0x16) with an explicit protocol version.
     *
     * <p>The firmware stores the byte verbatim and only branches on it for
     * the V3 receive frames, so an older version is expressible for a
     * client that deliberately wants the legacy shapes.</p>
     *
     * @param appTargetVer protocol version the app targets
     * @return the encoded frame
     */
    public static byte[] deviceQuery(int appTargetVer) {
        return new FrameBuilder()
                .u8(MeshcoreCommand.DEVICE_QUERY.code())
                .u8(appTargetVer)
                .build();
    }

    /**
     * {@code CMD_GET_BATT_AND_STORAGE} (0x14): {@code 14}.
     *
     * @return the encoded frame
     */
    public static byte[] getBatteryStorage() {
        return new FrameBuilder()
                .u8(MeshcoreCommand.GET_BATTERY_STORAGE.code())
                .build();
    }

    /**
     * {@code CMD_GET_CHANNEL} (0x1F): {@code 1F [channel_idx]}.
     *
     * @param channelIdx channel slot index
     * @return the encoded frame
     */
    public static byte[] getChannel(int channelIdx) {
        return new FrameBuilder()
                .u8(MeshcoreCommand.GET_CHANNEL.code())
                .u8(channelIdx)
                .build();
    }

    /**
     * {@code CMD_SET_CHANNEL} (0x20):
     * {@code 20 [channel_idx] [name 32B NUL-padded] [secret 16B]}
     * (50 bytes).
     *
     * @param channelIdx channel slot index
     * @param name       channel name (zero-padded/truncated to 32 bytes)
     * @param psk        the 16-byte AES-128 channel key as carried by
     *                   the companion link (truncated/zero-padded to
     *                   {@link MeshcoreConstants#CHANNEL_PSK_SIZE})
     * @return the encoded frame
     */
    public static byte[] setChannel(int channelIdx, String name, byte[] psk) {
        return new FrameBuilder()
                .u8(MeshcoreCommand.SET_CHANNEL.code())
                .u8(channelIdx)
                .fixed(name.getBytes(StandardCharsets.UTF_8),
                        MeshcoreConstants.CHANNEL_NAME_SIZE)
                .fixed(psk, MeshcoreConstants.CHANNEL_PSK_SIZE)
                .build();
    }

    // ---------------------------------------------------------------------
    // Decoder (Device → App) — total, never throws.
    // ---------------------------------------------------------------------

    /**
     * Decodes one device&#8594;app frame.
     *
     * <p>Total: returns a {@link DecodeFailure} for malformed/truncated
     * input and an {@link UnsupportedFrame} for unmodelled opcodes —
     * never throws. Switch exhaustively over
     * {@link MeshcoreInbound}.</p>
     *
     * @param frame raw frame bytes (one BLE notification)
     * @return the decoded inbound value
     */
    public static MeshcoreInbound decode(byte[] frame) {
        if (frame.length == 0) {
            return new DecodeFailure(MeshcoreDecodeError.of(
                    DecodeErrorKind.EMPTY, "empty frame"));
        }
        int op = frame[0] & 0xFF;
        ByteCursor c = new ByteCursor(frame);
        MeshcoreInbound out;
        try {
            c.u8("opcode"); // consume opcode
            out = decodeBody(c, op, frame);
        } catch (FrameTruncatedException e) {
            return new DecodeFailure(MeshcoreDecodeError.of(
                    DecodeErrorKind.TRUNCATED, e.getMessage(), op));
        }
        // Every layout below describes one whole frame, so a parsed frame
        // must end exactly at the frame's end. A leftover is either a
        // second frame in the same buffer (a transport-boundary error) or
        // a length the recorded layout does not explain; both are
        // reported, never dropped.
        if (out instanceof UnsupportedFrame || out instanceof DecodeFailure) {
            return out;
        }
        if (c.remaining() != 0) {
            return new DecodeFailure(MeshcoreDecodeError.of(
                    DecodeErrorKind.TRAILING_BYTES,
                    c.remaining() + " byte(s) left after a complete "
                            + out.getClass().getSimpleName(),
                    op));
        }
        return out;
    }

    /**
     * Decodes one frame body. The opcode byte has already been consumed.
     *
     * @param c     cursor positioned after the opcode
     * @param op    the opcode value
     * @param frame the whole frame, preserved for {@link UnsupportedFrame}
     * @return the decoded inbound value
     */
    private static MeshcoreInbound decodeBody(
            ByteCursor c, int op, byte[] frame) {
        switch (op) {
            case 0x00: { // RESP_CODE_OK
                OptionalLong v = c.remaining() >= 4
                        ? OptionalLong.of(c.u32("ok.value"))
                        : OptionalLong.empty();
                return new OkFrame(v);
            }
            case 0x01: { // RESP_CODE_ERR
                OptionalInt code = c.remaining() >= 1
                        ? OptionalInt.of(c.u8("err.code"))
                        : OptionalInt.empty();
                return new ErrorFrame(code);
            }
            case 0x02: // RESP_CODE_CONTACTS_START
                return new ContactsStartFrame(c.u32("contactsStart.count"));

            case 0x03: // RESP_CODE_CONTACT
                return new ContactFrame(decodeContact(c));

            case 0x04: // RESP_CODE_END_OF_CONTACTS
                return new EndOfContactsFrame(c.u32("endOfContacts.lastMod"));

            case 0x05: // RESP_CODE_SELF_INFO
                return new SelfInfoFrame(decodeSelfInfo(c));

            case 0x06: // RESP_CODE_SENT
                return new MsgSentFrame(new MsgSent(
                        c.u8("msgSent.floodFlag") != 0,
                        c.u32("msgSent.expectedAck"),
                        c.u32("msgSent.estTimeoutMs")));

            case 0x07: // RESP_CODE_CONTACT_MSG_RECV (legacy)
                return new ContactMessageFrame(decodeContactMsg(c, false));

            case 0x08: // RESP_CODE_CHANNEL_MSG_RECV (legacy)
                return new ChannelMessageFrame(decodeChannelMsg(c, false));

            case 0x09: // RESP_CODE_CURR_TIME
                return new CurrentTimeFrame(c.u32("currentTime.unix"));

            case 0x0A: // RESP_CODE_NO_MORE_MESSAGES
                return new NoMoreMessagesFrame();

            case 0x0C: // RESP_CODE_BATT_AND_STORAGE
                return new BatteryStorageFrame(new BatteryStorage(
                        c.u16("battery.mv"),
                        c.u32("battery.usedKb"),
                        c.u32("battery.totalKb")));

            case 0x0D: // RESP_CODE_DEVICE_INFO
                return new DeviceInfoFrame(new DeviceInfo(
                        c.u8("deviceInfo.fwVer"),
                        c.u8("deviceInfo.maxContactsHalf") * 2,
                        c.u8("deviceInfo.maxGroupChannels"),
                        c.u32("deviceInfo.blePin"),
                        c.fixedCString(
                                MeshcoreConstants.DEVICE_BUILD_DATE_SIZE,
                                "deviceInfo.build"),
                        c.fixedCString(
                                MeshcoreConstants.DEVICE_MANUFACTURER_SIZE,
                                "deviceInfo.manufacturer"),
                        c.fixedCString(
                                MeshcoreConstants.DEVICE_FIRMWARE_VERSION_SIZE,
                                "deviceInfo.fwVersion"),
                        c.u8("deviceInfo.clientRepeat"),
                        c.u8("deviceInfo.pathHashMode")));

            case 0x10: // RESP_CODE_CONTACT_MSG_RECV_V3
                return new ContactMessageFrame(decodeContactMsg(c, true));

            case 0x11: // RESP_CODE_CHANNEL_MSG_RECV_V3
                return new ChannelMessageFrame(decodeChannelMsg(c, true));

            case 0x12: { // RESP_CODE_CHANNEL_INFO
                // The reply carries 16 bytes of secret for an ordinary
                // request and 32 when the request asked for the full
                // secret with a third byte of 32 (MyMesh.cpp:1715-1721
                // writes 16). Only the frame length says which, so read
                // whatever follows the name and reject a width the
                // firmware does not send.
                int infoIdx = c.u8("channelInfo.idx");
                String infoName = c.fixedCString(
                        MeshcoreConstants.CHANNEL_NAME_SIZE,
                        "channelInfo.name");
                byte[] infoPsk = c.atEnd()
                        ? new byte[0]
                        : c.bytes(c.remaining(), "channelInfo.psk");
                if (infoPsk.length != MeshcoreConstants.CHANNEL_PSK_SIZE
                        && infoPsk.length
                                != MeshcoreConstants.CHANNEL_PSK_SIZE_FULL) {
                    return new DecodeFailure(MeshcoreDecodeError.of(
                            DecodeErrorKind.TRUNCATED,
                            "CHANNEL_INFO secret is " + infoPsk.length
                                    + " bytes; the radio sends "
                                    + MeshcoreConstants.CHANNEL_PSK_SIZE
                                    + " or "
                                    + MeshcoreConstants.CHANNEL_PSK_SIZE_FULL,
                            op));
                }
                return new ChannelInfoFrame(
                        new ChannelInfo(infoIdx, infoName, infoPsk));
            }

            case 0x15: // RESP_CODE_CUSTOM_VARS
                return new CustomVarsFrame(decodeCustomVars(c));

            case 0x80: { // PUSH_CODE_ADVERTISEMENT
                byte[] payload = c.atEnd()
                        ? new byte[0]
                        : c.bytes(c.remaining(), "advert.payload");
                // Firmware in the field pushes only the 32-byte public key
                // here, not a signed advert record
                // (MyMesh.cpp:357-360 writes 1 + PUB_KEY_SIZE). Parsing
                // that as a record fails on the timestamp and drops the
                // push, so every over-the-air advert is lost. A payload
                // that carries the key decodes to a BARE advert instead:
                // which node was heard, and nothing it cannot honestly
                // claim. One too short to name a node identifies nothing
                // and is a controlled failure.
                if (payload.length >= Advert.MIN_FULL_SIZE) {
                    return new AdvertFrame(Advert.parse(payload));
                }
                if (payload.length < MeshcoreConstants.PUB_KEY_SIZE) {
                    return new DecodeFailure(MeshcoreDecodeError.of(
                            DecodeErrorKind.TRUNCATED,
                            "advert push is " + payload.length
                                    + " bytes; a node is named by its "
                                    + MeshcoreConstants.PUB_KEY_SIZE
                                    + "-byte public key",
                            op));
                }
                return new AdvertFrame(Advert.bare(
                        java.util.Arrays.copyOf(
                                payload, MeshcoreConstants.PUB_KEY_SIZE)));
            }
            case 0x82: { // PUSH_CODE_SEND_CONFIRMED
                // Delivery ACK for a direct message: a 4-byte CRC tag
                // matching the MsgSent.expectedAck recorded on send,
                // then the round-trip time the firmware measures
                // (MyMesh.cpp:418-422 writes all 9 bytes). Guard for a
                // short payload that carries only the tag.
                long ack = c.remaining() >= 4 ? c.u32("ack.crc") : 0;
                OptionalLong rtt = c.remaining() >= 4
                        ? OptionalLong.of(c.u32("ack.rtt"))
                        : OptionalLong.empty();
                return new AckFrame(ack, rtt);
            }
            case 0x83: { // PUSH_CODE_MSGS_WAITING
                OptionalInt n = c.remaining() >= 1
                        ? OptionalInt.of(c.u8("msgsWaiting.count"))
                        : OptionalInt.empty();
                return new MessagesWaitingFrame(n);
            }
            case 0x88: { // PUSH_CODE_LOG_RX_DATA
                double snr = c.i8("rfLog.snr") / 4.0;
                int rssi = c.i8("rfLog.rssi");
                byte[] raw = c.atEnd()
                        ? new byte[0]
                        : c.bytes(c.remaining(), "rfLog.raw");
                return new RfLogFrame(new RfLog(snr, rssi, raw));
            }
            case 0x8B: { // PUSH_CODE_TELEMETRY_RESPONSE
                c.u8("telemetry.reserved");
                byte[] pub6 = c.bytes(
                        MeshcoreConstants.PUB_KEY_PREFIX_SIZE,
                        "telemetry.pubKey6");
                byte[] lpp = c.atEnd()
                        ? new byte[0]
                        : c.bytes(c.remaining(), "telemetry.lpp");
                return new TelemetryResponseFrame(pub6, lpp);
            }
            case 0x1B: { // RESP_CODE_CHANNEL_DATA_RECV
                double cdSnr = MeshcoreConstants.snrByteToDb(c.u8("chdata.snr"));
                // The firmware leaves this byte reserved on a
                // single-profile radio and reports the receiving
                // profile in it while a second profile is on: 0xA0
                // primary, 0xA1 radio2 (onChannelDataRecv,
                // MyMesh.cpp:2423).
                RxVia cdVia = RxVia.fromWireByte(c.u8("chdata.via"));
                c.u8("chdata.reserved2");
                int cdIdx = c.u8("chdata.channel");
                int cdPath = c.u8("chdata.pathLen");
                int cdType = c.u16("chdata.dataType");
                int cdLen = c.u8("chdata.len");
                byte[] cdData = c.bytes(cdLen, "chdata.data");
                return new ChannelDataFrame(new ChannelData(
                        cdSnr, cdIdx, cdPath, cdType, cdData, cdVia));
            }

            case 0x1D: // RESP_CODE_CLI_REPLY
                return new CliReplyFrame(
                        c.atEnd() ? "" : c.utf8ToEnd("cliReply.text"));

            case 0x0B: { // RESP_CODE_EXPORT_CONTACT
                byte[] exported = c.atEnd()
                        ? new byte[0]
                        : c.bytes(c.remaining(), "export.packet");
                return new ExportedContactFrame(exported);
            }
            case 0x0E: // RESP_CODE_PRIVATE_KEY
                return new PrivateKeyFrame(c.bytes(
                        MeshcoreConstants.PRIV_KEY_SIZE, "privateKey.key"));

            case 0x0F: // RESP_CODE_DISABLED
                return new DisabledFrame();

            case 0x13: // RESP_CODE_SIGN_START
                c.u8("signStart.reserved");
                return new SignStartFrame(c.u32("signStart.maxLen"));

            case 0x14: // RESP_CODE_SIGNATURE
                return new SignatureFrame(c.bytes(
                        MeshcoreConstants.SIGNATURE_SIZE, "signature"));

            case 0x16: { // RESP_CODE_ADVERT_PATH
                long receivedAt = c.u32("advertPath.ts");
                PathLen apl = new PathLen(c.u8("advertPath.pathLen"));
                return new AdvertPathFrame(new AdvertPath(
                        receivedAt, apl, readPath(c, apl, "advertPath.path")));
            }
            case 0x17: // RESP_CODE_TUNING_PARAMS
                return new TuningParamsFrame(new TuningParams(
                        c.u32("tuning.rx")
                                / (double) MeshcoreConstants.RADIO_SCALE,
                        c.u32("tuning.af")
                                / (double) MeshcoreConstants.RADIO_SCALE));

            case 0x18: // RESP_CODE_STATS
                return decodeStats(c, op, frame);

            case 0x19: // RESP_CODE_AUTOADD_CONFIG
                return new AutoAddConfigFrame(new AutoAddConfig(
                        c.u8("autoAdd.flags"), c.u8("autoAdd.maxHops")));

            case 0x81: // PUSH_CODE_PATH_UPDATED
                return new PathUpdatedFrame(c.bytes(
                        MeshcoreConstants.PUB_KEY_SIZE, "pathUpdated.pubKey"));

            case 0x84: { // PUSH_CODE_RAW_DATA
                double rawSnr = c.i8("raw.snr") / 4.0;
                int rawRssi = c.i8("raw.rssi");
                // 0xFF on a single-profile radio; 0xA0/0xA1 when a second
                // profile is on (onRawDataRecv, MyMesh.cpp:2830-2840).
                RxVia rawVia = RxVia.fromWireByte(c.u8("raw.via"));
                byte[] rawPayload = c.atEnd()
                        ? new byte[0]
                        : c.bytes(c.remaining(), "raw.payload");
                return new RawDataFrame(rawSnr, rawRssi, rawPayload, rawVia);
            }
            case 0x85: { // PUSH_CODE_LOGIN_SUCCESS
                int perm = c.u8("login.permissions");
                byte[] lp = c.bytes(
                        MeshcoreConstants.PUB_KEY_PREFIX_SIZE, "login.pubKey6");
                Long ts = null;
                Integer acl = null;
                Integer lvl = null;
                // The new-format frame appends 4+1+1 bytes; the legacy one
                // stops. The same writer added these to the legacy form
                // (MyMesh.cpp:684-702), so a tail shorter than a whole
                // extension is a future field, not a second frame.
                if (c.remaining() >= 6) {
                    ts = c.u32("login.serverTs");
                    acl = c.u8("login.acl");
                    lvl = c.u8("login.fwLevel");
                }
                c.skipRemaining("login reply has grown in place before");
                return new LoginResultFrame(new LoginResult(
                        true, perm, lp, ts, acl, lvl));
            }
            case 0x86: // PUSH_CODE_LOGIN_FAIL
                c.u8("login.reserved");
                return new LoginResultFrame(new LoginResult(
                        false, 0,
                        c.bytes(MeshcoreConstants.PUB_KEY_PREFIX_SIZE,
                                "login.pubKey6"),
                        null, null, null));

            case 0x87: { // PUSH_CODE_STATUS_RESPONSE
                c.u8("status.reserved");
                byte[] sp = c.bytes(
                        MeshcoreConstants.PUB_KEY_PREFIX_SIZE, "status.pubKey6");
                RepeaterStatus status = decodeRepeaterStatus(c);
                // The firmware forwards the answering node's on-air status
                // payload verbatim (MyMesh.cpp:718-724), so anything after
                // the fields modelled here is that node's own tail.
                c.skipRemaining("repeater status payload is forwarded verbatim");
                return new StatusResponseFrame(sp, status);
            }
            case 0x89: // PUSH_CODE_TRACE_DATA
                return new TraceDataFrame(decodeTrace(c));

            case 0x8A: // PUSH_CODE_NEW_ADVERT
                return new NewAdvertFrame(decodeContact(c));

            case 0x8D: { // PUSH_CODE_PATH_DISCOVERY_RESPONSE
                c.u8("discovery.reserved");
                byte[] dp = c.bytes(
                        MeshcoreConstants.PUB_KEY_PREFIX_SIZE,
                        "discovery.pubKey6");
                PathLen outL = new PathLen(c.u8("discovery.outPathLen"));
                byte[] outP = readPath(c, outL, "discovery.outPath");
                PathLen inL = new PathLen(c.u8("discovery.inPathLen"));
                byte[] inP = readPath(c, inL, "discovery.inPath");
                return new PathDiscoveryFrame(new PathDiscoveryResult(
                        dp, outL, outP, inL, inP));
            }
            case 0x8E: { // PUSH_CODE_CONTROL_DATA
                double ctlSnr = c.i8("control.snr") / 4.0;
                int ctlRssi = c.i8("control.rssi");
                int ctlPath = c.u8("control.pathLen");
                // The firmware copies the payload straight after path_len —
                // no path bytes, whatever path_len says.
                byte[] ctlPayload = c.atEnd()
                        ? new byte[0]
                        : c.bytes(c.remaining(), "control.payload");
                return new ControlDataFrame(ctlSnr, ctlRssi, ctlPath,
                        ctlPayload,
                        decodeDiscover(ctlPayload, ctlSnr, ctlRssi));
            }
            case 0x8F: // PUSH_CODE_CONTACT_DELETED
                return new ContactDeletedFrame(c.bytes(
                        MeshcoreConstants.PUB_KEY_SIZE, "deleted.pubKey"));

            case 0x90: // PUSH_CODE_CONTACTS_FULL
                return new ContactsFullFrame();

            case 0x91: // PUSH_CODE_ONE_KEY_DM_REJECTED
                return new OneKeyRejectedFrame(c.bytes(
                        MeshcoreConstants.PUB_KEY_SIZE,
                        "oneKeyRejected.pubKey"));

            default:
                return new UnsupportedFrame(op, frame.clone());
        }
    }

    /**
     * {@code RESP_CODE_CUSTOM_VARS} payload: comma-separated
     * {@code name:value} pairs (ASCII, no NUL — frame length is the
     * terminator). Empty payload &#8594; empty map. Malformed entries
     * (no {@code :} separator) are silently dropped to match the
     * firmware's permissive parser.
     */
    private static Map<String, String> decodeCustomVars(ByteCursor c) {
        if (c.atEnd()) {
            return Collections.emptyMap();
        }
        String payload = c.utf8ToEnd("customVars.payload");
        Map<String, String> out = new LinkedHashMap<>();
        for (String entry : payload.split(",", -1)) {
            int sep = entry.indexOf(':');
            if (sep <= 0) {
                continue;
            }
            out.put(entry.substring(0, sep), entry.substring(sep + 1));
        }
        return Collections.unmodifiableMap(out);
    }

    private static SelfInfo decodeSelfInfo(ByteCursor c) {
        int advType = c.u8("selfInfo.advType");
        int txPower = c.u8("selfInfo.txPower");
        int maxTxPower = c.u8("selfInfo.maxTxPower");
        byte[] pubKey = c.bytes(MeshcoreConstants.PUB_KEY_SIZE,
                "selfInfo.pubKey");
        double lat = c.i32("selfInfo.lat") / 1e6;
        double lon = c.i32("selfInfo.lon") / 1e6;
        int multiAcks = c.u8("selfInfo.multiAcks");
        int locPolicy = c.u8("selfInfo.advertLocPolicy");
        int telemetry = c.u8("selfInfo.telemetryMode");
        boolean manualAdd = c.u8("selfInfo.manualAddContacts") != 0;
        double freq = c.u32("selfInfo.frequency") / 1000.0;
        double bw = c.u32("selfInfo.bandwidth") / 1000.0;
        int sf = c.u8("selfInfo.sf");
        int cr = c.u8("selfInfo.cr");
        String name = c.atEnd() ? "" : c.utf8ToEnd("selfInfo.name");
        return new SelfInfo(advType, txPower, maxTxPower, pubKey, lat, lon,
                multiAcks, locPolicy, telemetry, manualAdd, freq, bw, sf, cr,
                name);
    }

    /**
     * Decodes 0x08 (legacy) and 0x11 (V3) channel messages. The opcode
     * byte has already been consumed.
     */
    private static ChannelMessage decodeChannelMsg(ByteCursor c, boolean v3) {
        Double snr = null;
        if (v3) {
            snr = c.i8("channelMsg.snr") / 4.0;
            c.u8("channelMsg.reserved1");
            c.u8("channelMsg.reserved2");
        }
        int channelIdx = c.u8("channelMsg.channelIdx");
        int pathLen = c.u8("channelMsg.pathLen");
        int txtType = c.u8("channelMsg.txtType");
        long ts = c.u32("channelMsg.timestamp");
        String text = c.atEnd() ? "" : c.utf8ToEnd("channelMsg.text");
        return new ChannelMessage(channelIdx, pathLen, txtType, ts, text, v3,
                snr);
    }

    /**
     * Decodes 0x07 (legacy) and 0x10 (V3) contact messages. The opcode
     * byte has already been consumed.
     */
    private static ContactMessage decodeContactMsg(ByteCursor c, boolean v3) {
        Double snr = null;
        if (v3) {
            snr = c.i8("contactMsg.snr") / 4.0;
            c.u8("contactMsg.reserved1");
            c.u8("contactMsg.reserved2");
        }
        byte[] prefix = c.bytes(MeshcoreConstants.PUB_KEY_PREFIX_SIZE,
                "contactMsg.prefix");
        int pathLen = c.u8("contactMsg.pathLen");
        int txtType = c.u8("contactMsg.txtType");
        long ts = c.u32("contactMsg.timestamp");
        byte[] sig = null;
        if (txtType == MeshcoreConstants.TXT_TYPE_SIGNED_PLAIN) {
            sig = c.bytes(MeshcoreConstants.SIGNATURE_PREFIX_SIZE,
                    "contactMsg.sigPrefix");
        }
        String text = c.atEnd() ? "" : c.utf8ToEnd("contactMsg.text");
        return new ContactMessage(prefix, pathLen, txtType, ts, text, v3, snr,
                sig);
    }


    /**
     * Reads the path bytes a {@code path_len} byte announces.
     *
     * <p>An invalid length (over {@link MeshcoreConstants#MAX_PATH_SIZE}, or
     * the reserved hash width) yields an empty path because that is exactly
     * what the firmware writes ({@code Packet.cpp:24-27}); the caller can see
     * the refusal through {@link PathLen#isValid()}.</p>
     *
     * @param c   cursor positioned at the first path byte
     * @param len the length byte that announces them
     * @param ctx field context for truncation reporting
     * @return the path bytes, empty when the length is one the radio refuses
     */
    private static byte[] readPath(ByteCursor c, PathLen len, String ctx) {
        if (!len.isValid() || len.byteLength() == 0) {
            return new byte[0];
        }
        return c.bytes(len.byteLength(), ctx);
    }

    /**
     * Decodes {@code RESP_CODE_STATS} (0x18): the sub-type byte chooses which
     * of the three structs follows.
     *
     * <p>A sub-type this build does not model is handed back as
     * {@link UnsupportedFrame} rather than guessed at, and a tail the struct
     * grew after this layout is consumed: the packet counters gained a
     * receive-error counter inside the same frame, so a longer payload is a
     * field, not a second frame.</p>
     *
     * @param c     cursor positioned after the opcode
     * @param op    the opcode, for the unsupported report
     * @param frame the whole frame, preserved for {@link UnsupportedFrame}
     * @return the reading, or an unsupported frame for an unknown sub-type
     */
    private static MeshcoreInbound decodeStats(
            ByteCursor c, int op, byte[] frame) {
        int sub = c.u8("stats.subType");
        FrameStats stats;
        switch (sub) {
            case MeshcoreConstants.STATS_TYPE_CORE:
                stats = new FrameStats(
                        new CoreStats(
                                c.u16("stats.core.batt"),
                                c.u32("stats.core.uptime"),
                                c.u16("stats.core.errFlags"),
                                c.u8("stats.core.queue")),
                        null, null);
                break;
            case MeshcoreConstants.STATS_TYPE_RADIO:
                stats = new FrameStats(
                        null,
                        new RadioStats(
                                c.i16("stats.radio.noise"),
                                c.i8("stats.radio.rssi"),
                                c.i8("stats.radio.snr") / 4.0,
                                c.u32("stats.radio.txAir"),
                                c.u32("stats.radio.rxAir")),
                        null);
                break;
            case MeshcoreConstants.STATS_TYPE_PACKETS:
                stats = new FrameStats(
                        null, null,
                        new PacketStats(
                                c.u32("stats.pkts.recv"),
                                c.u32("stats.pkts.sent"),
                                c.u32("stats.pkts.sentFlood"),
                                c.u32("stats.pkts.sentDirect"),
                                c.u32("stats.pkts.recvFlood"),
                                c.u32("stats.pkts.recvDirect"),
                                c.remaining() >= 4
                                        ? c.u32("stats.pkts.recvErrors")
                                        : null));
                break;
            default:
                return new UnsupportedFrame(op, frame.clone());
        }
        c.skipRemaining("stats struct grows in place");
        return new StatsFrame(stats);
    }

    /**
     * Decodes the {@code RepeaterStats} struct.
     *
     * <p>The first 24 bytes are required; every later field was added by a
     * firmware release, so it is read only when the payload carries it and
     * stays {@code null} otherwise. An old repeater's short answer still
     * decodes.</p>
     *
     * @param c cursor positioned at the first status byte
     * @return the decoded status, or {@code null} when the payload is too
     *         short to be one
     */
    private static RepeaterStatus decodeRepeaterStatus(ByteCursor c) {
        if (c.remaining() < 24) {
            return null;
        }
        int batt = c.u16("rs.batt");
        int queue = c.u16("rs.queue");
        int noise = c.i16("rs.noise");
        int rssi = c.i16("rs.rssi");
        long recv = c.u32("rs.recv");
        long sent = c.u32("rs.sent");
        long air = c.u32("rs.air");
        long up = c.u32("rs.uptime");
        Long sentFlood = u32OrNull(c, "rs.sentFlood");
        Long sentDirect = u32OrNull(c, "rs.sentDirect");
        Long recvFlood = u32OrNull(c, "rs.recvFlood");
        Long recvDirect = u32OrNull(c, "rs.recvDirect");
        Integer errEvents = u16OrNull(c, "rs.errEvents");
        Double snr = c.remaining() >= 2 ? c.i16("rs.snr") / 4.0 : null;
        Integer directDups = u16OrNull(c, "rs.directDups");
        Integer floodDups = u16OrNull(c, "rs.floodDups");
        Long rxAir = u32OrNull(c, "rs.rxAir");
        Long recvErrors = u32OrNull(c, "rs.recvErrors");
        return new RepeaterStatus(batt, queue, noise, rssi, recv, sent, air,
                up, sentFlood, sentDirect, recvFlood, recvDirect, errEvents,
                snr, directDups, floodDups, rxAir, recvErrors);
    }

    /**
     * Reads an optional little-endian u32.
     *
     * @param c   cursor
     * @param ctx field context for truncation reporting
     * @return the value, or {@code null} when fewer than 4 bytes remain
     */
    private static Long u32OrNull(ByteCursor c, String ctx) {
        return c.remaining() >= 4 ? c.u32(ctx) : null;
    }

    /**
     * Reads an optional little-endian u16.
     *
     * @param c   cursor
     * @param ctx field context for truncation reporting
     * @return the value, or {@code null} when fewer than 2 bytes remain
     */
    private static Integer u16OrNull(ByteCursor c, String ctx) {
        return c.remaining() >= 2 ? c.u16(ctx) : null;
    }

    /**
     * Decodes {@code PUSH_CODE_TRACE_DATA} (0x89).
     *
     * <pre>
     * [reserved][path_len][flags][tag u32][auth u32][hashes]
     * [snr i8 x hops][final snr i8]
     * </pre>
     *
     * <p>The hop count is not carried: it is {@code path_len} shifted down by
     * the hash code in the low two flag bits, which is why the flags are
     * needed before the SNR block can be located.</p>
     *
     * @param c cursor positioned after the opcode
     * @return the trace
     */
    private static TraceResult decodeTrace(ByteCursor c) {
        c.u8("trace.reserved");
        int pathLen = c.u8("trace.pathLen");
        int flags = c.u8("trace.flags");
        long tag = c.u32("trace.tag");
        long auth = c.u32("trace.auth");
        byte[] hashes = c.bytes(pathLen, "trace.hashes");
        int hops = pathLen >> (flags & 0x03);
        double[] snrs = new double[hops];
        for (int i = 0; i < hops; i++) {
            snrs[i] = c.i8("trace.snr[" + i + "]") / 4.0;
        }
        double last = c.i8("trace.finalSnr") / 4.0;
        return new TraceResult(tag, auth, flags, hashes, snrs, last);
    }

    /**
     * Decodes a node-discover response out of a control payload.
     *
     * <pre>
     * [0x9X | node_type][their snr x4][tag u32][pub_key 32 or 8]
     * </pre>
     *
     * <p>Returns {@code null} for any other control packet, which the caller
     * keeps as raw bytes: not every control payload is a discover reply, and
     * guessing at one would invent a node that is not there.</p>
     *
     * @param payload  the control payload
     * @param ourSnr   the SNR our radio measured for the packet
     * @param ourRssi  the RSSI our radio measured for the packet
     * @return the discover response, or {@code null} when this payload is not
     *         one
     */
    private static DiscoverResponse decodeDiscover(
            byte[] payload, double ourSnr, int ourRssi) {
        if (payload.length < 6 + 8
                || (payload[0] & 0xF0)
                        != MeshcoreConstants.CTL_TYPE_NODE_DISCOVER_RESP) {
            return null;
        }
        ByteCursor p = new ByteCursor(payload);
        int type = p.u8("discover.type") & 0x0F;
        double theirs = p.i8("discover.snr") / 4.0;
        long tag = p.u32("discover.tag");
        int keyLen = p.remaining() >= MeshcoreConstants.PUB_KEY_SIZE
                ? MeshcoreConstants.PUB_KEY_SIZE
                : 8;
        return new DiscoverResponse(type, tag, p.bytes(keyLen, "discover.key"),
                theirs, ourSnr, ourRssi);
    }

    private static Contact decodeContact(ByteCursor c) {
        byte[] pubKey = c.bytes(MeshcoreConstants.PUB_KEY_SIZE,
                "contact.pubKey");
        int type = c.u8("contact.type");
        int flags = c.u8("contact.flags");
        int pathLen = c.u8("contact.outPathLen");
        byte[] path = c.bytes(MeshcoreConstants.MAX_PATH_SIZE,
                "contact.outPath");
        String name = c.fixedCString(MeshcoreConstants.CONTACT_NAME_SIZE,
                "contact.name");
        long advertTs = c.u32("contact.lastAdvertTimestamp");
        int latMicros = c.i32("contact.lat");
        int lonMicros = c.i32("contact.lon");
        long lastMod = c.u32("contact.lastMod");
        return new Contact(pubKey, type, flags, pathLen, path, name, advertTs,
                latMicros, lonMicros, lastMod);
    }
}
