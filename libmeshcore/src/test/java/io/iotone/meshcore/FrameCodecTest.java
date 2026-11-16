// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package io.iotone.meshcore;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertInstanceOf;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.iotone.meshcore.codec.CayenneLpp;
import io.iotone.meshcore.codec.DecodeErrorKind;
import io.iotone.meshcore.codec.FrameBuilder;
import io.iotone.meshcore.codec.MeshcoreFrameCodec;
import io.iotone.meshcore.frames.AckFrame;
import io.iotone.meshcore.frames.AdvertPathFrame;
import io.iotone.meshcore.frames.AutoAddConfigFrame;
import io.iotone.meshcore.frames.ContactDeletedFrame;
import io.iotone.meshcore.frames.ContactFrame;
import io.iotone.meshcore.frames.ContactsFullFrame;
import io.iotone.meshcore.frames.ControlDataFrame;
import io.iotone.meshcore.frames.DisabledFrame;
import io.iotone.meshcore.frames.ExportedContactFrame;
import io.iotone.meshcore.frames.LoginResultFrame;
import io.iotone.meshcore.frames.NewAdvertFrame;
import io.iotone.meshcore.frames.OneKeyRejectedFrame;
import io.iotone.meshcore.frames.PathDiscoveryFrame;
import io.iotone.meshcore.frames.PathUpdatedFrame;
import io.iotone.meshcore.frames.PrivateKeyFrame;
import io.iotone.meshcore.frames.RawDataFrame;
import io.iotone.meshcore.frames.SignStartFrame;
import io.iotone.meshcore.frames.SignatureFrame;
import io.iotone.meshcore.frames.StatsFrame;
import io.iotone.meshcore.frames.StatusResponseFrame;
import io.iotone.meshcore.frames.TraceDataFrame;
import io.iotone.meshcore.frames.TuningParamsFrame;
import io.iotone.meshcore.frames.CustomVarsFrame;
import io.iotone.meshcore.frames.DecodeFailure;
import io.iotone.meshcore.frames.MeshcoreInbound;
import io.iotone.meshcore.frames.MessagesWaitingFrame;
import io.iotone.meshcore.frames.MsgSentFrame;
import io.iotone.meshcore.frames.SelfInfoFrame;
import io.iotone.meshcore.frames.TelemetryResponseFrame;
import io.iotone.meshcore.model.Contact;
import io.iotone.meshcore.model.DiscoverResponse;
import io.iotone.meshcore.model.LoginResult;
import io.iotone.meshcore.model.RepeaterStatus;
import io.iotone.meshcore.model.RxVia;
import io.iotone.meshcore.model.SelfInfo;
import io.iotone.meshcore.model.TraceResult;

import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.Map;

import org.junit.jupiter.api.Test;

/**
 * Programmatic frame goldens (SELF_INFO / CONTACT / ACK / telemetry /
 * custom vars) + decode totality, mirroring the Dart reference tests.
 */
class FrameCodecTest {

    @Test
    void selfInfoAllFieldsScalingTrailingName() {
        byte[] pubkey = new byte[32];
        for (int i = 0; i < 32; i++) {
            pubkey[i] = (byte) i;
        }
        byte[] frame = new FrameBuilder()
                .u8(0x05) // opcode
                .u8(0x01) // advType
                .u8(14) // txPower
                .u8(22) // maxTxPower
                .raw(pubkey)
                .i32(1000000) // lat → 1.0
                .i32(-2000000) // lon → -2.0
                .u8(2) // multiAcks
                .u8(1) // advertLocPolicy
                .u8(0) // telemetry
                .u8(1) // manualAddContacts → true
                .u32(915000) // frequency → 915.0 MHz
                .u32(250000) // bandwidth → 250.0 kHz
                .u8(7) // sf
                .u8(5) // cr
                .utf8String("T1000-E")
                .build();
        // 1 + 3 + 32 + 4 + 4 + 4 + 4 + 2 = 58 header bytes, then name.
        assertEquals(58 + "T1000-E".length(), frame.length);

        SelfInfo s = assertInstanceOf(SelfInfoFrame.class,
                MeshcoreFrameCodec.decode(frame)).selfInfo();
        assertEquals(1, s.advType());
        assertEquals(14, s.txPowerDbm());
        assertEquals(22, s.maxTxPowerDbm());
        assertArrayEquals(pubkey, s.publicKey());
        assertEquals(1.0, s.latitude(), 1e-9);
        assertEquals(-2.0, s.longitude(), 1e-9);
        assertEquals(2, s.multiAcks());
        assertEquals(1, s.advertLocPolicy());
        assertEquals(0, s.telemetryModeRaw());
        assertTrue(s.manualAddContacts());
        assertEquals(915.0, s.frequencyMhz(), 1e-9);
        assertEquals(250.0, s.bandwidthKhz(), 1e-9);
        assertEquals(7, s.spreadingFactor());
        assertEquals(5, s.codingRate());
        assertEquals("T1000-E", s.name());
    }

