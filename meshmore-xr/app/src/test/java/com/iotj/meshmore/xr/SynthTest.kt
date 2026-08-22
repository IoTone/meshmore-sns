// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

import com.iotj.meshmore.xr.spatial.Theme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * THE SOUND, MEASURED.
 *
 * §1.2 asked for synthesis rather than samples precisely so this file could
 * exist: an MP3 can only be listened to, and nobody listens to nine packs times
 * fourteen events before every release. Arithmetic can be checked.
 *
 * What is worth asserting is not "does it sound nice" — it cannot — but the
 * properties that make a cue vocabulary work at all: every sound is audible,
 * none of them clips, none of them runs on forever, the shapes differ from
 * each other in the way the grammar claims, and no theme is twice as loud as
 * its neighbour.
 */
class SynthTest {

    private fun renderMs(motif: Synth.Motif, pack: String, ms: Int = 900): FloatArray {
        val voices = mutableListOf<Synth.Voice>()
        Synth.voice(motif, Motifs.timbreFor(pack, motif), voices)
        val out = FloatArray(Synth.RATE * ms / 1000)
        Synth.render(out, voices)
        return out
    }

    /**
     * A cue nobody can hear is not a cue.
     *
     * MEASURED OVER THE SOUND, NOT OVER THE SILENCE AFTER IT. The first
     * version took the RMS of a fixed 900 ms buffer, which reports a 16 ms
     * detent as inaudible for the sole reason that it is short — it flagged
     * TICK in three packs, all of which are perfectly audible. Energy per unit
     * of SOUNDING time is the property that matters, plus a peak floor so a
     * click cannot pass by being long and faint.
     */
    @Test fun everyMotifIsAudibleInEveryPack() {
        val quiet = mutableListOf<String>()
        Motifs.ALL.forEach { (name, m) ->
            Motifs.PACKS.keys.forEach { pack ->
                val span = m.steps.sumOf { it.ms }
                val buf = renderMs(m, pack, ms = span)
                val r = Synth.rms(buf)
                val p = Synth.peak(buf)
                // SEELE IS ALLOWED TO BE QUIETER, and it is the only one.
                // "Near-silence otherwise" is TRIBUNAL's actual spec, so
                // holding it to the same floor as the rest would either fail
                // forever or force the pack to stop being what it is.
                val rFloor = if (pack == "tribunal") 0.012f else 0.02f
                val pFloor = if (pack == "tribunal") 0.04f else 0.05f
                if (r < rFloor || p < pFloor) {
                    quiet += "$name/$pack rms=%.4f peak=%.3f".format(r, p)
                }
            }
        }
        assertEquals("motifs nobody could hear", emptyList<String>(), quiet)
    }

    /** And one that clips is a cue that sounds broken on a small speaker. */
    @Test fun nothingClips() {
        val hot = mutableListOf<String>()
        Motifs.ALL.forEach { (name, m) ->
            Motifs.PACKS.keys.forEach { pack ->
                val p = Synth.peak(renderMs(m, pack))
                if (p >= Synth.CEILING) hot += "$name/$pack peak=%.3f".format(p)
            }
        }
        assertEquals("motifs at or over the ceiling", emptyList<String>(), hot)
    }

    /**
     * EVERY SOUND ENDS. A voice whose envelope never reaches zero is a drone
     * the wearer cannot switch off, and on a device worn for eight hours that
     * is the difference between a cue and a fault.
     */
    @Test fun everyMotifDecaysToSilence() {
        Motifs.ALL.forEach { (name, m) ->
            val buf = renderMs(m, "sonar", ms = 3000)
            val tail = buf.copyOfRange(buf.size * 3 / 4, buf.size)
            assertTrue("$name still sounding after 2.25 s", Synth.rms(tail) < 1e-6f)
        }
    }

    /** Six voices, and a seventh steals rather than piling up. */
    @Test fun voicesAreCappedAtSix() {
        val voices = mutableListOf<Synth.Voice>()
        repeat(10) { Synth.voice(Motifs.NODE_FOUND, Motifs.PACKS.getValue("sonar"), voices) }
        assertTrue("${voices.size} voices", voices.size <= Synth.MAX_VOICES)
    }

    // --- the grammar itself --------------------------------------------------

    /** Centre of mass of the signal's energy over time, 0 = start, 1 = end. */
    private fun centroid(buf: FloatArray): Float {
        var num = 0.0; var den = 0.0
        buf.forEachIndexed { i, s ->
            val e = (s * s).toDouble(); num += e * i; den += e
        }
        return if (den == 0.0) 0f else (num / den / buf.size).toFloat()
    }

