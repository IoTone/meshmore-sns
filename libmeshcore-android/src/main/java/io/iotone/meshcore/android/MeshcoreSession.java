// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package io.iotone.meshcore.android;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import java.io.IOException;
import java.util.ArrayDeque;
import java.util.Deque;
import java.util.concurrent.atomic.AtomicReference;

import io.iotone.meshcore.codec.MeshcoreFrameCodec;
import io.iotone.meshcore.frames.AdvertFrame;
import io.iotone.meshcore.frames.ChannelMessageFrame;
import io.iotone.meshcore.frames.ContactFrame;
import io.iotone.meshcore.frames.ContactMessageFrame;
import io.iotone.meshcore.frames.DecodeFailure;
import io.iotone.meshcore.frames.MeshcoreInbound;
import io.iotone.meshcore.frames.MessagesWaitingFrame;
import io.iotone.meshcore.frames.NoMoreMessagesFrame;
import io.iotone.meshcore.frames.SelfInfoFrame;
import io.iotone.meshcore.model.SelfInfo;
import io.iotone.meshcore.transport.MeshcoreTransport;

/**
 * MeshCore protocol session over any {@link MeshcoreTransport}.
 *
 * <p>Drives the connection lifecycle end-to-end:</p>
 * <ol>
 *   <li><strong>Handshake</strong> — on transport ready, sends
 *       {@code CMD_APP_START} and waits for {@code RESP_CODE_SELF_INFO}.
 *       Transitions to {@link SessionState#READY} and calls
 *       {@link SessionListener#onReady}.</li>
 *   <li><strong>Message pump</strong> — when {@code PUSH_CODE_MSGS_WAITING}
 *       (0x83) arrives, the session drains the device's queue by issuing
 *       {@code CMD_SYNC_NEXT_MESSAGE} (0x0A) repeatedly until
 *       {@code RESP_CODE_NO_MORE_MESSAGES} (0x0A) is received.</li>
 *   <li><strong>Frame dispatch</strong> — decoded frames are routed to
 *       the typed {@link SessionListener} callbacks on the main thread
 *       (inherited from the transport's dispatch thread).</li>
 * </ol>
 *
 * <p>RF-log frames (0x88) are buffered internally; use
 * {@link #exportInteropFixture} to produce a fixture JSON for the
 * {@code libmeshcore} interop test suite (see M6 runbook).</p>
 *
 * <h3>Usage</h3>
 * <pre>{@code
 * AndroidBleTransport transport = new AndroidBleTransport(context);
 * MeshcoreSession session = new MeshcoreSession("Meshmore", transport, listener);
 * transport.connect(device);   // triggers the handshake automatically
 * // …later…
 * session.sendChannelMessage(0, System.currentTimeMillis() / 1000, "hello");
 * }</pre>
 *
 * <p>All listener callbacks and all internal state transitions run on
 * the same thread the transport dispatches on (Android main thread for
 * {@link AndroidBleTransport}).</p>
 */
public final class MeshcoreSession {

    private static final int RF_LOG_BUFFER_CAP = 32;

    private final String appName;
    private final MeshcoreTransport transport;
    private final SessionListener listener;

    private final AtomicReference<SessionState> state =
            new AtomicReference<>(SessionState.DISCONNECTED);

    /** Most recent SELF_INFO received during the handshake. */
    @Nullable
    private volatile SelfInfo selfInfo;

    /**
     * Ring buffer of the last {@link #RF_LOG_BUFFER_CAP} RF-log frames
     * (0x88), as hex strings. Used by {@link #exportInteropFixture}.
     */
    private final Deque<String> rfLogCapture =
            new ArrayDeque<>(RF_LOG_BUFFER_CAP);

    /** True while the sync-drain loop is in progress. */
    private boolean draining = false;

    /**
     * Creates a session.
     *
     * @param appName   the app name announced to the device in
     *                  {@code CMD_APP_START} (max 64 UTF-8 bytes; no NUL)
     * @param transport the BLE (or other) transport to use; the session
     *                  registers itself as the listener
     * @param listener  receives typed frame callbacks and state changes
     */
    public MeshcoreSession(
            @NonNull String appName,
            @NonNull MeshcoreTransport transport,
            @NonNull SessionListener listener) {
        this.appName = appName;
        this.transport = transport;
        this.listener = listener;
        transport.setListener(new TransportListener());
    }

