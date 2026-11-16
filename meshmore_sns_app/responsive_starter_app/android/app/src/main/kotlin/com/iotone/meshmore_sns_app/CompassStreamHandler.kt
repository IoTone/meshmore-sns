package com.iotone.meshmore_sns_app

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.hardware.display.DisplayManager
import android.os.SystemClock
import android.view.Display
import android.view.Surface
import io.flutter.plugin.common.EventChannel

/**
 * The phone's orientation, from the OS's own sensor fusion.
 *
 * `Sensor.TYPE_ROTATION_VECTOR` is the platform's fused attitude: the gyroscope,
 * the accelerometer and the magnetometer already combined, with the factory
 * magnetometer calibration already applied. Getting *that* is the hard part and
 * it is what this channel is for.
 *
 * What it deliberately does **not** do is turn it into a heading. Android's
 * `getOrientation` azimuth is the rotation about one chosen axis, and which axis
 * is right depends on how the phone is held: with the screen flat it is the
 * phone's own top, held up like a camera it is the direction you face, and in
 * between the two the sample code's pitch-based axis swaps make the reading
 * jump. Doing that on the Dart side means it can be unit-tested against known
 * attitudes, which is how the previous three attempts at this were found to be
 * wrong rather than merely unlucky.
 *
 * So the payload is the raw quaternion plus the two things only the platform
 * knows: the display's rotation and the sensor's accuracy.
 */
class CompassStreamHandler(private val context: Context) :
    EventChannel.StreamHandler, SensorEventListener {

    private val sensors =
        context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private val rotationSensor: Sensor? =
        sensors.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)

    private var events: EventChannel.EventSink? = null
    private var accuracy = SensorManager.SENSOR_STATUS_UNRELIABLE
    private var lastEmit = 0L

    /// A dial redrawn 60 times a second from a noisy sensor shivers; 50 Hz keeps
    /// a turn smooth and costs nothing.
    private val minIntervalMs = 20L

    /// `getRotationMatrixFromVector` throws on some Samsungs when the vector is
    /// longer than four values, and the fourth is all this needs.
    private val quaternion = FloatArray(4)

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
        events = sink
        val sensor = rotationSensor
        if (sensor == null) {
            // No fused sensor: say so once. The Dart side falls back to its own
            // arithmetic and draws north-up until it can do better.
            sink.error("no_sensor", "no rotation vector sensor", null)
            return
        }
        sensors.registerListener(this, sensor, SensorManager.SENSOR_DELAY_GAME)
    }

    override fun onCancel(arguments: Any?) {
        sensors.unregisterListener(this)
        events = null
    }

    override fun onAccuracyChanged(sensor: Sensor?, newAccuracy: Int) {
        accuracy = newAccuracy
    }

    override fun onSensorChanged(event: SensorEvent) {
        val sink = events ?: return
        if (event.values.isEmpty()) return
        val now = SystemClock.elapsedRealtime()
        if (now - lastEmit < minIntervalMs) return
        lastEmit = now

        val n = minOf(4, event.values.size)
        for (i in 0 until n) quaternion[i] = event.values[i]
        if (n < 4) quaternion[3] = 1f

        sink.success(
            mapOf(
                "qx" to quaternion[0].toDouble(),
                "qy" to quaternion[1].toDouble(),
                "qz" to quaternion[2].toDouble(),
                "qw" to quaternion[3].toDouble(),
                "rotation" to displayRotation(),
                "accuracy" to accuracyDegrees(accuracy),
            )
        )
    }

    private fun displayRotation(): Int {
        val manager =
            context.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
        return manager.getDisplay(Display.DEFAULT_DISPLAY)?.rotation
            ?: Surface.ROTATION_0
    }

    /** The OS accuracy figures, in degrees, as Android itself reports them. */
    private fun accuracyDegrees(status: Int): Int = when (status) {
        SensorManager.SENSOR_STATUS_ACCURACY_HIGH -> 15
        SensorManager.SENSOR_STATUS_ACCURACY_MEDIUM -> 30
        SensorManager.SENSOR_STATUS_ACCURACY_LOW -> 45
        else -> -1
    }
}
