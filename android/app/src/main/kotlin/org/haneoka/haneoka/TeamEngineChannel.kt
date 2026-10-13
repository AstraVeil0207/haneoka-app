package org.haneoka.haneoka

import android.content.Context
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Separate engines give the solver its own Dart heap and garbage collector. */
class TeamEngineChannel(private val context: Context, messenger: BinaryMessenger) {
    private val engines = mutableMapOf<String, FlutterEngine>()
    private val channel = MethodChannel(messenger, "org.haneoka/team_engine")
    init {
        channel.setMethodCallHandler { call, result ->
            val key = call.argument<String>("key")
            if (key.isNullOrEmpty()) { result.error("engine-key", "Missing engine key", null) }
            else when (call.method) {
                "start" -> {
                    if (!engines.containsKey(key)) {
                        try {
                            val loader = FlutterInjector.instance().flutterLoader()
                            loader.ensureInitializationComplete(context, null)
                            val engine = FlutterEngine(context, null, false)
                            engines[key] = engine
                            engine.dartExecutor.executeDartEntrypoint(
                                DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "main"),
                                listOf("--haneoka-team-engine=$key"))
                        } catch (error: Exception) {
                            engines.remove(key)?.destroy()
                            result.error("engine-start", error.message, null)
                            return@setMethodCallHandler
                        }
                    }
                    result.success(null)
                }
                "dispose" -> { engines.remove(key)?.destroy(); result.success(null) }
                else -> result.notImplemented()
            }
        }
    }
    fun dispose() {
        channel.setMethodCallHandler(null)
        engines.values.forEach { it.destroy() }
        engines.clear()
    }
}
