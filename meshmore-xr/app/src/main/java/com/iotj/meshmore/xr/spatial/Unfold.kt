// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.unit.dp
import kotlin.math.abs
import kotlin.random.Random

/**
 * Diagnostic surfaces are the ONE place a rectangle is allowed, and even there
 * it must not arrive like a mobile dialog. It glitch-teleports in: a targeting
 * reticle snaps to the spot, holds, then the frame unfolds along one axis and
 * the content fades up inside it.
 *
 * Three stages, all driven from a single 0..1 clock so they cannot drift:
 *
 *   0.00-0.30  ARRIVE   corner brackets punch in, jittering; scanline noise
 *   0.30-0.62  UNFOLD   the frame opens vertically from a horizontal slit
 *   0.62-1.00  SETTLE   jitter decays, content fades up, brackets thin out
 *
 * Every phase respects reduce-motion by collapsing to its end state.
 */
object Unfold {

    /** The panel's own arrival clock. Returns 0..1. */
    @Composable
    fun rememberClock(durationMs: Int = 900, reduceMotion: Boolean = false): Float {
        val anim = remember { Animatable(if (reduceMotion) 1f else 0f) }
        LaunchedEffect(Unit) {
            if (!reduceMotion) {
                anim.animateTo(1f, tween(durationMs, easing = LinearEasing))
            }
        }
        return anim.value
    }

    /**
     * Draws the reticle + unfold over whatever content the panel holds.
     * Content should be scaled/clipped by [foldOpen] so it reveals with the frame.
     */
    @Composable
    fun Frame(
        t: Float,
        accent: Color,
        alt: Color,
        modifier: Modifier = Modifier,
        content: @Composable (contentAlpha: Float, foldOpen: Float) -> Unit,
    ) {
        // Glitch offsets are re-rolled a few times a second, not every frame:
        // per-frame noise reads as a broken renderer, stepped noise reads as
        // deliberate signal corruption.
        var seed by remember { mutableFloatStateOf(0f) }
        LaunchedEffect(t) {
            if (t < 0.62f) seed = Random.nextFloat()
        }

        val arrive = (t / 0.30f).coerceIn(0f, 1f)
        val fold = ((t - 0.30f) / 0.32f).coerceIn(0f, 1f)
        val settle = ((t - 0.62f) / 0.38f).coerceIn(0f, 1f)

        // ease-out on fold so the frame snaps open then eases to rest
        val foldOpen = 1f - (1f - fold) * (1f - fold)
        val jitter = (1f - settle) * (1f - t * 0.4f)

        Box(modifier.fillMaxSize()) {
            content(settle, foldOpen)
            Canvas(Modifier.fillMaxSize()) {
                drawReticle(arrive, foldOpen, settle, jitter, seed, accent, alt)
            }
        }
    }

    private fun DrawScope.drawReticle(
        arrive: Float, foldOpen: Float, settle: Float,
        jitter: Float, seed: Float, accent: Color, alt: Color,
    ) {
        val w = size.width
        val h = size.height
        val cy = h / 2f
        // The frame opens from a horizontal slit at the vertical centre.
        val halfH = (h / 2f) * foldOpen
        val top = cy - halfH
        val bot = cy + halfH

        val jx = (seed - 0.5f) * 18f * jitter
        val jy = (abs(seed - 0.3f) - 0.2f) * 10f * jitter

        val stroke = 2.2.dp.toPx()
        val arm = (w * 0.13f).coerceAtLeast(28f)
        val a = 0.25f + 0.75f * arrive

        // corner brackets — the reticle. They punch in before anything unfolds.
        val corners = listOf(
            Triple(0f, top, 1f to 1f),
            Triple(w, top, -1f to 1f),
            Triple(0f, bot, 1f to -1f),
            Triple(w, bot, -1f to -1f),
        )
        corners.forEach { (x, y, dir) ->
            val (sx, sy) = dir
            val px = x + jx * sx
            val py = y + jy * sy
            drawLine(accent.copy(alpha = a), Offset(px, py), Offset(px + arm * sx, py), stroke)
            drawLine(
                accent.copy(alpha = a), Offset(px, py),
                Offset(px, py + arm * 0.55f * sy), stroke,
            )
        }

        // the opening slit itself — bright while folding, fades once open
        if (foldOpen < 0.995f) {
            val slit = (1f - foldOpen).coerceIn(0f, 1f)
            drawLine(
                alt.copy(alpha = 0.9f * slit + 0.15f),
                Offset(jx, cy), Offset(w + jx, cy), stroke * 1.6f,
            )
        }

        // scanline tear during arrival — one displaced band, not a full overlay
        if (jitter > 0.02f) {
            val band = (seed * h * 0.9f) + top * 0.05f
            drawLine(
                alt.copy(alpha = 0.35f * jitter),
                Offset(jx * 2f, band), Offset(w + jx * 2f, band), stroke * 2.4f,
            )
        }

        // edge rails settle in last, thin and quiet
        if (settle > 0f) {
            val e = settle * 0.5f
            drawLine(accent.copy(alpha = e), Offset(0f, top), Offset(w, top), stroke * 0.6f)
            drawLine(accent.copy(alpha = e), Offset(0f, bot), Offset(w, bot), stroke * 0.6f)
        }
    }
}
