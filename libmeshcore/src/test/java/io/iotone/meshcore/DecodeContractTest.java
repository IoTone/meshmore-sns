// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package io.iotone.meshcore;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertInstanceOf;
import static org.junit.jupiter.api.Assertions.assertSame;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.iotone.meshcore.codec.DecodeErrorKind;
import io.iotone.meshcore.codec.FrameBuilder;
import io.iotone.meshcore.codec.MeshcoreFrameCodec;
import io.iotone.meshcore.frames.AckFrame;
import io.iotone.meshcore.frames.ChannelDataFrame;
import io.iotone.meshcore.frames.ChannelInfoFrame;
import io.iotone.meshcore.frames.CliReplyFrame;
import io.iotone.meshcore.frames.DecodeFailure;
import io.iotone.meshcore.frames.MeshcoreInbound;
import io.iotone.meshcore.frames.UnsupportedFrame;
import io.iotone.meshcore.model.ChannelData;
import io.iotone.meshcore.model.ChannelInfo;
import io.iotone.meshcore.model.RxVia;

import org.junit.jupiter.api.Test;

/**
 * The decode contract as the Dart reference codec states it: a frame is
 * consumed exactly, the receive frames surface their bytes instead of
 * dropping them, and the push/reply split is the firmware's own.
 */
class DecodeContractTest {

    private static MeshcoreInbound decode(String hex) {
        return MeshcoreFrameCodec.decode(TestUtil.hex(hex));
    }

    // --- DEVICE_QUERY protocol version ---------------------------------

    @Test
    void deviceQueryAsksForTheVersionWhoseFramesCarrySnr() {
        // [0x16][3]: the firmware stores the byte and gates the V3 receive
        // frames on >= 3 (MyMesh.cpp:435-443, :548-556).
        assertEquals("1603", TestUtil.toHex(MeshcoreFrameCodec.deviceQuery()));
        assertEquals(3, MeshcoreConstants.APP_TARGET_PROTOCOL_VERSION);
    }

    @Test
    void anOlderProtocolVersionIsStillExpressible() {
        assertEquals("1601", TestUtil.toHex(MeshcoreFrameCodec.deviceQuery(1)));
    }

    // --- decode consumes the whole frame -------------------------------

    @Test
    void twoFramesInOneBufferAreReportedNotHalfDecoded() {
        // CURR_TIME (0x09) is exactly 5 bytes, so a second one is visible.
        DecodeFailure df = assertInstanceOf(DecodeFailure.class,
                decode("0900f15365" + "0900f15365"));
        assertEquals(DecodeErrorKind.TRAILING_BYTES, df.error().kind());
        assertEquals(0x09, df.error().opcode().getAsInt());
        assertTrue(df.error().message().contains("5 byte"),
                df.error().message());
    }

    @Test
    void oneStrayByteAfterACompleteFrameIsReported() {
        DecodeFailure df = assertInstanceOf(DecodeFailure.class,
                decode("0900f15365" + "00"));
        assertEquals(DecodeErrorKind.TRAILING_BYTES, df.error().kind());
    }

    @Test
    void anUnknownOpcodeIsStillPreservedNeverATrailingFailure() {
        UnsupportedFrame f = assertInstanceOf(UnsupportedFrame.class,
                decode("7edeadbeef"));
        assertEquals(0x7E, f.opcode());
        assertArrayEquals(TestUtil.hex("7edeadbeef"), f.raw());
    }

    // --- RESP_CODE_CLI_REPLY (0x1D) ------------------------------------

    @Test
    void cliReplyCarriesOneOutputLine() {
        MeshcoreInbound got = decode(TestUtil.toHex(
                new byte[] {0x1D, 'o', 'k'}));
        CliReplyFrame f = assertInstanceOf(CliReplyFrame.class, got);
        assertEquals("ok", f.text());
    }

    @Test
    void aBareCliOpcodeIsAnEmptyLineNotAFailure() {
        CliReplyFrame f = assertInstanceOf(CliReplyFrame.class, decode("1d"));
        assertEquals("", f.text());
    }

    // --- RESP_CODE_CHANNEL_INFO secret widths --------------------------

    @Test
    void channelInfoAcceptsTheOrdinarySixteenByteSecret() {
        ChannelInfo info = channelInfo(16);
        assertEquals(16, info.psk().length);
    }

    @Test
    void channelInfoAcceptsTheFullThirtyTwoByteSecret() {
        ChannelInfo info = channelInfo(32);
        assertEquals(32, info.psk().length);
    }

    @Test
    void channelInfoRejectsAWidthTheFirmwareDoesNotSend() {
        DecodeFailure df = assertInstanceOf(DecodeFailure.class,
                decode(channelInfoHex(15)));
        assertEquals(DecodeErrorKind.TRUNCATED, df.error().kind());
        assertEquals(0x12, df.error().opcode().getAsInt());
    }

    private static ChannelInfo channelInfo(int pskLen) {
        return assertInstanceOf(ChannelInfoFrame.class,
                decode(channelInfoHex(pskLen))).info();
    }