    @Test
    void selfInfoWithEmptyTrailingNameDecodes() {
        byte[] frame = new FrameBuilder().u8(0x05).zeros(57).build();
        SelfInfo s = assertInstanceOf(SelfInfoFrame.class,
                MeshcoreFrameCodec.decode(frame)).selfInfo();
        assertEquals("", s.name());
    }

    @Test
    void contact148ByteFrameFieldsAndActivePath() {
        byte[] pubkey = new byte[32];
        for (int i = 0; i < 32; i++) {
            pubkey[i] = (byte) (i + 1);
        }
        byte[] path = new byte[64];
        path[0] = (byte) 0xAA;
        path[1] = (byte) 0xBB;
        path[2] = (byte) 0xCC;
        byte[] frame = new FrameBuilder()
                .u8(0x03)
                .raw(pubkey)
                .u8(2) // type
                .u8(0) // flags
                .u8(3) // outPathLen
                .raw(path)
                .fixed("Repeater-1".getBytes(StandardCharsets.UTF_8), 32)
                .u32(0x66000001L) // lastAdvertTs
                .i32(1000000) // lat → 1.0
                .i32(-2000000) // lon → -2.0
                .u32(255) // lastMod
                .build();
        assertEquals(148, frame.length, "CONTACT frame must be 148 bytes");

        Contact ct = assertInstanceOf(ContactFrame.class,
                MeshcoreFrameCodec.decode(frame)).contact();
        assertArrayEquals(pubkey, ct.publicKey());
        assertEquals(2, ct.type());
        assertEquals(0, ct.flags());
        assertEquals(3, ct.outPathLen());
        assertEquals(64, ct.outPath().length);
        assertArrayEquals(new byte[] {(byte) 0xAA, (byte) 0xBB, (byte) 0xCC},
                ct.activePath());
        assertEquals("Repeater-1", ct.name());
        assertEquals(0x66000001L, ct.lastAdvertTimestamp());
        assertEquals(1.0, ct.latitude(), 1e-9);
        assertEquals(-2.0, ct.longitude(), 1e-9);
        assertEquals(255, ct.lastMod());
    }

    @Test
    void contactRoundTripsThroughAddUpdateContact() {
        // decode(CONTACT) → addUpdateContact re-encodes the same 148
        // bytes with only the opcode differing (0x03 → 0x09).
        byte[] pubkey = new byte[32];
        Arrays.fill(pubkey, (byte) 0x42);
        byte[] frame = new FrameBuilder()
                .u8(0x03).raw(pubkey).u8(1).u8(5).u8(0).zeros(64)
                .fixed("R".getBytes(StandardCharsets.UTF_8), 32)
                .u32(7).i32(-1).i32(1).u32(9)
                .build();
        Contact ct = assertInstanceOf(ContactFrame.class,
                MeshcoreFrameCodec.decode(frame)).contact();
        byte[] reEncoded = MeshcoreFrameCodec.addUpdateContact(ct);
        assertEquals(0x09, reEncoded[0] & 0xFF);
        assertArrayEquals(Arrays.copyOfRange(frame, 1, frame.length),
                Arrays.copyOfRange(reEncoded, 1, reEncoded.length));
    }