    // -------------------------------------------------------------------------
    // Public API
    // -------------------------------------------------------------------------

    /**
     * Returns the current session state.
     *
     * @return session state, never {@code null}
     */
    @NonNull
    public SessionState state() {
        return state.get();
    }

    /**
     * Returns the device self-info received during the handshake, or
     * {@code null} before the handshake completes.
     *
     * @return decoded {@link SelfInfo}, or {@code null}
     */
    @Nullable
    public SelfInfo selfInfo() {
        return selfInfo;
    }

    /**
     * Sends a channel text message. No-op when the session is not
     * {@link SessionState#READY}.
     *
     * @param channelIdx target channel slot (0-based)
     * @param timestamp  sender timestamp (unix seconds)
     * @param text       message text (UTF-8)
     */
    public void sendChannelMessage(int channelIdx, long timestamp,
            @NonNull String text) {
        if (state.get() != SessionState.READY) return;
        send(MeshcoreFrameCodec.sendChannelTextMessage(
                channelIdx, timestamp, text));
    }

    /**
     * Sends a direct message to a contact. No-op when not
     * {@link SessionState#READY}.
     *
     * @param pubKeyPrefix first 6 bytes of the recipient's public key
     * @param timestamp    sender timestamp (unix seconds)
     * @param text         message text (UTF-8)
     */
    public void sendDirectMessage(
            @NonNull byte[] pubKeyPrefix, long timestamp,
            @NonNull String text) {
        if (state.get() != SessionState.READY) return;
        send(MeshcoreFrameCodec.sendTextMessage(pubKeyPrefix, timestamp, text));
    }

    /**
     * Emits a self-advert into the mesh. No-op when not
     * {@link SessionState#READY}.
     *
     * @param flood {@code true} = flood, {@code false} = zero-hop
     */
    public void sendSelfAdvert(boolean flood) {
        if (state.get() != SessionState.READY) return;
        send(MeshcoreFrameCodec.sendSelfAdvert(flood));
    }

    /**
     * Requests self-telemetry from the device. The response arrives as
     * a {@code PUSH_CODE_TELEMETRY_RESPONSE} (0x8B) frame dispatched
     * to {@link SessionListener#onOtherFrame}. No-op when not
     * {@link SessionState#READY}.
     */
    public void requestSelfTelemetry() {
        if (state.get() != SessionState.READY) return;
        send(MeshcoreFrameCodec.sendTelemetryReq());
    }

    /**
     * Requests the device's stored contact list ({@code CMD_GET_CONTACTS},
     * 0x04). The device replies with {@code ContactsStartFrame}, one
     * {@link io.iotone.meshcore.frames.ContactFrame} per contact dispatched to
     * {@link SessionListener#onContact}, then {@code EndOfContactsFrame}.
     *
     * <p>Without this the contact list is never delivered: the device does not
     * push it on connect, so a client that only listens sees an empty mesh
     * while the radio's own screen shows a full one.</p>
     *
     * <p>No-op when not {@link SessionState#READY}.</p>
     */
    public void requestContacts() {
        if (state.get() != SessionState.READY) return;
        send(MeshcoreFrameCodec.getContacts());
    }

    /**
     * Requests battery voltage and storage usage
     * ({@code CMD_GET_BATT_AND_STORAGE}, 0x14). The reply arrives as a
     * {@link io.iotone.meshcore.frames.BatteryStorageFrame} on
     * {@link SessionListener#onOtherFrame}.
     *
     * <p>No-op when not {@link SessionState#READY}.</p>
     */
    public void requestBatteryStorage() {
        if (state.get() != SessionState.READY) return;
        send(MeshcoreFrameCodec.getBatteryStorage());
    }

