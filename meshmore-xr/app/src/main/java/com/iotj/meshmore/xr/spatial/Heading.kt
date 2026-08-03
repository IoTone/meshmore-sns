// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

import android.content.Context
import android.hardware.GeomagneticField
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.util.Log
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeoutOrNull
import kotlin.coroutines.resume

/**
 * WHICH WAY IS NORTH — the thing the whole ring is measured from, and which the
 * app has been assuming since P0.
 *
 * `Stage.Origin.place` says it plainly: "bearing is measured from the launch
 * facing." Every node, though, is placed at a bearing `MeshNodes` computes from
 * real latitudes and longitudes — which is a bearing from TRUE NORTH. The two
 * only agree if the wearer happened to be facing north when the app started.
 *
 * So this is not a mislabelled compass tick. Launch facing east and the entire
 * mesh is drawn 90 degrees off: the ring says a repeater is north of you when
 * it is east of you, in an app whose first paradigm rule is that bearing is the
 * primary index. Reported 2026-08-02 by holding a real compass up to it.
 *
 * TRUE, NOT MAGNETIC. The two differ by declination, which is about 15 degrees
 * east in Seattle — larger than the angular width of most of what the ring
 * draws, so ignoring it would swap one wrong answer for a slightly better wrong
 * answer. GeomagneticField gives the correction from a position and a date.
 *
 * THE SIGN IS NOT SETTLED. Android's azimuth convention is written for a phone
 * held in a phone's frame, and this is a headset; four separate sign errors in
 * this project have come from deriving a convention in a comment instead of
 * looking at the result. So this logs what it measured, in degrees, and the
 * caller applies it only when [TRUST] says the reading has been checked against
 * a real compass. Until then the app keeps its old behaviour and says so.
 */
object Heading {

    private const val TAG = "MeshmoreXR"

    /**
     * Whether to actually APPLY the measured heading to the origin.
     *
     * False until someone has stood with a compass and confirmed the logged
     * figure matches, because a confidently wrong north is worse than an
     * honestly relative one — it looks authoritative. Flip it once the log and
     * the compass agree, and the ring becomes north-referenced.
     */
    const val TRUST = false

    /** What a reading is worth. */
    data class Fix(
        /** Radians clockwise from true north to the device's forward axis. */
        val trueRad: Float,
        /** The raw magnetic azimuth, before declination. */
        val magneticRad: Float,
        /** Declination applied, in degrees east. 0 when no position was known. */
        val declinationDeg: Float,
        /** Sensor accuracy, as reported. Low values mean "wave it in a figure 8". */
        val accuracy: Int,
    )

    /**
     * One reading, or null if the device cannot give one.
     *
     * Waits briefly for a sample: the rotation vector is fused and takes a few
     * frames to settle after registration, and a heading taken from the first
     * event is routinely tens of degrees out.
     */
    suspend fun read(context: Context, lat: Double?, lon: Double?, altM: Double?): Fix? {
        val sm = context.getSystemService(Context.SENSOR_SERVICE) as? SensorManager
        if (sm == null) {
            Log.w(TAG, "[heading] no SensorManager")
            return null
        }
        // ROTATION_VECTOR is magnetometer-fused. GAME_ROTATION_VECTOR is the
        // same shape and deliberately has NO magnetic reference, so it would
        // return a heading that drifts from an arbitrary zero — exactly the
        // problem we are trying to fix, wearing a more authoritative name.
        val sensor = sm.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
        if (sensor == null) {
            // WHAT THE DEVICE ACTUALLY HAS. Absence of the fused vector does
            // not by itself mean there is no magnetometer — a raw field plus
            // gravity can be fused by hand — and "no compass" is too important
            // a conclusion to reach from one missing constant.
            val have = runCatching {
                sm.getSensorList(Sensor.TYPE_ALL).joinToString(", ") { "${it.type}:${it.name}" }
            }.getOrDefault("<unreadable>")
            Log.w(TAG, "[heading] no TYPE_ROTATION_VECTOR. magnetometer=" +
                (sm.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD) != null) +
                " accelerometer=" + (sm.getDefaultSensor(Sensor.TYPE_ACCELEROMETER) != null))
            Log.w(TAG, "[heading] sensors: $have")
            return null
        }
        val magnetic = withTimeoutOrNull(SETTLE_MS) { sample(sm, sensor) }
        if (magnetic == null) {
            Log.w(TAG, "[heading] no sample in ${SETTLE_MS}ms")
            return null
        }
        val (azimuth, accuracy) = magnetic
        val decl = if (lat != null && lon != null) {
            GeomagneticField(
                lat.toFloat(), lon.toFloat(), (altM ?: 0.0).toFloat(),
                System.currentTimeMillis(),
            ).declination
        } else {
            Log.w(TAG, "[heading] no position yet — declination NOT applied, " +
                "reading is magnetic north")
            0f
        }
        val trueRad = azimuth + Math.toRadians(decl.toDouble()).toFloat()
        Log.i(TAG, ("[heading] magnetic=%.1f° declination=%.1f°E true=%.1f° " +
            "accuracy=%d trust=%s")
            .format(
                Math.toDegrees(azimuth.toDouble()), decl,
                Math.toDegrees(trueRad.toDouble()), accuracy, TRUST,
            ))
        return Fix(trueRad, azimuth, decl, accuracy)
    }

    /** Take samples until the fused vector stops moving, or the timeout wins. */
    private suspend fun sample(sm: SensorManager, sensor: Sensor): Pair<Float, Int>? =
        suspendCancellableCoroutine { cont ->
            val r = FloatArray(9)
            val o = FloatArray(3)
            var acc = SensorManager.SENSOR_STATUS_UNRELIABLE
            var seen = 0
            val l = object : SensorEventListener {
                override fun onSensorChanged(e: SensorEvent) {
                    seen++
                    // Discard the first few: the fusion has not converged and an
                    // early sample is routinely far out.
                    if (seen < DISCARD) return
                    SensorManager.getRotationMatrixFromVector(r, e.values)
                    SensorManager.getOrientation(r, o)
                    runCatching { sm.unregisterListener(this) }
                    if (cont.isActive) cont.resume(o[0] to acc)
                }

                override fun onAccuracyChanged(s: Sensor?, a: Int) { acc = a }
            }
            sm.registerListener(l, sensor, SensorManager.SENSOR_DELAY_GAME)
            cont.invokeOnCancellation { runCatching { sm.unregisterListener(l) } }
        }

    /** How long to wait for a settled sample before giving up. */
    private const val SETTLE_MS = 1500L
    /** Samples thrown away while the fusion converges. */
    private const val DISCARD = 12
}