    @Test
    void customVarsEncodeAndDecode() {
        assertEquals("28", TestUtil.toHex(MeshcoreFrameCodec.getCustomVars()));
        assertEquals("29" + TestUtil.toHex(
                        "gps:1".getBytes(StandardCharsets.UTF_8)),
                TestUtil.toHex(MeshcoreFrameCodec.setCustomVar("gps", "1")));

        byte[] frame = new FrameBuilder()
                .u8(0x15).utf8String("gps:1,gps_interval:30").build();
        Map<String, String> m = assertInstanceOf(CustomVarsFrame.class,
                MeshcoreFrameCodec.decode(frame)).values();
        assertEquals("1", m.get("gps"));
        assertEquals("30", m.get("gps_interval"));
        assertEquals(2, m.size());
    }

    @Test
    void customVarsEmptyAndMalformed() {
        assertTrue(assertInstanceOf(CustomVarsFrame.class,
                MeshcoreFrameCodec.decode(new byte[] {0x15}))
                .values().isEmpty());

        byte[] frame = new FrameBuilder()
                .u8(0x15)
                .utf8String("gps:1,no_colon_here,gps_interval:30")
                .build();
        Map<String, String> m = assertInstanceOf(CustomVarsFrame.class,
                MeshcoreFrameCodec.decode(frame)).values();
        assertEquals(Map.of("gps", "1", "gps_interval", "30"), m);
    }

    @Test
    void decodeIsTotalOnEmptyAndTruncated() {
        DecodeFailure empty = assertInstanceOf(DecodeFailure.class,
                MeshcoreFrameCodec.decode(new byte[0]));
        assertEquals(DecodeErrorKind.EMPTY, empty.error().kind());

        DecodeFailure trunc = assertInstanceOf(DecodeFailure.class,
                MeshcoreFrameCodec.decode(TestUtil.hex("020100")));
        assertEquals(DecodeErrorKind.TRUNCATED, trunc.error().kind());
        assertEquals(0x02, trunc.error().opcode().getAsInt());

        assertInstanceOf(DecodeFailure.class,
                MeshcoreFrameCodec.decode(TestUtil.hex("0501")));
    }

    @Test
    void ackDecodesAndCorrelatesWithMsgSent() {
        AckFrame ack = assertInstanceOf(AckFrame.class,
                MeshcoreFrameCodec.decode(TestUtil.hex("8278563412")));
        assertEquals(0x12345678L, ack.ackCrc());

        MsgSentFrame sent = assertInstanceOf(MsgSentFrame.class,
                MeshcoreFrameCodec.decode(
                        TestUtil.hex("060078563412e8030000")));
        assertEquals(sent.sent().expectedAck(), ack.ackCrc());

        // Short/empty payload decodes to ack 0 (no throw).
        assertEquals(0, assertInstanceOf(AckFrame.class,
                MeshcoreFrameCodec.decode(TestUtil.hex("82"))).ackCrc());
    }

    @Test
    void telemetryReqEncodersSelfAndPeer() {
        byte[] self = MeshcoreFrameCodec.sendTelemetryReq();
        assertArrayEquals(new byte[] {0x27, 0, 0, 0}, self);

        byte[] pub = new byte[32];
        for (int i = 0; i < 32; i++) {
            pub[i] = (byte) (i + 1);
        }
        byte[] peer = MeshcoreFrameCodec.sendTelemetryReq(pub);
        assertEquals(36, peer.length);
        assertArrayEquals(new byte[] {0x27, 0, 0, 0},
                Arrays.copyOfRange(peer, 0, 4));
        assertArrayEquals(pub, Arrays.copyOfRange(peer, 4, 36));
    }

    @Test
    void telemetryResponseDecodes() {
        byte[] frame = TestUtil.hex(
                "8B" + "00" + "AABBCCDDEEFF"
                + "018806765FF2960A0003E8"); // ch=1 GPS entry
        TelemetryResponseFrame t = assertInstanceOf(
                TelemetryResponseFrame.class,
                MeshcoreFrameCodec.decode(frame));
        assertEquals("aabbccddeeff", TestUtil.toHex(t.pubKeyPrefix()));
        assertEquals(11, t.lppPayload().length);
        assertEquals(10.0,
                CayenneLpp.decode(t.lppPayload()).get(0).gps()[2], 1e-2);

        // Empty LPP payload decodes safely.
        TelemetryResponseFrame empty = assertInstanceOf(
                TelemetryResponseFrame.class,
                MeshcoreFrameCodec.decode(TestUtil.hex("8B00AABBCCDDEEFF")));
        assertEquals(0, empty.lppPayload().length);

        // Truncated pubkey prefix → DecodeFailure.
        assertInstanceOf(DecodeFailure.class,
                MeshcoreFrameCodec.decode(TestUtil.hex("8B00AABB")));
    }