    /**
     * Reads one channel slot ({@code CMD_GET_CHANNEL}, 0x1F). The reply
     * arrives as a {@link io.iotone.meshcore.frames.ChannelInfoFrame} on
     * {@link SessionListener#onOtherFrame}.
     *
     * <p>Slot numbering is the firmware's: 0 is conventionally the public
     * channel. A slot that is not configured answers with an empty name, so
     * enumerating channels means asking for each index and reading what comes
     * back — there is no "how many channels" query.</p>
     *
     * <p>No-op when not {@link SessionState#READY}.</p>
     *
     * @param channelIdx channel slot index
     */
    public void requestChannel(int channelIdx) {
        if (state.get() != SessionState.READY) return;
        send(MeshcoreFrameCodec.getChannel(channelIdx));
    }

    /**
     * Sets the position this node puts in its own adverts
     * ({@code CMD_SET_ADVERT_LATLON}, 0x0C). Degrees, converted to the
     * protocol's micro-degrees.
     *
     * <p>This is what other nodes will see and plot. A node with no GPS
     * reports 0/0 forever, and 0/0 is a real place in the Gulf of Guinea —
     * so an unset position is not a harmless blank, it is a wrong answer
     * that looks like a right one.</p>
     *
     * <p>No-op when not {@link SessionState#READY}.</p>
     *
     * @param latitude  degrees
     * @param longitude degrees
     */
    public void setAdvertPosition(double latitude, double longitude) {
        if (state.get() != SessionState.READY) return;
        send(MeshcoreFrameCodec.setAdvertLatLon(
                (int) Math.round(latitude * 1_000_000d),
                (int) Math.round(longitude * 1_000_000d)));
    }

    /**
     * Sets the advert location policy ({@code CMD_SET_OTHER_PARAMS}, 0x26)
     * while preserving the other params from {@code selfInfo}.
     *
     * <p>Policy 0 means the node omits its position from adverts however
     * good that position is, so setting a lat/lon without also setting this
     * changes nothing on the air.</p>
     *
     * <p>No-op when not {@link SessionState#READY} or before self-info.</p>
     *
     * @param policy advert location policy (0 = none, 1 = share)
     */
    public void setAdvertLocPolicy(int policy) {
        SelfInfo s = selfInfo();
        if (state.get() != SessionState.READY || s == null) return;
        send(MeshcoreFrameCodec.setOtherParams(
                s.manualAddContacts() ? 1 : 0, s.telemetryModeRaw(), policy, s.multiAcks()));
    }

    /**
     * Closes the session and disconnects the transport.
     */
    public void close() {
        setState(SessionState.DISCONNECTED);
        try {
            transport.close();
        } catch (IOException ignored) {
        }
    }

    /**
     * Builds a {@code grp_txt_capture} interop-fixture JSON from the
     * most recent RF-log capture (0x88 frame). Drop the returned string
     * as a {@code .json} file into both:
     * <ul>
     *   <li>{@code packages/meshcore/test/vectors/interop/}</li>
     *   <li>{@code libmeshcore/src/test/resources/vectors/interop/}</li>
     * </ul>
     * and run {@code dart test} / {@code ./gradlew test} to validate
     * both libraries simultaneously.
     *
     * @param pskHex              the channel PSK as a lowercase hex string
     *                            (16 bytes = 32 hex chars); use
     *                            {@code "8b3387e9c5cdea6ac9e5edbaa115cd72"}
     *                            for the Public channel
     * @param knownPlaintextUtf8  the exact text the sender transmitted
     *                            (must be a message you can verify arrived)
     * @param firmwareVersion     the flashed firmware version string, for
     *                            fixture provenance ({@code "companion-v1.15.0"})
     * @return fixture JSON, or {@code null} if no 0x88 frame is buffered
     *         yet (send a channel message and wait a moment first)
     */
    @Nullable
    public String exportInteropFixture(
            @NonNull String pskHex,
            @NonNull String knownPlaintextUtf8,
            @NonNull String firmwareVersion) {
        // Walk the RF-log ring newest-first for the last 0x88 frame.
        String lastRfLog = null;
        for (String hex : rfLogCapture) {
            if (hex.startsWith("88") || hex.startsWith("8b")) {
                // Both 0x88 (RF log) and 0x8b (telemetry) start with 8x.
                // We want only 0x88.
                if (hex.startsWith("88")) {
                    lastRfLog = hex;
                    break;
                }
            }
        }
        if (lastRfLog == null) return null;

        SelfInfo self = selfInfo;
        return "{\n"
                + "  \"kind\": \"grp_txt_capture\",\n"
                + "  \"description\": \"Public-channel capture from "
                + (self != null ? self.name() : "unknown") + "\",\n"
                + "  \"firmware\": \"" + firmwareVersion + "\",\n"
                + "  \"channel_name\": \"Public\",\n"
                + "  \"psk_hex\": \"" + pskHex + "\",\n"
                + "  \"known_plaintext_utf8\": \"" + knownPlaintextUtf8 + "\",\n"
                + "  \"rf_log_frame_hex\": \"" + lastRfLog + "\"\n"
                + "}\n";
    }

