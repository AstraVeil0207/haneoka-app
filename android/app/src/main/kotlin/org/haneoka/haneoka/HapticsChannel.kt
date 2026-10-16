package org.haneoka.haneoka

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Device recipes are supplied by the host; the channel knows no note types. */
class HapticsChannel(context: Context, messenger: BinaryMessenger) {
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
        val mode = (recipe["_androidPlayType"] as? Number)?.toInt() ?: 0
        if (mode == 0) return
        val effect = (recipe["_androidEffect"] as? Number)?.toInt() ?: 0
        val duration = ((recipe["_androidDurationMs"] as? Number)?.toLong() ?: 20L).coerceIn(1L, 1000L)
        val amplitude = ((recipe["_androidAmplitude"] as? Number)?.toDouble() ?: 1.0).coerceIn(0.0, 1.0)
        if (amplitude == 0.0) return
        if (Build.VERSION.SDK_INT >= 29 && mode == 1 && effect in 0..5) {
            device.vibrate(VibrationEffect.createPredefined(effect))
        } else if (Build.VERSION.SDK_INT >= 26) {
            device.vibrate(VibrationEffect.createOneShot(duration, (amplitude * 255).toInt().coerceIn(1, 255)))
        } else {
            @Suppress("DEPRECATION")
            device.vibrate(duration)
        }
    }

    fun stop() { vibrator?.cancel() }
    fun dispose() { stop(); channel.setMethodCallHandler(null) }
}
