// android/app/src/main/kotlin/com/example/extractmp3/MainActivity.kt
package <your.package>

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL_EXTRACTOR = "audio_extractor"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_EXTRACTOR)
            .setMethodCallHandler { call, result ->
                AudioExtractorNative.handle(
                    call,
                    result,
                    applicationContext.contentResolver,
                    cacheDir,
                    getExternalFilesDir(null) ?: filesDir
                )
            }
    }
}