    // -------------------------------------------------------------------------
    // Internal: transport listener + frame dispatch
    // -------------------------------------------------------------------------

    private class TransportListener implements MeshcoreTransport.Listener {

        @Override
        public void onFrame(@NonNull byte[] frame) {
            // Buffer every raw frame as hex for the RF-log capture.
            String hex = bytesToHex(frame);
            if (rfLogCapture.size() >= RF_LOG_BUFFER_CAP) {
                rfLogCapture.pollLast();
            }
            rfLogCapture.addFirst(hex);

            MeshcoreInbound decoded = MeshcoreFrameCodec.decode(frame);
            dispatch(decoded);
        }

        @Override
        public void onConnectionChanged(boolean connected) {
            if (connected) {
                setState(SessionState.HANDSHAKING);
                // Kick off the handshake immediately.
                send(MeshcoreFrameCodec.appStart(appName));
            } else {
                setState(SessionState.DISCONNECTED);
                draining = false;
            }
        }
    }

    private void dispatch(@NonNull MeshcoreInbound frame) {
        if (frame instanceof SelfInfoFrame f) {
            selfInfo = f.selfInfo();
            setState(SessionState.READY);
            // Drain any messages that accumulated while we were offline.
            triggerDrain();
            listener.onReady(f.selfInfo());
            return;
        }
        if (frame instanceof MessagesWaitingFrame) {
            triggerDrain();
            return;
        }
        if (frame instanceof NoMoreMessagesFrame) {
            draining = false;
            return;
        }
        if (frame instanceof ChannelMessageFrame f) {
            listener.onChannelMessage(f);
            continueDrain();
            return;
        }
        if (frame instanceof ContactMessageFrame f) {
            listener.onContactMessage(f);
            continueDrain();
            return;
        }
        if (frame instanceof AdvertFrame f) {
            listener.onAdvert(f);
            return;
        }
        if (frame instanceof ContactFrame f) {
            listener.onContact(f);
            continueDrain();
            return;
        }
        if (frame instanceof DecodeFailure f) {
            listener.onDecodeFailure(f);
            return;
        }
        // Everything else (OkFrame, BatteryStorageFrame, TelemetryResponse…).
        listener.onOtherFrame(frame);
        continueDrain();
    }

    /**
     * Start the sync-drain loop if not already draining and the session
     * is ready.
     */
    private void triggerDrain() {
        if (!draining && state.get() == SessionState.READY) {
            draining = true;
            send(MeshcoreFrameCodec.syncNextMessage());
        }
    }

    /**
     * Issue the next {@code SYNC_NEXT_MESSAGE} if a drain is in progress.
     */
    private void continueDrain() {
        if (draining) {
            send(MeshcoreFrameCodec.syncNextMessage());
        }
    }

    private void setState(@NonNull SessionState next) {
        SessionState prev = state.getAndSet(next);
        if (prev != next) {
            listener.onStateChanged(next);
        }
    }

    private void send(@NonNull byte[] frame) {
        try {
            transport.send(frame);
        } catch (IOException | IllegalStateException e) {
            // Link dropped mid-session; the connection-observer will fire
            // onConnectionChanged(false) and reset the state.
        }
    }

    private static String bytesToHex(@NonNull byte[] bytes) {
        StringBuilder sb = new StringBuilder(bytes.length * 2);
        for (byte b : bytes) {
            sb.append(String.format("%02x", b));
        }
        return sb.toString();
    }
}
