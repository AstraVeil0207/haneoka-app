package org.haneoka.haneoka

import android.app.Activity
import android.content.Context
import android.media.AudioAttributes
import android.os.Build
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import android.view.HapticFeedbackConstants
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Device recipes are supplied by the host; the channel knows no note types. */
class HapticsChannel(context: Context, messenger: BinaryMessenger) {
    private val activity = context as? Activity
    private val resolver = context.applicationContext.contentResolver
    private val vibrator: Vibrator? = if (Build.VERSION.SDK_INT >= 31) {
        context.getSystemService(VibratorManager::class.java)?.defaultVibrator
    } else {
        @Suppress("DEPRECATION")
        context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
    }
    private val channel = MethodChannel(messenger, "org.haneoka/haptics")

    init {
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "supported" -> result.success(vibrator?.hasVibrator() == true)
                    "stop" -> { vibrator?.cancel(); result.success(null) }
                    "emit" -> {
                        val recipe = call.arguments as? Map<*, *>
                        if (recipe == null) {
                            result.error("haptic-recipe", "Missing haptic recipe", null)
                        } else {
                            emit(recipe)
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                result.error("haptic-device", error.message, null)
            }
        }
    }

    private fun emit(recipe: Map<*, *>) {
        val device = vibrator ?: return
        if (!device.hasVibrator()) return
        @Suppress("DEPRECATION")
        if (Settings.System.getInt(resolver, Settings.System.HAPTIC_FEEDBACK_ENABLED, 1) == 0) return
        val mode = (recipe["_androidPlayType"] as? Number)?.toInt() ?: 0
        val effect = (recipe["_androidEffect"] as? Number)?.toInt() ?: 0
        val duration = ((recipe["_androidDurationMs"] as? Number)?.toLong() ?: 20L).coerceAtLeast(1L)
        val amplitude = ((recipe["_androidAmplitude"] as? Number)?.toDouble() ?: 1.0).coerceIn(0.0, 1.0)
        when (mode) {
            // Formal HapticPlayer routes these through its legacy type table.
            1, 2 -> emitLegacy(effect, amplitude)
            3 -> oneShot(duration, amplitude)
            4 -> {
                if (Build.VERSION.SDK_INT < 30 || !device.arePrimitivesSupported(effect).all { it }) return
                val scale = ((recipe["_androidScale"] as? Number)?.toFloat() ?: 1f).coerceIn(0f, 1f)
                vibrate(VibrationEffect.startComposition().addPrimitive(effect, scale).compose())
            }
        }
    }

    private fun emitLegacy(type: Int, amplitude: Double) {
        if (type <= 0) return
        if (type < 10) {
            val constant = when (type) {
                1 -> HapticFeedbackConstants.LONG_PRESS
                2 -> HapticFeedbackConstants.KEYBOARD_TAP
                3 -> HapticFeedbackConstants.VIRTUAL_KEY
                4 -> HapticFeedbackConstants.CLOCK_TICK
                5 -> HapticFeedbackConstants.CONTEXT_CLICK
                6 -> if (Build.VERSION.SDK_INT >= 27) HapticFeedbackConstants.KEYBOARD_PRESS else return
                7 -> if (Build.VERSION.SDK_INT >= 27) HapticFeedbackConstants.KEYBOARD_RELEASE else return
                8 -> if (Build.VERSION.SDK_INT >= 27) HapticFeedbackConstants.VIRTUAL_KEY_RELEASE else return
                9 -> if (Build.VERSION.SDK_INT >= 27) HapticFeedbackConstants.TEXT_HANDLE_MOVE else return
                else -> return
            }
            activity?.window?.decorView?.performHapticFeedback(constant)
            return
        }
        val predefined = when (type) {
            10 -> VibrationEffect.EFFECT_CLICK
            11 -> VibrationEffect.EFFECT_DOUBLE_CLICK
            12 -> VibrationEffect.EFFECT_TICK
            13 -> VibrationEffect.EFFECT_HEAVY_CLICK
            else -> null
        }
        val fallbackDuration = when (type) {
            11, 13 -> 30L
            12 -> 10L
            else -> 20L
        }
        val device = vibrator ?: return
        if (predefined != null && Build.VERSION.SDK_INT >= 29 &&
            (Build.VERSION.SDK_INT < 30 ||
                device.areEffectsSupported(predefined).firstOrNull() != Vibrator.VIBRATION_EFFECT_SUPPORT_NO)) {
            vibrate(VibrationEffect.createPredefined(predefined))
        } else {
            oneShot(fallbackDuration, amplitude)
        }
    }

    private fun oneShot(duration: Long, amplitude: Double) {
        val device = vibrator ?: return
        if (Build.VERSION.SDK_INT >= 26) {
            val strength = if (device.hasAmplitudeControl()) (amplitude * 255).toInt().coerceIn(1, 255) else 255
            vibrate(VibrationEffect.createOneShot(duration, strength))
        } else {
            @Suppress("DEPRECATION")
            device.vibrate(duration)
        }
    }

    private fun vibrate(effect: VibrationEffect) {
        val device = vibrator ?: return
        if (Build.VERSION.SDK_INT >= 33) {
            device.vibrate(effect, VibrationAttributes.createForUsage(VibrationAttributes.USAGE_TOUCH))
        } else {
            @Suppress("DEPRECATION")
            device.vibrate(effect, AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION).build())
        }
    }

    fun stop() { vibrator?.cancel() }
    fun dispose() { stop(); channel.setMethodCallHandler(null) }
}
