// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

import androidx.xr.runtime.Session
import androidx.xr.runtime.math.BoundingBox
import androidx.xr.runtime.math.Vector3
import androidx.xr.runtime.math.Vector4
import androidx.xr.scenecore.AlphaMode
import androidx.xr.scenecore.CustomMesh
import androidx.xr.scenecore.KhronosUnlitMaterial
import androidx.xr.scenecore.MeshSubsetTopology
import androidx.xr.scenecore.VertexAttribute
import androidx.xr.scenecore.VertexAttributeType
import androidx.xr.scenecore.VertexLayout
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * The AiRspace volumetric primitives, as REAL GEOMETRY.
 *
 * P1's whole point is that this is not a flat app floating in space. There are
 * no SpatialPanels here and no Compose: every mark is a CustomMesh placed in the
 * world, which is the only way the symbology gets actual volume.
 *
 * SHADING WITHOUT A SHADER. SceneCore beta01 offers KhronosUnlitMaterial, which
 * is deliberately flat -- and an unshaded sphere renders as a flat coloured
 * circle, exactly the bug the Three.js prototype hit. There is no custom shader
 * hook, so lighting is BAKED into vertex colours at build time: per-facet
 * lambert against a fixed key direction, multiplied by the theme colour through
 * baseColorFactor (glTF unlit: baseColor = factor x COLOR_0).
 *
 * Baking has a second, wanted consequence. Bakeable shading is per-FACET, so the
 * geometry must be faceted -- hard edges, visible polygons, no smoothing. That
 * is the Wipeout XL look: low-poly solids with crisp facets and neon, not the
 * soft PBR blobs a mobile toolkit reaches for. The constraint and the aesthetic
 * point the same way.
 *
 * What cannot be baked is the view-dependent fresnel rim, so silhouettes are
 * carried by geometry instead: torus rings around motes, extruded edges on bars.
 */
object Prims {

    /** POSITION float3 + COLOR ubyte4 = 16 bytes per vertex. */
    private val layout: VertexLayout by lazy {
        VertexLayout.Builder()
            .addAttribute(VertexAttribute.POSITION, VertexAttributeType.FLOAT3)
            .addAttribute(VertexAttribute.COLOR, VertexAttributeType.UBYTE4_NORM)
            .build()
    }

    private const val STRIDE = 16

    /** Fixed key direction — symbology must not flicker as the head turns. */
    private val KEY = floatArrayOf(0.35f, 0.75f, 0.55f).also {
        val l = sqrt(it[0] * it[0] + it[1] * it[1] + it[2] * it[2])
        it[0] /= l; it[1] /= l; it[2] /= l
    }

    /** A soup of flat-shaded triangles: three unshared vertices per face. */
    class Facets {
        val pos = ArrayList<Float>()
        val shade = ArrayList<Float>()
        val vertexCount get() = shade.size

        fun tri(
            ax: Float, ay: Float, az: Float,
            bx: Float, by: Float, bz: Float,
            cx: Float, cy: Float, cz: Float,
        ) {
            val ux = bx - ax; val uy = by - ay; val uz = bz - az
            val vx = cx - ax; val vy = cy - ay; val vz = cz - az
            var nx = uy * vz - uz * vy
            var ny = uz * vx - ux * vz
            var nz = ux * vy - uy * vx
            val l = sqrt(nx * nx + ny * ny + nz * nz).let { if (it > 1e-9f) it else 1f }
            nx /= l; ny /= l; nz /= l
            val lam = (nx * KEY[0] + ny * KEY[1] + nz * KEY[2]).coerceAtLeast(0f)
            // AMBIENT FLOOR: a facet turned away from the key must still read as
            // part of the object. Pure lambert makes half the volume disappear on
            // an additive display, where black is simply transparent.
            val s = 0.42f + 0.58f * lam
            pos.add(ax); pos.add(ay); pos.add(az); shade.add(s)
            pos.add(bx); pos.add(by); pos.add(bz); shade.add(s)
            pos.add(cx); pos.add(cy); pos.add(cz); shade.add(s)
        }

        fun quad(
            ax: Float, ay: Float, az: Float, bx: Float, by: Float, bz: Float,
            cx: Float, cy: Float, cz: Float, dx: Float, dy: Float, dz: Float,
        ) {
            tri(ax, ay, az, bx, by, bz, cx, cy, cz)
            tri(ax, ay, az, cx, cy, cz, dx, dy, dz)
        }