    private static String channelInfoHex(int pskLen) {
        byte[] psk = new byte[pskLen];
        for (int i = 0; i < pskLen; i++) {
            psk[i] = (byte) i;
        }
        return TestUtil.toHex(new FrameBuilder()
                .u8(0x12)
                .u8(3)
                .fixed("ch".getBytes(java.nio.charset.StandardCharsets.UTF_8),
                        MeshcoreConstants.CHANNEL_NAME_SIZE)
                .raw(psk)
                .build());
    }

    // --- RESP_CODE_CHANNEL_DATA_RECV (0x1B) ----------------------------

    @Test
    void channelDataReadsLittleEndianTypeAndTheFloodPath() {
        // [1B][snr 8][via 0][rsvd 0][ch 2][path FF][type 34 FF][len 3][1 2 3]
        ChannelData d = assertInstanceOf(ChannelDataFrame.class,
                decode("1b08000002ff34ff03010203")).data();
        assertEquals(2.0, d.snrDb(), 1e-9);
        assertEquals(2, d.channelIndex());
        assertEquals(0xFF, d.pathLen());
        assertTrue(d.isFlood());
        assertEquals(0xFF34, d.dataType());
        assertArrayEquals(new byte[] {1, 2, 3}, d.data());
        assertSame(RxVia.UNKNOWN, d.via());
    }

    @Test
    void channelDataSurfacesTheReceivingProfile() {
        // onChannelDataRecv writes the profile tag in the byte after SNR:
        // 0xA0 the primary radio, 0xA1 the second one, 0 on a single-profile
        // radio (MyMesh.cpp:2423).
        assertSame(RxVia.UNKNOWN, channelData(0x00).via());
        assertSame(RxVia.PRIMARY, channelData(0xA0).via());
        assertSame(RxVia.SECONDARY, channelData(0xA1).via());
        // A tag from neither profile is not guessed at.
        assertSame(RxVia.UNKNOWN, channelData(0x7F).via());
    }

    @Test
    void channelDataLengthThatOverrunsTheFrameIsAFailure() {
        // The length byte says 9; the frame carries 1 data byte.
        assertInstanceOf(DecodeFailure.class, decode(TestUtil.toHex(
                new byte[] {0x1B, 0, 0, 0, 0, 0, 1, 0, 9, 1})));
    }

    private static ChannelData channelData(int via) {
        return assertInstanceOf(ChannelDataFrame.class, decode(TestUtil.toHex(
                new byte[] {0x1B, 8, (byte) via, 0, 2, (byte) 0xFF,
                    0x34, (byte) 0xFF, 3, 1, 2, 3}))).data();
    }

    @Test
    void rxViaMapsOnlyTheTwoTagsTheFirmwareWrites() {
        assertSame(RxVia.PRIMARY,
                RxVia.fromWireByte(MeshcoreConstants.RX_VIA_PRIMARY_TAG));
        assertSame(RxVia.SECONDARY,
                RxVia.fromWireByte(MeshcoreConstants.RX_VIA_SECONDARY_TAG));
        // Both "none" sentinels: 0 for a channel datagram, 0xFF for raw data.
        assertSame(RxVia.UNKNOWN, RxVia.fromWireByte(0));
        assertSame(RxVia.UNKNOWN, RxVia.fromWireByte(0xFF));
    }

    // --- PUSH_CODE_SEND_CONFIRMED (0x82) -------------------------------

    @Test
    void sendConfirmedCarriesTheRoundTripTime() {
        // MyMesh.cpp:418-422 writes the 4-byte tag and a 4-byte trip time.
        AckFrame f = assertInstanceOf(AckFrame.class,
                decode("8278563412e8030000"));
        assertEquals(0x12345678L, f.ackCrc());
        assertEquals(1000L, f.roundTripMs().getAsLong());
    }

    @Test
    void sendConfirmedWithOnlyTheTagIsAccepted() {
        AckFrame f = assertInstanceOf(AckFrame.class, decode("8278563412"));
        assertEquals(0x12345678L, f.ackCrc());
        assertFalse(f.roundTripMs().isPresent());
    }

    // --- the push/reply split ------------------------------------------

    @Test
    void everyReplyCodeSitsBelowThePushBlock() {
        // The firmware's own split: PUSH_CODE_* at 0x80 and above under the
        // "these are _pushed_ to client app at any time" comment
        // (MyMesh.cpp:111-128). 0x1B and 0x1D arrive unasked in the same
        // breath but answer a command the client sent, so they are replies.
        for (MeshcoreResponse r : MeshcoreResponse.values()) {
            if (r.code() >= 0x80) {
                assertTrue(r.isPush(), r + " is a push");
            } else {
                assertFalse(r.isPush(), r + " is a reply");
            }
        }
        assertFalse(MeshcoreResponse.CHANNEL_DATA_RECV.isPush());
        assertFalse(MeshcoreResponse.CLI_REPLY.isPush());
        assertEquals(0x1B, MeshcoreResponse.CHANNEL_DATA_RECV.code());
        assertEquals(0x1D, MeshcoreResponse.CLI_REPLY.code());
    }
}