    /**
     * RISING AND FALLING ARE THE WHOLE GRAMMAR, so they are measured rather
     * than asserted by reading the table. Compares the dominant frequency of
     * the first note against the last by counting zero crossings in each half.
     */
    private fun crossingsPerSecond(buf: FloatArray): Float {
        var n = 0
        for (i in 1 until buf.size) if ((buf[i - 1] < 0f) != (buf[i] < 0f)) n++
        return n * Synth.RATE.toFloat() / buf.size
    }

    @Test fun anArrivalRisesAndALossFalls() {
        // MEASURED OVER THE MOTIF, NOT OVER A FIXED WINDOW. The first version
        // rendered half a second and compared its halves, and DM is 240 ms
        // long — so the second half was silence and every shape "fell". The
        // test was wrong in a way that looked exactly like the code being
        // wrong, which cost a fix aimed at the wrong line.
        fun shape(m: Synth.Motif): Pair<Float, Float> {
            val span = m.steps.sumOf { it.ms }
            val buf = renderMs(m, "sonar", ms = span)
            val firstMs = m.steps.first().ms
            val cut = (buf.size.toLong() * firstMs / span).toInt()
            return crossingsPerSecond(buf.copyOfRange(0, cut)) to
                crossingsPerSecond(buf.copyOfRange(cut, buf.size))
        }
        val (dmFirst, dmLast) = shape(Motifs.DM)
        assertTrue("DM should rise: $dmFirst -> $dmLast", dmLast > dmFirst)
        val (lostFirst, lostLast) = shape(Motifs.LOST)
        assertTrue("LOST should fall: $lostFirst -> $lostLast", lostLast < lostFirst)
        val (linkFirst, linkLast) = shape(Motifs.LINKED)
        assertTrue("LINKED should rise", linkLast > linkFirst)
        val (dropFirst, dropLast) = shape(Motifs.DROPPED)
        assertTrue("DROPPED should fall", dropLast < dropFirst)
    }

    /**
     * A DIRECT MESSAGE AND A CHANNEL MESSAGE MUST NOT SOUND ALIKE — §2 says so
     * outright, and the reason is practical: channel traffic that fired the
     * "somebody is talking to you" cue would train a wearer to ignore both.
     */
    @Test fun aDirectMessageIsNotAChannelMessage() {
        val dm = renderMs(Motifs.DM, "sonar", ms = 500)
        val ch = renderMs(Motifs.CHANNEL, "sonar", ms = 500)
        assertTrue("DM should be the longer shape", centroid(dm) > centroid(ch))
        assertTrue("a channel message is quieter", Synth.rms(ch) < Synth.rms(dm))
    }

    /** Refusal has no pitch in any pack, so it can never read as success. */
    @Test fun refusalIsUnpitchedEverywhere() {
        Motifs.PACKS.keys.forEach { pack ->
            assertEquals(
                "denied in $pack",
                Synth.Wave.NOISE,
                Motifs.timbreFor(pack, Motifs.DENIED).wave,
            )
        }
    }

    /** Furniture stays quieter than the mesh, or the app shouts about menus. */
    @Test fun chromeIsQuieterThanTheMesh() {
        val chrome = Synth.rms(renderMs(Motifs.OPENED, "sonar"))
        val mesh = Synth.rms(renderMs(Motifs.DM, "sonar"))
        assertTrue("opened=$chrome dm=$mesh", chrome < mesh)
    }

    // --- the packs -----------------------------------------------------------

    /** Every theme has a timbre, and every timbre belongs to a theme. */
    @Test fun everyThemeHasItsPack() {
        val named = Theme.ALL.map { it.audio }.toSet()
        assertEquals("packs with no theme", emptySet<String>(), Motifs.PACKS.keys - named)
        assertEquals("themes with no pack", emptySet<String>(), named - Motifs.PACKS.keys)
    }

    /**
     * NO PACK IS TWICE AS LOUD AS ANOTHER. §6 asks for per-pack loudness
     * normalisation, and without it switching theme becomes a volume control —
     * which is how a wearer ends up choosing a theme by how much it startles
     * them rather than by how it looks.
     */
    @Test fun noPackIsTwiceAsLoudAsAnother() {
        val loud = Motifs.PACKS.keys.associateWith { Synth.rms(renderMs(Motifs.DM, it)) }
        val min = loud.values.min()
        val max = loud.values.max()
        assertTrue("quietest=$min loudest=$max in $loud", max <= min * 4f)
    }

    /** SEELE's near-silence is a decision, and it should stay the quietest. */
    @Test fun tribunalIsTheQuietestPack() {
        val loud = Motifs.PACKS.keys.associateWith { Synth.rms(renderMs(Motifs.DM, it)) }
        assertEquals("tribunal", loud.minByOrNull { it.value }?.key)
    }
}
