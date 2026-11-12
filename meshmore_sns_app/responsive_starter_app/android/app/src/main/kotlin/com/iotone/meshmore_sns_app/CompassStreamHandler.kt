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
 * The phone's heading, from the OS's own sensor fusion.
 *
 * `Sensor.TYPE_ROTATION_VECTOR` is the platform's fused orientation: the OS has
 * already combined the gyroscope, the accelerometer and the magnetometer, and
 * has already applied the factory magnetometer calibration. Everything the app
 * used to do by hand — tilt compensation, hard-iron removal, gyroscope
 * integration — is what this sensor exists to replace, and the hand-rolled
 * version was measurably wrong on a handset whose magnetometer reads 157 µT
 * where the Earth's field is about 50.
 *
 * Two things it reports and a raw sensor cannot:
 *
 *  * **heading**, in degrees clockwise from magnetic north, for the direction
 *    the *screen* faces. The rotation matrix is remapped for the display's own
 *    rotation first, so a landscape-locked app and a portrait one agree.
 *  * **accuracy**, from `onAccuracyChanged`. That is the OS telling us the
 *    magnetometer is uncalibrated, which is the state a reader has to be told
 *    about rather than shown a confident wrong arrow. It is sent on every
 *    reading so the Dart side can hold or drop the heading.
 *
 * The pitch/roll remaps below are Android's own sample code: with the screen
 * parallel to the ground the "forward" axis of a compass is the device's +y,
 * held up like a camera it is −z, and face down it is reversed. Without them the
 * azimuth is the angle of the wrong axis and the dial swings further than the
 * phone is turned or turns the wrong way — the reported fault.
 */
class CompassStreamHandler(private val context: Context) :
    EventChannel.StreamHandler, SensorEventListener {

    private val sensors =
        context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private val rotationSensor: Sensor? =
        sensors.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)

    private var events: EventChannel.EventSink? = null
    private var accuracy = SensorManager.SENSOR_STATUS_UNRELIABLE

    private val rotationMatrix = FloatArray(9)
    private val adjusted = FloatArray(9)
    private val orientation = FloatArray(3)
    private var lastEmit = 0L

    /** Between readings: a dial redrawn 60 times a second from a noisy sensor
     *  shivers. 50 Hz keeps a turn smooth and costs nothing. */
    private val minIntervalMs = 20L

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
        events = sink
        val sensor = rotationSensor
        if (sensor == null) {
            // No fused sensor: say so once and stay quiet. The Dart side falls
            // back to its own arithmetic and draws north-up until it can.
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
        if (event.values.size < 3) return
        val now = SystemClock.elapsedRealtime()
        if (now - lastEmit < minIntervalMs) return
        lastEmit = now

        SensorManager.getRotationMatrixFromVector(rotationMatrix, event.values)
        val displayRotation = displayRotation()

        // First remap: the axes as if the screen were parallel to the ground.
        var worldX: Int
        var worldY: Int
        when (displayRotation) {
            Surface.ROTATION_90 -> {
                worldX = SensorManager.AXIS_Y
                worldY = SensorManager.AXIS_MINUS_X
            }
            Surface.ROTATION_180 -> {
                worldX = SensorManager.AXIS_MINUS_X
                worldY = SensorManager.AXIS_MINUS_Y
            }
            Surface.ROTATION_270 -> {
                worldX = SensorManager.AXIS_MINUS_Y
                worldY = SensorManager.AXIS_X
            }
            else -> {
                worldX = SensorManager.AXIS_X
                worldY = SensorManager.AXIS_Y
            }
        }
        SensorManager.remapCoordinateSystem(
            rotationMatrix, worldX, worldY, adjusted
        )
        SensorManager.getOrientation(adjusted, orientation)

        if (orientation[1] < -Math.PI / 4) {
            // Screen parallel to the ground: the dial is read flat, so "the way
            // the phone points" is its own +y axis.
            when (displayRotation) {
                Surface.ROTATION_90 -> {
                    worldX = SensorManager.AXIS_Z
                    worldY = SensorManager.AXIS_MINUS_X
                }
                Surface.ROTATION_180 -> {
                    worldX = SensorManager.AXIS_MINUS_X
                    worldY = SensorManager.AXIS_MINUS_Z
                }
                Surface.ROTATION_270 -> {
                    worldX = SensorManager.AXIS_MINUS_Z
                    worldY = SensorManager.AXIS_X
                }
                else -> {
                    worldX = SensorManager.AXIS_X
                    worldY = SensorManager.AXIS_Z
                }
            }
        } else if (orientation[1] > Math.PI / 4) {
            // Upside down and facing away.
            when (displayRotation) {
                Surface.ROTATION_90 -> {
                    worldX = SensorManager.AXIS_MINUS_Z
                    worldY = SensorManager.AXIS_MINUS_X
                }
                Surface.ROTATION_180 -> {
                    worldX = SensorManager.AXIS_MINUS_X
                    worldY = SensorManager.AXIS_Z
                }
                Surface.ROTATION_270 -> {
                    worldX = SensorManager.AXIS_Z
                    worldY = SensorManager.AXIS_X
                }
                else -> {
                    worldX = SensorManager.AXIS_X
                    worldY = SensorManager.AXIS_MINUS_Z
                }
            }
        } else if (Math.abs(orientation[2]) > Math.PI / 2) {
            // Face down: the screen's forward axis is reversed.
            when (displayRotation) {
                Surface.ROTATION_90 -> {
                    worldX = SensorManager.AXIS_MINUS_Y
                    worldY = SensorManager.AXIS_MINUS_X
                }
                Surface.ROTATION_180 -> {
                    worldX = SensorManager.AXIS_MINUS_X
                    worldY = SensorManager.AXIS_Y
                }
                Surface.ROTATION_270 -> {
                    worldX = SensorManager.AXIS_Y
                    worldY = SensorManager.AXIS_X
                }
                else -> {
                    worldX = SensorManager.AXIS_X
                    worldY = SensorManager.AXIS_MINUS_Y
                }
            }
        }

        SensorManager.remapCoordinateSystem(
            rotationMatrix, worldX, worldY, adjusted
        )
        SensorManager.getOrientation(adjusted, orientation)

        var heading = Math.toDegrees(orientation[0].toDouble())
        if (heading < 0) heading += 360.0
        sink.success(
            mapOf(
                "heading" to heading,
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
