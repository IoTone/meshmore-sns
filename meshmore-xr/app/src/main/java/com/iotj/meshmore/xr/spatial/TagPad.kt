// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

import android.content.Context
import android.graphics.Color
import android.text.InputType
import android.util.Log
import android.view.Gravity
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import androidx.xr.runtime.Session
import androidx.xr.runtime.math.FloatSize2d
import androidx.xr.runtime.math.IntSize2d
import androidx.xr.runtime.math.Pose
import androidx.xr.runtime.math.Quaternion
import androidx.xr.runtime.math.Vector3
import androidx.xr.scenecore.Entity
import androidx.xr.scenecore.PanelEntity
import androidx.xr.scenecore.Space
import androidx.xr.scenecore.scene

/**
 * A FIELD YOU CAN TYPE A CHANNEL TAG INTO, BECAUSE SAYING ONE DOES NOT WORK.
 *
 * Dictation was the input this app chose for everything spoken, on the good
 * argument that a headset has no keyboard and should not grow one. For a
 * MESSAGE that is right: speech recognition mishears, and a misheard message is
 * a slightly wrong sentence that a human reader repairs.
 *
 * A channel tag is not a sentence. Its key is SHA-256 over the exact bytes, so
 * one wrong character is not a typo, it is a different channel with nobody in
 * it. Four attempts on the glasses on 2026-08-22, target `#soaktest`:
 *
 *     "Soak test"      -> #Soak-test     capitalised, and split into two words
 *     "Soak test"      -> #Silk-test     misheard outright
 *     "#Soakte s t"    -> #Soakte-s-t
 *     "S o a k t e s t"-> #S-o-a-k-t-e-s-t   spelling it out is worse
 *
 * Zero successes, and no amount of tuning fixes it: sentence case, word breaks
 * and homophones are what a dictation engine is FOR. So the tag gets a
 * keyboard. The system IME exists on this device and the design note that said
 * otherwise was written before anybody checked.
 *
 * ## What this field turns off, and why each one matters
 *
 * Every convenience an Android text field offers is a hazard here:
 *
 *  - **Auto-capitalisation** would produce `#Soak` for a wearer typing `#soak`,
 *    which is a different channel that looks identical on the row.
 *  - **Suggestions and autocorrect** would rewrite an unfamiliar tag into a
 *    familiar word — exactly what dictation did.
 *  - **Multi-line** would let a newline into the hashed bytes.
 *
 * So the field is a single line of monospace with suggestions off, capitalised
 * never, and a DONE key that hands the literal text back.
 */
class TagPad(
    private val session: Session,
    private val theme: Horizon.Palette,
    private val context: Context,
) {

    private var panel: PanelEntity? = null
    private var field: EditText? = null
    private val entities = mutableListOf<Entity>()

    var open: Boolean = false
        private set

    /** Raised with the literal text when the wearer presses DONE. */
    var onDone: ((String) -> Unit)? = null

    /** Raised when the wearer leaves without entering anything. */
    var onCancel: (() -> Unit)? = null

    /**
     * BUILT AT SETUP LIKE EVERY OTHER PANEL, and hidden until wanted.
     *
     * A panel created after the scene is up does not attach — measured on the
     * emulator, and the reason every surface in this app is born during setup.
     */
    fun build(root: Entity = session.scene.activitySpace) {
        clear()
        val tv = EditText(context).apply {
            setTextColor(theme.text or 0xFF000000.toInt())
            setBackgroundColor(Color.argb(220, 8, 8, 12))
            setHintTextColor(argb(theme.alt, 0.6f))
            hint = "#tag"
            textSize = 34f
            typeface = android.graphics.Typeface.MONOSPACE
            gravity = Gravity.CENTER
            setPadding(28, 20, 28, 20)
            isSingleLine = true
            // THE WHOLE POINT. See the class note: every one of these flags is
            // off because leaving it on changes bytes the wearer did not type.
            inputType = InputType.TYPE_CLASS_TEXT or
                InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS or
                InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD
            imeOptions = EditorInfo.IME_ACTION_DONE
            setOnEditorActionListener { _, action, _ ->
                if (action == EditorInfo.IME_ACTION_DONE) {
                    val typed = text?.toString().orEmpty()
                    Log.i(TAG, "[tagpad] done '$typed'")
                    hide()
                    onDone?.invoke(typed)
                    true
                } else {
                    false
                }
            }
        }
        field = tv
        val p = PanelEntity.create(
            session, tv, FloatSize2d(W_PX * MPP, H_PX * MPP), "tagpad",
            Pose(Vector3(0f, 0f, 0f)),
        )
        p.sizeInPixels = IntSize2d(W_PX, H_PX)
        p.parent = root
        p.setEnabled(false)
        panel = p
        entities += p
        Log.i(TAG, "[tagpad] built ${W_PX}x${H_PX}px")
    }

    /**
     * Put it in front of the wearer and raise the keyboard.
     *
     * Closer than a bay — this is a thing you are working ON rather than
     * reading, and the system keyboard will want room under it.
     */
    fun showAt(head: Vector3, yawRad: Float, prefill: String = "#") {
        val p = panel ?: return
        val fx = kotlin.math.sin(yawRad)
        val fz = -kotlin.math.cos(yawRad)
        val at = Vector3(head.x + fx * DIST, head.y + DROP, head.z + fz * DIST)
        runCatching {
            p.setEnabled(true)
            p.setPose(
                Pose(
                    at,
                    Quaternion.fromEulerAngles(
                        0f,
                        Math.toDegrees(kotlin.math.atan2(-fx.toDouble(), -fz.toDouble()))
                            .toFloat(),
                        0f,
                    ),
                ),
                Space.ACTIVITY,
            )
        }
        open = true
        field?.let { f ->
            f.setText(prefill)
            f.setSelection(f.text?.length ?: 0)
            f.requestFocus()
            // THE KEYBOARD DOES NOT COME UP ON ITS OWN for a view that was
            // never touched. Asking explicitly is what makes this a keyboard
            // rather than a box you cannot type into.
            runCatching {
                context.getSystemService(InputMethodManager::class.java)
                    ?.showSoftInput(f, InputMethodManager.SHOW_IMPLICIT)
            }
        }
        Log.i(TAG, "[tagpad] open")
    }

    fun hide() {
        if (!open) return
        open = false
        field?.let { f ->
            runCatching {
                context.getSystemService(InputMethodManager::class.java)
                    ?.hideSoftInputFromWindow(f.windowToken, 0)
            }
            f.clearFocus()
        }
        runCatching { panel?.setEnabled(false) }
        Log.i(TAG, "[tagpad] closed")
    }

    fun cancel() {
        if (!open) return
        hide()
        onCancel?.invoke()
    }

    fun clear() {
        val doomed = entities.toList()
        entities.clear()
        panel = null
        field = null
        open = false
        doomed.forEach { runCatching { it.parent = null } }
        doomed.forEach { runCatching { it.dispose() } }
    }

    private fun argb(rgb: Int, a: Float) =
        ((a * 255).toInt() shl 24) or (rgb and 0xFFFFFF)

    private companion object {
        const val TAG = "MeshmoreXR"

        /** Wide enough for a long tag at a size that can be proof-read. */
        const val W_PX = 620
        const val H_PX = 110

        /** Seed only — the runtime reports what it actually chose. */
        const val MPP = 0.00039215686f

        /** Nearer than a bay: this is worked on, not read. */
        const val DIST = 0.85f
        const val DROP = -0.12f
    }
}