        fun addTranslated(o: Facets, tx: Float, ty: Float, tz: Float) {
            for (i in 0 until o.vertexCount) {
                pos.add(o.pos[i * 3] + tx)
                pos.add(o.pos[i * 3 + 1] + ty)
                pos.add(o.pos[i * 3 + 2] + tz)
                shade.add(o.shade[i])
            }
        }
    }

    fun build(session: Session, f: Facets): CustomMesh {
        val n = f.vertexCount
        val vb = ByteBuffer.allocateDirect(n * STRIDE).order(ByteOrder.nativeOrder())
        for (i in 0 until n) {
            vb.putFloat(f.pos[i * 3]); vb.putFloat(f.pos[i * 3 + 1]); vb.putFloat(f.pos[i * 3 + 2])
            val c = (f.shade[i] * 255f).toInt().coerceIn(0, 255).toByte()
            vb.put(c); vb.put(c); vb.put(c); vb.put(255.toByte())
        }
        vb.rewind()
        // Facet soup is already in draw order, so indices are simply 0..n-1.
        val ib = ByteBuffer.allocateDirect(n * 4).order(ByteOrder.nativeOrder())
        for (i in 0 until n) ib.putInt(i)
        ib.rewind()

        // BOUNDS ARE NOT OPTIONAL. A CustomMesh built without them carries an
        // empty box, and an empty box means the mesh is frustum-culled on every
        // frame: it builds without error, reports enabled, and is never drawn.
        // That failure has no log line anywhere -- the only symptom is nothing
        // on the glasses.
        var lo = Vector3(Float.MAX_VALUE, Float.MAX_VALUE, Float.MAX_VALUE)
        var hi = Vector3(-Float.MAX_VALUE, -Float.MAX_VALUE, -Float.MAX_VALUE)
        for (i in 0 until n) {
            val x = f.pos[i * 3]; val y = f.pos[i * 3 + 1]; val z = f.pos[i * 3 + 2]
            lo = Vector3(min(lo.x, x), min(lo.y, y), min(lo.z, z))
            hi = Vector3(max(hi.x, x), max(hi.y, y), max(hi.z, z))
        }

        return CustomMesh.BuilderFromMeshData(session, layout)
            .addVertexData(vb)
            .setIndexData(ib)
            .addSubset(MeshSubsetTopology.TRIANGLES, 0, n)
            .setBounds(BoundingBox.fromMinMax(lo, hi))
            .build()
    }

    suspend fun material(session: Session, rgb: Int, alpha: Float = 1f): KhronosUnlitMaterial =
        KhronosUnlitMaterial.create(session, AlphaMode.BLEND).apply {
            setBaseColorFactor(
                Vector4(
                    ((rgb shr 16) and 0xFF) / 255f,
                    ((rgb shr 8) and 0xFF) / 255f,
                    (rgb and 0xFF) / 255f,
                    alpha,
                )
            )
        }

    // ---- the primitives ----------------------------------------------------

    /**
     * MOTE — a node. A faceted sphere: identical from every angle so it can
     * never foreshorten, and low-poly enough that the facets read as facets.
     */
    fun mote(r: Float, rings: Int = 7, seg: Int = 10): Facets {
        val f = Facets()
        fun px(i: Int, j: Int) = (r * sin(Math.PI * i / rings) * cos(2.0 * Math.PI * j / seg)).toFloat()
        fun py(i: Int) = (r * cos(Math.PI * i / rings)).toFloat()
        fun pz(i: Int, j: Int) = (r * sin(Math.PI * i / rings) * sin(2.0 * Math.PI * j / seg)).toFloat()
        for (i in 0 until rings) for (j in 0 until seg) {
            val ax = px(i, j); val ay = py(i); val az = pz(i, j)
            val bx = px(i + 1, j); val by = py(i + 1); val bz = pz(i + 1, j)
            val cx = px(i + 1, j + 1); val cy = py(i + 1); val cz = pz(i + 1, j + 1)
            val dx = px(i, j + 1); val dy = py(i); val dz = pz(i, j + 1)
            when (i) {
                0 -> f.tri(ax, ay, az, bx, by, bz, cx, cy, cz)
                rings - 1 -> f.tri(ax, ay, az, bx, by, bz, dx, dy, dz)
                else -> f.quad(ax, ay, az, bx, by, bz, cx, cy, cz, dx, dy, dz)
            }
        }
        return f
    }

