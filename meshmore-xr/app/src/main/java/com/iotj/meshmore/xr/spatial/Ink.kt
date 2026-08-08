// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

import android.util.Log
import androidx.xr.runtime.math.Vector4
import androidx.xr.scenecore.KhronosUnlitMaterial
import java.lang.ref.WeakReference

/**
 * RESTYLING A SCENE THAT IS ALREADY BUILT.
 *
 * ## The finding this is built on
 *
 * `MeshEntity.setAlpha` is a no-op on the Khronos-unlit path — proved on device
 * 2026-08-02, and the reason half this codebase animates scale instead of
 * brightness. From that it looked as though colour was baked at creation too,
 * and that a theme change therefore meant tearing the scene down and building
 * it again.
 *
 * It is not. `KhronosUnlitMaterial.setBaseColorFactor(Vector4)` is a SETTER,
 * and it is the same call [Prims.material] already makes once at creation. A
 * material can be re-coloured in place, at any time, for free. What is fixed is
 * the per-facet lambert baked into the vertex colours — and that is a
 * MULTIPLIER (glTF unlit: baseColor = factor x COLOR_0), so rewriting the
 * factor restyles the mark and leaves its shading intact. Which is exactly what
 * a theme change wants and nothing more.
 *
 * So: theme switching is a walk over a list of materials, and section S11's
 * "preview live on the actual HORIZON, not in a swatch" is affordable rather
 * than aspirational.
 *
 * ## Why a reverse lookup and not a role parameter
 *
 * Nothing here is passed a role. Materials are created by call sites that say
 * `Prims.material(session, theme.accent, 0.42f)` — the role is in the source
 * text and gone by the time the value arrives. Rather than thread an enum
 * through some two hundred of those, [register] looks the value back up in the
 * palette it was created under and records the ROLE it matched.
 *
 * That needs the roles in a palette to be distinguishable by value, which three
 * single-hue themes are not by design. [Theme] documents the one-unit nudge
 * that resolves them.
 *
 * ## What this deliberately does not do
 *
 * It does not hold a strong reference to anything. A material outlives its
 * entity only as garbage, and [Horizon] disposes and rebuilds its entire
 * entity list every time mesh membership changes — which on a live mesh is
 * every few seconds. A strong list here would be an unbounded leak with a
 * rebuild timer attached. Weak references let the collector do the pruning, and
 * [retint] drops the cleared slots as it passes.
 */
object Ink {

    private const val TAG = "MeshmoreXR"

    /** Which palette entry a colour came from. */
    enum class Role { ACCENT, ALT, WARN, TEXT }

    private class Held(
        val mat: WeakReference<KhronosUnlitMaterial>,
        val role: Role,
        val alpha: Float,
    )

    /** Anything that can be re-inked but is not a material — text panels, mostly. */
    fun interface Tintable {
        /** Returns false when the target is gone and the entry should be dropped. */
        fun setInk(argb: Int): Boolean
    }

    private class HeldText(val target: WeakReference<Tintable>, val role: Role, val alpha: Float)

    private val mats = ArrayList<Held>()
    private val texts = ArrayList<HeldText>()
    private val lock = Any()

    /**
     * The palette everything currently registered was created under.
     *
     * Read by [register] to resolve a role, and used by nothing else. It is set
     * at startup from the stored theme and again by [retint]; the scene is
     * always built from this, so a surface that misses a retint is still
     * correct the next time it is built.
     */
    @Volatile
    var active: Horizon.Palette = Theme.DEFAULT.palette
        private set

    /** Establish the palette before anything is built. */
    fun begin(p: Horizon.Palette) {
        active = p
    }

    fun rgbOf(role: Role, p: Horizon.Palette): Int = when (role) {
        Role.ACCENT -> p.accent
        Role.ALT -> p.alt
        Role.WARN -> p.warn
        Role.TEXT -> p.text
    }

    /**
     * Which role [rgb] is, in [p], or null when it is a literal the palette does
     * not contain.
     *
     * A literal is not an error and not a warning: hit proxies, the boot
     * wordmark and the ruler overlay are all deliberately outside the theme.
     * They simply do not retint.
     */
    fun roleOf(rgb: Int, p: Horizon.Palette = active): Role? {
        val c = rgb and 0xFFFFFF
        return when (c) {
            p.accent and 0xFFFFFF -> Role.ACCENT
            p.alt and 0xFFFFFF -> Role.ALT
            p.warn and 0xFFFFFF -> Role.WARN
            p.text and 0xFFFFFF -> Role.TEXT
            else -> null
        }
    }

    /** Called by [Prims.material] for every material it makes. */
    fun register(m: KhronosUnlitMaterial, rgb: Int, alpha: Float) {
        val role = roleOf(rgb) ?: return
        synchronized(lock) { mats.add(Held(WeakReference(m), role, alpha)) }
    }

    /** Called by a text run, which carries its alpha inside the argb it was given. */
    fun registerText(t: Tintable, argb: Int) {
        val role = roleOf(argb) ?: return
        val a = ((argb ushr 24) and 0xFF) / 255f
        synchronized(lock) { texts.add(HeldText(WeakReference(t), role, a)) }
    }

    /**
     * Re-colour everything live, and make [to] the palette future builds use.
     *
     * Every write is guarded individually. A material whose entity was disposed
     * between the weak reference surviving and this call reaching it is a real
     * race on a frame loop that rebuilds the horizon on mesh traffic, and the
     * cost of losing that race must be one skipped mark rather than the scene.
     */
    fun retint(to: Horizon.Palette) {
        if (to == active) return
        var painted = 0
        var dropped = 0
        synchronized(lock) {
            val mi = mats.iterator()
            while (mi.hasNext()) {
                val h = mi.next()
                val m = h.mat.get()
                if (m == null) { mi.remove(); dropped++; continue }
                val rgb = rgbOf(h.role, to)
                val ok = runCatching {
                    m.setBaseColorFactor(
                        Vector4(
                            ((rgb shr 16) and 0xFF) / 255f,
                            ((rgb shr 8) and 0xFF) / 255f,
                            (rgb and 0xFF) / 255f,
                            h.alpha,
                        )
                    )
                }.isSuccess
                if (ok) painted++ else { mi.remove(); dropped++ }
            }
            val ti = texts.iterator()
            while (ti.hasNext()) {
                val h = ti.next()
                val t = h.target.get()
                if (t == null) { ti.remove(); dropped++; continue }
                val argb = (((h.alpha * 255f).toInt().coerceIn(0, 255)) shl 24) or
                    (rgbOf(h.role, to) and 0xFFFFFF)
                val ok = runCatching { t.setInk(argb) }.getOrDefault(false)
                if (ok) painted++ else { ti.remove(); dropped++ }
            }
        }
        active = to
        Log.i(TAG, "[ink] retint -> ${painted} repainted, ${dropped} stale")
    }

    /** How many live things a retint would touch. Diagnostics, and a test hook. */
    fun size(): Int = synchronized(lock) { mats.size + texts.size }

    /** Forget everything, for a teardown that is about to rebuild from scratch. */
    fun clear() {
        synchronized(lock) { mats.clear(); texts.clear() }
    }
}