    @Test
    void messagesWaitingWithAndWithoutCount() {
        MessagesWaitingFrame bare = assertInstanceOf(
                MessagesWaitingFrame.class,
                MeshcoreFrameCodec.decode(TestUtil.hex("83")));
        assertTrue(bare.count().isEmpty());

        MessagesWaitingFrame counted = assertInstanceOf(
                MessagesWaitingFrame.class,
                MeshcoreFrameCodec.decode(TestUtil.hex("8303")));
        assertEquals(3, counted.count().getAsInt());
    }

    // --- Opcode coverage: every opcode the Dart reference decodes --------
    //
    // The port modelled 24 of the 45 inbound opcodes the Dart codec
    // dispatches; the rest arrived as UnsupportedFrame. Each case below is
    // that opcode's layout, with the byte vector the Dart suite uses where
    // one exists, so the two libraries stay provably identical.

    @Test
    void exportedContactCarriesTheRadiosOwnAdvertPacket() {
        ExportedContactFrame f = assertInstanceOf(
                ExportedContactFrame.class,
                MeshcoreFrameCodec.decode(TestUtil.hex("0B AABBCCDD")));
        assertEquals("aabbccdd", TestUtil.toHex(f.advertPacket()));

        // No packet at all is an empty export, not a failure.
        assertEquals(0, assertInstanceOf(ExportedContactFrame.class,
                MeshcoreFrameCodec.decode(TestUtil.hex("0B")))
                .advertPacket().length);
    }

    @Test
    void privateKeyIsRedactedInToString() {
        byte[] key = new byte[64];
        java.util.Arrays.fill(key, (byte) 0x5A);
        byte[] frame = new byte[65];
        frame[0] = (byte) 0x0E;
        System.arraycopy(key, 0, frame, 1, 64);
        PrivateKeyFrame f = assertInstanceOf(PrivateKeyFrame.class,
                MeshcoreFrameCodec.decode(frame));
        assertArrayEquals(key, f.privateKey());
        // A key that reaches a log is a key leaked.
        assertTrue(f.toString().contains("redacted"));
        assertFalse(f.toString().contains("5a"));
    }

    @Test
    void disabledIsItsOwnAnswerNotSilence() {
        assertInstanceOf(DisabledFrame.class,
                MeshcoreFrameCodec.decode(TestUtil.hex("0F")));
    }

    @Test
    void signStartNamesItsBuffer() {
        SignStartFrame f = assertInstanceOf(SignStartFrame.class,
                MeshcoreFrameCodec.decode(TestUtil.hex("13 00 E8030000")));
        assertEquals(1000, f.maxLength());
    }

    @Test
    void signatureIsSixtyFourBytes() {
        byte[] sig = new byte[64];
        byte[] frame = new byte[65];
        frame[0] = (byte) 0x14;
        System.arraycopy(sig, 0, frame, 1, 64);
        assertEquals(64, assertInstanceOf(SignatureFrame.class,
                MeshcoreFrameCodec.decode(frame)).signature().length);
        assertInstanceOf(DecodeFailure.class,
                MeshcoreFrameCodec.decode(TestUtil.hex("14 0102")));
    }

    @Test
    void advertPathCarriesTheRouteAndItsHashWidth() {
        AdvertPathFrame f = assertInstanceOf(AdvertPathFrame.class,
                MeshcoreFrameCodec.decode(TestUtil.hex("16 E8030000 02 AABB")));
        assertEquals(1000, f.advertPath().receivedAt());
        assertEquals(2, f.advertPath().pathLen().hopCount());
        assertEquals(1, f.advertPath().pathLen().hashSize());
        assertEquals("aabb", TestUtil.toHex(f.advertPath().path()));

        // Hash size lives in the top two bits: 0x42 = 2 hops x 2 bytes.
        assertEquals(4, assertInstanceOf(AdvertPathFrame.class,
                MeshcoreFrameCodec.decode(TestUtil.hex("16 00000000 42 AABBCCDD")))
                .advertPath().path().length);

        // An over-long path_len yields an empty path, as the firmware writes.
        assertEquals(0, assertInstanceOf(AdvertPathFrame.class,
                MeshcoreFrameCodec.decode(TestUtil.hex("16 00000000 FF")))
                .advertPath().path().length);

        assertInstanceOf(DecodeFailure.class,
                MeshcoreFrameCodec.decode(TestUtil.hex("16 00000000 03 AABB")));
    }