    /**
     * HALO — a range ring. A real TORUS, never a flat annulus: an annulus is a
     * disc with a hole and collapses to a line at a grazing angle, which reads
     * as a rendering fault rather than as a ring.
     */
    fun halo(radius: Float, tube: Float, seg: Int = 48, sides: Int = 6): Facets {
        val f = Facets()
        fun px(i: Int, j: Int) =
            ((radius + tube * cos(2.0 * Math.PI * j / sides)) * cos(2.0 * Math.PI * i / seg)).toFloat()
        fun py(j: Int) = (tube * sin(2.0 * Math.PI * j / sides)).toFloat()
        fun pz(i: Int, j: Int) =
            ((radius + tube * cos(2.0 * Math.PI * j / sides)) * sin(2.0 * Math.PI * i / seg)).toFloat()
        for (i in 0 until seg) for (j in 0 until sides) {
            f.quad(
                px(i, j), py(j), pz(i, j),
                px(i + 1, j), py(j), pz(i + 1, j),
                px(i + 1, j + 1), py(j + 1), pz(i + 1, j + 1),
                px(i, j + 1), py(j + 1), pz(i, j + 1),
            )
        }
        return f
    }

    /** CARET — direction / elevation. A cone; a flat triangle vanishes edge-on. */
    fun caret(radius: Float, height: Float, seg: Int = 8): Facets {
        val f = Facets()
        for (j in 0 until seg) {
            val a = 2.0 * Math.PI * j / seg
            val b = 2.0 * Math.PI * (j + 1) / seg
            val ax = (radius * cos(a)).toFloat(); val az = (radius * sin(a)).toFloat()
            val bx = (radius * cos(b)).toFloat(); val bz = (radius * sin(b)).toFloat()
            f.tri(0f, height, 0f, ax, 0f, az, bx, 0f, bz)
            f.tri(0f, 0f, 0f, bx, 0f, bz, ax, 0f, az)
        }
        return f
    }

    /** BAR — one discrete segment. An extruded box, so it reads at an angle. */
    fun bar(w: Float, h: Float, d: Float): Facets {
        val f = Facets()
        val x = w / 2; val y = h / 2; val z = d / 2
        f.quad(-x, -y, z, x, -y, z, x, y, z, -x, y, z)
        f.quad(x, -y, -z, -x, -y, -z, -x, y, -z, x, y, -z)
        f.quad(x, -y, z, x, -y, -z, x, y, -z, x, y, z)
        f.quad(-x, -y, -z, -x, -y, z, -x, y, z, -x, y, -z)
        f.quad(-x, y, z, x, y, z, x, y, -z, -x, y, -z)
        f.quad(-x, -y, -z, x, -y, -z, x, -y, z, -x, -y, z)
        return f
    }

    /**
     * SPUR — a link. A square-section extruded tube between two points. Never a
     * line: GPU line width is ignored on most platforms, and anything under
     * ~1 cm is invisible in bright passthrough.
     */
    fun spur(
        ax: Float, ay: Float, az: Float,
        bx: Float, by: Float, bz: Float,
        r: Float,
    ): Facets {
        val f = Facets()
        var dx = bx - ax; var dy = by - ay; var dz = bz - az
        val len = sqrt(dx * dx + dy * dy + dz * dz).let { if (it > 1e-6f) it else 1f }
        dx /= len; dy /= len; dz /= len
        // any vector not parallel to d, to build the section frame
        val hx = if (kotlin.math.abs(dy) < 0.9f) 0f else 1f
        val hy = if (kotlin.math.abs(dy) < 0.9f) 1f else 0f
        var ux = hy * dz - 0f * dy
        var uy = 0f * dx - hx * dz
        var uz = hx * dy - hy * dx
        val ul = sqrt(ux * ux + uy * uy + uz * uz).let { if (it > 1e-6f) it else 1f }
        ux /= ul; uy /= ul; uz /= ul
        val vx = dy * uz - dz * uy
        val vy = dz * ux - dx * uz
        val vz = dx * uy - dy * ux

        fun corner(t: Float, s: Int): Triple<Float, Float, Float> {
            val cx = ax + (bx - ax) * t; val cy = ay + (by - ay) * t; val cz = az + (bz - az) * t
            val su = if (s == 0 || s == 3) -r else r
            val sv = if (s < 2) -r else r
            return Triple(cx + ux * su + vx * sv, cy + uy * su + vy * sv, cz + uz * su + vz * sv)
        }
        for (s in 0 until 4) {
            val n = (s + 1) % 4
            val (p0x, p0y, p0z) = corner(0f, s); val (p1x, p1y, p1z) = corner(0f, n)
            val (p2x, p2y, p2z) = corner(1f, n); val (p3x, p3y, p3z) = corner(1f, s)
            f.quad(p0x, p0y, p0z, p1x, p1y, p1z, p2x, p2y, p2z, p3x, p3y, p3z)
        }
        return f
    }
}
