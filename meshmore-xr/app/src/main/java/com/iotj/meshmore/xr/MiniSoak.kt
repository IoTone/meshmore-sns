// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

/**
 * TEN PACKETS IN A MINUTE, AT A NODE YOU OWN.
 *
 * The hour-long soaks answered "does this mesh deliver", and their answer was
 * roughly nine times in ten. This asks a narrower question about one radio: it
 * fires ten full-length messages a few seconds apart and reports what came
 * back, which is what you want when the thing under test is a device on your
 * own bench rather than the band.
 *
 * FULL LENGTH MEANS BYTES, NOT CHARACTERS, and that is the point of mixing the
 * scripts. A kanji is three UTF-8 bytes and an emoji is four, so a message that
 * looks short can be the longest thing the radio has ever been asked to carry —
 * and a firmware that counts characters where it should count bytes fails on
 * exactly this input and on nothing else. The preamble stays ASCII so a garbled
 * arrival can still be read well enough to say WHICH message it was.
 */
object MiniSoak {

    /** How many messages one run sends. */
    const val COUNT = 10

    /** Seconds between them: ten messages spread across a minute. */
    const val EVERY_S = 6

    /**
     * Target size of one message in UTF-8 bytes.
     *
     * MeshCore's bindings carry no text-length constant and the firmware's own
     * limit is not published in anything this project can read, so this is a
     * measured guess: comfortably inside a 255-byte radio packet after the
     * six-byte key prefix, the timestamp and the frame header. The byte count
     * of every message is logged, so if the radio starts refusing, the number
     * that did it is on the record rather than inferred.
     */
    const val TARGET_BYTES = 140

    /**
     * THE THREE LENGTHS A RUN CYCLES THROUGH.
     *
     * The first twenty packets this instrument sent were all 135 bytes, all
     * direct, all one hop — so the ledger's by-size, by-route and by-hop
     * breakdowns each came back as a single row saying 95%, which is the
     * number that was already known. A measurement that cannot vary the thing
     * it is measuring cannot attribute anything.
     *
     * So a run rotates through a short, a middling and a full-length message,
     * and each lands in a different one of [TxLog]'s size buckets. If loss
     * concentrates in the long one, the packet is over the link budget in use
     * and the repair is a spreading factor. If it does not, the loss is the
     * radio link itself and no amount of shortening will help — which is worth
     * knowing before anybody spends a week shortening things.
     */
    val SIZES = listOf(48, 96, TARGET_BYTES)

    /** Which length message [n] of a run should be, 1-based. */
    fun sizeFor(n: Int): Int = SIZES[(n - 1) % SIZES.size]

    /** Latin, kanji and emoji in rotation — one of each per cycle. */
    private val FILLER = listOf(
        "MESH", "電波", "🛰", "TEST", "受信", "📡", "LINK", "中継", "🔆", "NODE", "確認", "✅",
    )

    /**
     * Build message [n] of a run.
     *
     * [stamp] is the wall-clock preamble, e.g. "14:03:22". The result is padded
     * with [FILLER] until one more piece would exceed [TARGET_BYTES], so it
     * never splits a character and never overshoots.
     */
    fun message(stamp: String, n: Int, targetBytes: Int = TARGET_BYTES): String {
        val head = "$stamp #%02d ".format(n)
        val sb = StringBuilder(head)
        var i = 0
        while (true) {
            val piece = FILLER[i % FILLER.size] + " "
            if (bytes(sb.toString() + piece) > targetBytes) break
            sb.append(piece)
            i++
            // A run of filler that cannot fit even its shortest piece would
            // spin forever; the shortest is four bytes, so this cannot, but
            // the guard costs nothing and the alternative is a hung radio.
            if (i > 200) break
        }
        return sb.toString().trimEnd()
    }

    fun bytes(s: String): Int = s.toByteArray(Charsets.UTF_8).size

    /** What a finished run amounts to, in one line. */
    fun report(sent: Int, accepted: Int, acked: Int, meanMs: Long): String =
        "sent=$sent accepted=$accepted acked=$acked " +
            "reliability=%.0f%% mean=%dms".format(
                if (sent == 0) 0.0 else acked * 100.0 / sent, meanMs,
            )
}