    @Test
    void tuningParamsScaleByAThousand() {
        TuningParamsFrame f = assertInstanceOf(TuningParamsFrame.class,
                MeshcoreFrameCodec.decode(TestUtil.hex("17 E8030000 F4010000")));
        assertEquals(1.0, f.params().rxDelayBaseSeconds(), 1e-9);
        assertEquals(0.5, f.params().airtimeFactor(), 1e-9);
        assertInstanceOf(DecodeFailure.class,
                MeshcoreFrameCodec.decode(TestUtil.hex("17 E8030000")));
    }

    @Test
    void autoAddConfigKeepsItsFlagsAndHopLimit() {
        AutoAddConfigFrame f = assertInstanceOf(AutoAddConfigFrame.class,
                MeshcoreFrameCodec.decode(TestUtil.hex("19 0F 03")));
        assertEquals(0x0F, f.config().flags());
        assertEquals(3, f.config().maxHops());
        assertTrue(f.config().overwriteOldest());
        assertTrue(f.config().chat());
        assertTrue(f.config().repeater());
        assertTrue(f.config().roomServer());
        assertFalse(f.config().sensor());
    }

    @Test
    void statsCoreRadioAndPackets() {
        StatsFrame core = assertInstanceOf(StatsFrame.class,
                MeshcoreFrameCodec.decode(
                        TestUtil.hex("18 00 6810 10270000 0300 02")));
        assertEquals(4200, core.stats().core().batteryMilliVolts());
        assertEquals(10000, core.stats().core().uptimeSecs());
        assertEquals(3, core.stats().core().errFlags());
        assertEquals(2, core.stats().core().queueLen());

        StatsFrame radio = assertInstanceOf(StatsFrame.class,
                MeshcoreFrameCodec.decode(
                        TestUtil.hex("18 01 92FF A6 E2 3C000000 58020000")));
        assertEquals(-110, radio.stats().radio().noiseFloorDbm());
        assertEquals(-90, radio.stats().radio().lastRssi());
        assertEquals(-7.5, radio.stats().radio().lastSnrDb(), 1e-9);
        assertEquals(60, radio.stats().radio().txAirSecs());
        assertEquals(600, radio.stats().radio().rxAirSecs());

        String six = "0A000000 05000000 03000000 02000000 06000000 04000000";
        StatsFrame pkts = assertInstanceOf(StatsFrame.class,
                MeshcoreFrameCodec.decode(
                        TestUtil.hex("18 02 " + six + " 07000000")));
        assertEquals(10, pkts.stats().packets().received());
        assertEquals(2, pkts.stats().packets().sentDirect());
        assertEquals(7L, pkts.stats().packets().receiveErrors());
        // Old firmware sends six counters: the reading still decodes.
        assertEquals(null, assertInstanceOf(StatsFrame.class,
                MeshcoreFrameCodec.decode(TestUtil.hex("18 02 " + six)))
                .stats().packets().receiveErrors());
        // A sub-type newer than this build is named, not guessed at.
        assertInstanceOf(io.iotone.meshcore.frames.UnsupportedFrame.class,
                MeshcoreFrameCodec.decode(TestUtil.hex("18 09 0000")));
        // A field appended to the struct does not cost the reading.
        assertEquals(2, assertInstanceOf(StatsFrame.class,
                MeshcoreFrameCodec.decode(
                        TestUtil.hex("18 00 6810 10270000 0300 02 0900")))
                .stats().core().queueLen());
    }

