package dev.sitesignal.app

import android.content.Intent
import android.media.Ringtone
import android.media.RingtoneManager
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var notificationSoundPreview: Ringtone? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dev.sitesignal.app/desktop",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "openNotificationSettings" -> {
                    val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                        putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                    }
                    startActivity(intent)
                    result.success(true)
                }
                "playSystemNotificationSound" -> {
                    try {
                        val soundUri = RingtoneManager.getDefaultUri(
                            RingtoneManager.TYPE_NOTIFICATION,
                        )
                        if (soundUri == null) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        val ringtone = RingtoneManager.getRingtone(applicationContext, soundUri)
                        if (ringtone == null) {
                            result.success(false)
                        } else {
                            notificationSoundPreview?.stop()
                            notificationSoundPreview = ringtone
                            ringtone.play()
                            result.success(true)
                        }
                    } catch (_: Exception) {
                        result.error(
                            "system_sound_failed",
                            "The system notification sound could not be played.",
                            null,
                        )
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        notificationSoundPreview?.stop()
        notificationSoundPreview = null
        super.onDestroy()
    }
}
