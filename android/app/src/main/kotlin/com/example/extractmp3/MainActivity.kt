package com.example.extractmp3

import io.flutter.embedding.android.FlutterActivity

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