    @Test
    void statusResponseDecodesTheRepeaterStatsStruct() {
        String stats = "6810" + "0100" + "92FF" + "B5FF"
                + "64000000" + "32000000" + "0A000000" + "100E0000"
                + "01000000 02000000 03000000 04000000"
                + "0000" + "1C00" + "0000 0000" + "05000000" + "00000000";
        StatusResponseFrame f = assertInstanceOf(StatusResponseFrame.class,
                MeshcoreFrameCodec.decode(
                        TestUtil.hex("87 00 A1A2A3A4A5A6 " + stats)));
        assertEquals("a1a2a3a4a5a6", TestUtil.toHex(f.pubKeyPrefix()));
        RepeaterStatus st = f.status();
        assertEquals(4200, st.batteryMilliVolts());
        assertEquals(-110, st.noiseFloorDbm());
        assertEquals(-75, st.lastRssi());
        assertEquals(3600, st.uptimeSecs());
        assertEquals(4, st.receivedDirect());
        assertEquals(7.0, st.lastSnrDb(), 1e-9);
        assertEquals(5, st.rxAirTimeSecs());
        assertEquals(0, st.receiveErrors());

        // An old, short struct still decodes: its fields are nullable.
        StatusResponseFrame old = assertInstanceOf(StatusResponseFrame.class,
                MeshcoreFrameCodec.decode(TestUtil.hex(
                        "87 00 A1A2A3A4A5A6 6810 0000 92FF B5FF "
                        + "64000000 32000000 0A000000 100E0000")));
        assertEquals(3600, old.status().uptimeSecs());
        assertEquals(null, old.status().lastSnrDb());

        // Shorter than the required 24 bytes: the frame decodes, the struct
        // is absent rather than invented.
        StatusResponseFrame tiny = assertInstanceOf(StatusResponseFrame.class,
                MeshcoreFrameCodec.decode(TestUtil.hex("87 00 AABBCCDDEEFF 6810")));
        assertEquals(null, tiny.status());
    }

    @Test
    void traceDataCarriesPerHopSnrAndTheFinalHop() {
        TraceDataFrame f = assertInstanceOf(TraceDataFrame.class,
                MeshcoreFrameCodec.decode(TestUtil.hex(
                        "89 00 03 00 44332211 00000000 A17FA1 18 F6 11 16")));
        TraceResult t = f.trace();
        assertEquals(0x11223344L, t.tag());
        assertEquals(1, t.hashSize());
        assertEquals("a17fa1", TestUtil.toHex(t.pathHashes()));
        assertEquals(3, t.hopCount());
        assertEquals(6.0, t.hopSnrsDb()[0], 1e-9);
        assertEquals(-2.5, t.hopSnrsDb()[1], 1e-9);
        assertEquals(4.25, t.hopSnrsDb()[2], 1e-9);
        assertEquals(5.5, t.finalSnrDb(), 1e-9);

        // Two-byte hashes halve the hop count.
        TraceDataFrame wide = assertInstanceOf(TraceDataFrame.class,
                MeshcoreFrameCodec.decode(TestUtil.hex(
                        "89 00 04 01 01000000 00000000 A1B27F80 08 0C 10")));
        assertEquals(2, wide.trace().hashSize());
        assertEquals(2, wide.trace().hopCount());
        assertEquals(4.0, wide.trace().finalSnrDb(), 1e-9);

        assertInstanceOf(DecodeFailure.class,
                MeshcoreFrameCodec.decode(TestUtil.hex("89 00 03 00 4433")));
    }

    @Test
    void newAdvertIsTheSameRecordAStreamedContactCarries() {
        byte[] pubkey = new byte[32];
        for (int i = 0; i < 32; i++) {
            pubkey[i] = (byte) (i + 1);
        }
        byte[] frame = new FrameBuilder()
                .u8(0x8A)
                .raw(pubkey)
                .u8(1) // type: chat
                .u8(0)
                .u8(0) // outPathLen: direct
                .raw(new byte[64])
                .fixed("Auto".getBytes(StandardCharsets.UTF_8), 32)
                .u32(0x66000001L)
                .i32(1000000)
                .i32(-2000000)
                .u32(7)
                .build();
        NewAdvertFrame f = assertInstanceOf(NewAdvertFrame.class,
                MeshcoreFrameCodec.decode(frame));
        assertEquals("Auto", f.contact().name());
        assertEquals(1, f.contact().type());
        assertEquals(7, f.contact().lastMod());
    }

