package org.haneoka.haneoka

import android.content.Intent
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : AudioServiceActivity() {
    private lateinit var saves: SaveChannel
    private lateinit var teamEngine: TeamEngineChannel
    private lateinit var haptics: HapticsChannel

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        haptics = HapticsChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        saves = SaveChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        teamEngine = TeamEngineChannel(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    @Deprecated("Activity results from the system folder picker")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (!saves.onActivityResult(requestCode, resultCode, data)) super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onPause() {
        if (::haptics.isInitialized) haptics.stop()
        super.onPause()
    }

    override fun onDestroy() {
        if (::haptics.isInitialized) haptics.dispose()
        if (::saves.isInitialized) saves.dispose()
        if (::teamEngine.isInitialized) teamEngine.dispose()
        super.onDestroy()
    }
}
