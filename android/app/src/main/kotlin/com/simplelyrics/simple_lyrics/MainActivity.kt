package com.simplelyrics.simple_lyrics

import android.content.ComponentName
import android.content.Intent
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.WindowManager
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsControllerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * MainActivity sets up platform channels for communication
 * between Flutter and the native MediaNotificationListener.
 *
 * - MethodChannel: for commands (play, pause, next, prev, seekTo)
 *   and permission checks
 * - EventChannel: for streaming media state updates to Flutter
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val METHOD_CHANNEL = "com.simplelyrics/media"
        private const val EVENT_CHANNEL = "com.simplelyrics/media_events"
    }

    private var eventSink: EventChannel.EventSink? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Force edge-to-edge at the Window level on all supported versions
        WindowCompat.setDecorFitsSystemWindows(window, false)
        window.statusBarColor = Color.TRANSPARENT
        window.navigationBarColor = Color.TRANSPARENT
        WindowInsetsControllerCompat(window, window.decorView).apply {
            isAppearanceLightStatusBars = false
            isAppearanceLightNavigationBars = false
        }
        
        // Keep the screen awake while the app is visible
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        // Request the highest available refresh rate (e.g., 90Hz/120Hz) instead of the default 60Hz cap
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val modes = windowManager.defaultDisplay.supportedModes
            val preferredMode = modes.maxByOrNull { it.refreshRate }
            if (preferredMode != null) {
                val layoutParams = window.attributes
                layoutParams.preferredDisplayModeId = preferredMode.modeId
                window.attributes = layoutParams
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── Method Channel ──────────────────────────────────────────
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            METHOD_CHANNEL
        ).setMethodCallHandler { call, result ->
            val listener = MediaNotificationListener.instance

            when (call.method) {
                "isPermissionGranted" -> {
                    result.success(isNotificationListenerEnabled())
                }

                "requestPermission" -> {
                    openNotificationListenerSettings()
                    result.success(null)
                }

                "play" -> {
                    listener?.play()
                    result.success(null)
                }

                "pause" -> {
                    listener?.pause()
                    result.success(null)
                }

                "next" -> {
                    listener?.next()
                    result.success(null)
                }

                "previous" -> {
                    listener?.previous()
                    result.success(null)
                }

                "seekTo" -> {
                    val posMs = (call.arguments as? Number)?.toLong() ?: 0L
                    listener?.seekTo(posMs)
                    result.success(null)
                }

                "refreshState" -> {
                    listener?.broadcastState()
                    result.success(null)
                }

                "setRepeatMode" -> {
                    val mode = (call.arguments as? Number)?.toInt() ?: 0
                    listener?.setRepeatMode(mode)
                    result.success(null)
                }

                "setShuffleMode" -> {
                    val mode = (call.arguments as? Number)?.toInt() ?: 0
                    listener?.setShuffleMode(mode)
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }

        // ── Event Channel ───────────────────────────────────────────
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            EVENT_CHANNEL
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events

                // Wire up the listener callback to push to Flutter
                MediaNotificationListener.onMediaStateChanged = { stateMap ->
                    runOnUiThread {
                        eventSink?.success(stateMap)
                    }
                }

                // Send initial state if service is already running
                MediaNotificationListener.instance?.broadcastState()
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
                MediaNotificationListener.onMediaStateChanged = null
            }
        })
    }

    /**
     * Check if this app's NotificationListenerService is enabled.
     */
    private fun isNotificationListenerEnabled(): Boolean {
        val flat = Settings.Secure.getString(
            contentResolver,
            "enabled_notification_listeners"
        ) ?: return false

        val componentName = ComponentName(this, MediaNotificationListener::class.java)
        return flat.contains(componentName.flattenToString())
    }

    /**
     * Open the system notification listener settings page.
     */
    private fun openNotificationListenerSettings() {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
            Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
        } else {
            Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS")
        }
        startActivity(intent)
    }
}