    @Test
    void pathUpdatedNamesOnlyTheKey() {
        byte[] key = new byte[32];
        byte[] frame = new byte[33];
        frame[0] = (byte) 0x81;
        System.arraycopy(key, 0, frame, 1, 32);
        assertEquals(32, assertInstanceOf(PathUpdatedFrame.class,
                MeshcoreFrameCodec.decode(frame)).publicKey().length);
        assertInstanceOf(DecodeFailure.class,
                MeshcoreFrameCodec.decode(TestUtil.hex("81 0102")));
    }

    @Test
    void rawDataCarriesSnrRssiAndTheProfileItArrivedOn() {
        RawDataFrame f = assertInstanceOf(RawDataFrame.class,
                MeshcoreFrameCodec.decode(
                        TestUtil.hex("84 F4 A6 A1 090807")));
        assertEquals(-3.0, f.snrDb(), 1e-9);
        assertEquals(-90, f.rssi());
        assertEquals(RxVia.SECONDARY, f.via());
        assertEquals("090807", TestUtil.toHex(f.payload()));

        // 0xFF is the frame's own "none" value.
        assertEquals(RxVia.UNKNOWN, assertInstanceOf(RawDataFrame.class,
                MeshcoreFrameCodec.decode(TestUtil.hex("84 04 B0 FF")))
                .via());
        assertInstanceOf(DecodeFailure.class,
                MeshcoreFrameCodec.decode(TestUtil.hex("84 01")));
    }

    @Test
    void loginSuccessKeepsTheNewFormatFields() {
        LoginResultFrame f = assertInstanceOf(LoginResultFrame.class,
                MeshcoreFrameCodec.decode(
                        TestUtil.hex("85 01 AABBCCDDEEFF D2040000 07 0D")));
        LoginResult r = f.result();
        assertTrue(r.success());
        assertEquals(1, r.permissions());
        assertEquals("aabbccddeeff", TestUtil.toHex(r.pubKeyPrefix()));
        assertEquals(1234, r.serverTimestamp());
        assertEquals(7, r.aclPermissions());
        assertEquals(13, r.firmwareLevel());
        assertFalse(r.isLegacy());

        // Legacy is eight bytes with no extras, and is told apart by absence.
        LoginResult legacy = assertInstanceOf(LoginResultFrame.class,
                MeshcoreFrameCodec.decode(TestUtil.hex("85 00 AABBCCDDEEFF")))
                .result();
        assertTrue(legacy.isLegacy());
        assertEquals(null, legacy.serverTimestamp());

        // A 1..5-byte tail is not a whole extension, so it is not guessed at.
        assertTrue(assertInstanceOf(LoginResultFrame.class,
                MeshcoreFrameCodec.decode(
                        TestUtil.hex("85 00 AABBCCDDEEFF 01 02 03")))
                .result().isLegacy());
    }

    @Test
    void loginFailureIsItsOwnFrame() {
        LoginResult r = assertInstanceOf(LoginResultFrame.class,
                MeshcoreFrameCodec.decode(TestUtil.hex("86 00 AABBCCDDEEFF")))
                .result();
        assertFalse(r.success());
        assertEquals(0, r.permissions());
        // Truncation is a typed failure, not an index exception.
        assertInstanceOf(DecodeFailure.class,
                MeshcoreFrameCodec.decode(TestUtil.hex("86 00 AABB")));
        assertInstanceOf(DecodeFailure.class,
                MeshcoreFrameCodec.decode(TestUtil.hex("85")));
    }

    @Test
    void pathDiscoveryCarriesBothDirections() {
        PathDiscoveryFrame f = assertInstanceOf(PathDiscoveryFrame.class,
                MeshcoreFrameCodec.decode(
                        TestUtil.hex("8D 00 AABBCCDDEEFF 02 1122 01 33")));
        assertEquals("aabbccddeeff", TestUtil.toHex(f.result().pubKeyPrefix()));
        assertEquals(2, f.result().outPathLen().hopCount());
        assertEquals("1122", TestUtil.toHex(f.result().outPath()));
        assertEquals(1, f.result().inPathLen().hopCount());
        assertEquals("33", TestUtil.toHex(f.result().inPath()));

        // A second path shorter than its length byte is a failure.
        assertInstanceOf(DecodeFailure.class,
                MeshcoreFrameCodec.decode(
                        TestUtil.hex("8D 00 AABBCCDDEEFF 01 11 02 33")));
    }

    @Test
    void controlDataKeepsThePayloadAndDecodesADiscoverResponse() {
        byte[] key = new byte[32];
        for (int i = 0; i < 32; i++) {
            key[i] = (byte) (i + 1);
        }
        byte[] frame = new FrameBuilder()
                .u8(0x8E)
                .u8(0x14) // snr: 20 / 4 = 5.0 dB
                .u8(0xA6) // rssi: -90
                .u8(0) // path_len
                .u8(0x92) // node type 2: repeater
                .u8(0xF8) // their snr: -8 / 4 = -2.0 dB
                .u32(0xDEADBEEFL)
                .raw(key)
                .build();
        ControlDataFrame f = assertInstanceOf(ControlDataFrame.class,
                MeshcoreFrameCodec.decode(frame));
        assertEquals(5.0, f.snrDb(), 1e-9);
        assertEquals(-90, f.rssi());
        assertEquals(0, f.pathLen());
        DiscoverResponse d = f.discover();
        assertEquals(2, d.nodeType());
        assertEquals(0xDEADBEEFL, d.tag());
        assertEquals(-2.0, d.theirSnrDb(), 1e-9);
        assertEquals(5.0, d.ourSnrDb(), 1e-9);
        assertArrayEquals(key, d.publicKey());

        // Another control packet keeps its bytes and claims no node.
        ControlDataFrame other = assertInstanceOf(ControlDataFrame.class,
                MeshcoreFrameCodec.decode(TestUtil.hex("8E 14 A6 00 80 04 01000000")));
        assertEquals(null, other.discover());
        assertEquals(6, other.payload().length);

        // Truncated (only two bytes of headers) is a typed failure.
        assertInstanceOf(DecodeFailure.class,
                MeshcoreFrameCodec.decode(TestUtil.hex("8E 14")));
    }

    @Test
    void contactDeletedCarriesTheWholeKey() {
        byte[] key = new byte[32];
        byte[] frame = new byte[33];
        frame[0] = (byte) 0x8F;
        System.arraycopy(key, 0, frame, 1, 32);
        assertEquals(32, assertInstanceOf(ContactDeletedFrame.class,
                MeshcoreFrameCodec.decode(frame)).publicKey().length);
        assertInstanceOf(DecodeFailure.class,
                MeshcoreFrameCodec.decode(TestUtil.hex("8F 0102")));
    }

    @Test
    void contactsFullAndOneKeyRejected() {
        assertInstanceOf(ContactsFullFrame.class,
                MeshcoreFrameCodec.decode(TestUtil.hex("90")));
        byte[] frame = new byte[33];
        frame[0] = (byte) 0x91;
        assertEquals(32, assertInstanceOf(OneKeyRejectedFrame.class,
                MeshcoreFrameCodec.decode(frame)).publicKey().length);
        assertInstanceOf(DecodeFailure.class,
                MeshcoreFrameCodec.decode(TestUtil.hex("91 0102")));
    }


    @Test
    void everyOpcodeTheDartReferenceDecodesIsModelledHere() {
        // The Dart codec dispatches 45 inbound opcodes. This port must model
        // the same set: an opcode it does not model is reported as
        // UnsupportedFrame, which is a gap rather than a decision, so the
        // set is pinned here and a new opcode on either side breaks the
        // test instead of drifting in silence.
        int[] modelled = {
            0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09,
            0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10, 0x11, 0x12, 0x13,
            0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1B, 0x1D,
            0x80, 0x81, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89,
            0x8A, 0x8B, 0x8D, 0x8E, 0x8F, 0x90, 0x91,
        };
        for (int op : modelled) {
            byte[] frame = new byte[64];
            frame[0] = (byte) op;
            MeshcoreInbound in = MeshcoreFrameCodec.decode(frame);
            assertFalse(in instanceof io.iotone.meshcore.frames.UnsupportedFrame,
                    () -> "opcode 0x" + Integer.toHexString(op)
                            + " is not modelled");
        }
        for (MeshcoreResponse r : MeshcoreResponse.values()) {
            boolean listed = false;
            for (int op : modelled) {
                listed = listed || op == r.code();
            }
            assertTrue(listed, () -> "MeshcoreResponse." + r.name()
                    + " names an opcode the decoder does not model");
        }
        assertEquals(45, MeshcoreResponse.values().length);
        assertEquals(45, modelled.length);
    }

}
