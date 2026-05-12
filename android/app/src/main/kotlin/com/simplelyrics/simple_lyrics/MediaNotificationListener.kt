package com.simplelyrics.simple_lyrics

import android.content.ComponentName
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.net.Uri
import android.os.Build
import android.os.SystemClock
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import java.io.ByteArrayOutputStream

/**
 * NotificationListenerService that detects active media sessions
 * and extracts metadata (title, artist, album art) and playback state.
 *
 * Uses MediaSessionManager as primary source, with notification
 * content as fallback when MediaSession data is unavailable.
 */
class MediaNotificationListener : NotificationListenerService() {

    companion object {
        private const val TAG = "MediaNotifListener"

        // Singleton bridge for communicating with MainActivity
        @Volatile
        var instance: MediaNotificationListener? = null
            private set

        // Callback for media state changes
        var onMediaStateChanged: ((Map<String, Any?>) -> Unit)? = null
    }

    private var mediaSessionManager: MediaSessionManager? = null
    private var activeController: MediaController? = null
    private var cachedArtBitmap: Bitmap? = null
    private var cachedArtBytes: ByteArray? = null
    private var lastSentArtKey: String? = null
    private var lastSentHadArt = false

    private var lastBroadcastTime = 0L
    private var lastReportedState: Int? = null
    private var lastReportedTitle: String? = null

    private val shuffleModeNone = 0
    private val repeatModeNone = 0
    private val actionSetRepeatMode = 1L shl 18
    private val actionSetShuffleMode = 1L shl 19

    private val sessionCallback = object : MediaController.Callback() {
        override fun onMetadataChanged(metadata: MediaMetadata?) {
            val title = metadata?.getString(MediaMetadata.METADATA_KEY_TITLE)
            val artist = metadata?.getString(MediaMetadata.METADATA_KEY_ARTIST)
            val newKey = "$title|$artist"
            if (newKey != lastReportedTitle) {
                lastReportedTitle = newKey
                broadcastState()
            }
        }

        override fun onPlaybackStateChanged(state: PlaybackState?) {
            val stateCode = state?.state
            val now = SystemClock.elapsedRealtime()
            // Reduce broadcast frequency for position updates, but ensure we don't miss state changes
            if (stateCode != lastReportedState || (now - lastBroadcastTime) > 2000) {
                lastReportedState = stateCode
                lastBroadcastTime = now
                broadcastState()
            }
        }
    }

    private val sessionsChangedListener =
        MediaSessionManager.OnActiveSessionsChangedListener { controllers ->
            Log.d(TAG, "Active sessions changed: ${controllers?.size ?: 0} sessions")
            updateActiveController(controllers)
        }

    override fun onCreate() {
        super.onCreate()
        instance = this
        Log.d(TAG, "Service created")

        mediaSessionManager =
            getSystemService(Context.MEDIA_SESSION_SERVICE) as? MediaSessionManager

        // Start listening for session changes
        try {
            val componentName = ComponentName(this, this::class.java)
            mediaSessionManager?.addOnActiveSessionsChangedListener(
                sessionsChangedListener, componentName
            )

            // Get initial sessions
            val controllers = mediaSessionManager?.getActiveSessions(componentName)
            updateActiveController(controllers)
        } catch (e: SecurityException) {
            Log.e(TAG, "SecurityException - notification access not granted", e)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        instance = null
        activeController?.unregisterCallback(sessionCallback)
        try {
            mediaSessionManager?.removeOnActiveSessionsChangedListener(sessionsChangedListener)
        } catch (e: Exception) {
            Log.e(TAG, "Error removing sessions listener", e)
        }
        Log.d(TAG, "Service destroyed")
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        // We primarily rely on MediaSessionManager, but this keeps
        // the service active. Could be extended for fallback metadata.
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        // No-op
    }

    /**
     * Pick the most relevant controller (prefer the one that's playing).
     */
    private fun updateActiveController(controllers: List<MediaController>?) {
        if (controllers.isNullOrEmpty()) {
            activeController?.unregisterCallback(sessionCallback)
            activeController = null
            lastSentArtKey = null // Reset so we resend when a session appears
            broadcastState()
            return
        }

        // Prefer a controller that is currently playing
        val playingController = controllers.firstOrNull {
            it.playbackState?.state == PlaybackState.STATE_PLAYING
        }
        val newController = playingController ?: controllers[0]

        if (newController != activeController) {
            activeController?.unregisterCallback(sessionCallback)
            activeController = newController
            activeController?.registerCallback(sessionCallback)
            lastSentArtKey = null // New controller, force artwork refresh
        }

        broadcastState()
    }

    /**
     * Collect current state and send it through the callback.
     */
    fun broadcastState() {
        val controller = activeController
        val metadata = controller?.metadata
        val playbackState = controller?.playbackState

        val title = metadata?.getString(MediaMetadata.METADATA_KEY_TITLE)
            ?: metadata?.getString(MediaMetadata.METADATA_KEY_DISPLAY_TITLE)
            ?: "No media playing"

        val artist = metadata?.getString(MediaMetadata.METADATA_KEY_ARTIST)
            ?: metadata?.getString(MediaMetadata.METADATA_KEY_ALBUM_ARTIST)
            ?: ""

        val duration = metadata?.getLong(MediaMetadata.METADATA_KEY_DURATION) ?: 0L
        var position = playbackState?.position ?: 0L
        val stateCode = playbackState?.state ?: lastReportedState
        val isPlaying = stateCode == PlaybackState.STATE_PLAYING ||
            stateCode == PlaybackState.STATE_BUFFERING
        val repeatMode = getPlaybackStateInt(playbackState, "repeatMode", repeatModeNone)
        val shuffleMode = getPlaybackStateInt(playbackState, "shuffleMode", shuffleModeNone)
        val actions = playbackState?.actions ?: 0L
        val supportsRepeatMode = (actions and actionSetRepeatMode) != 0L
        val supportsShuffleMode = (actions and actionSetShuffleMode) != 0L
        
        if (isPlaying && playbackState != null) {
            val timeDelta = SystemClock.elapsedRealtime() - playbackState.lastPositionUpdateTime
            position += (timeDelta * playbackState.playbackSpeed).toLong()
        }

        val stateMap = mutableMapOf<String, Any?>(
            "title" to title,
            "artist" to artist,
            "position" to position,
            "duration" to duration,
            "isPlaying" to isPlaying,
            "repeatMode" to repeatMode,
            "shuffleMode" to shuffleMode,
            "supportsRepeatMode" to supportsRepeatMode,
            "supportsShuffleMode" to supportsShuffleMode,
        )

        // ARTWORK OPTIMIZATION:
        // Only include artwork in the payload if it has changed since last broadcast.
        // This keeps position updates (every 1-2s) extremely light.
        val currentArtKey = "$title|$artist"
        val artBitmap = metadata?.let { getArtworkBitmap(it) }

        val hasArt = artBitmap != null
        val shouldSendArt = currentArtKey != lastSentArtKey || (hasArt && !lastSentHadArt)

        if (shouldSendArt) {
            val artBytes = artBitmap?.let { getEncodedBitmap(it) }
            stateMap["albumArt"] = artBytes
            lastSentArtKey = currentArtKey
            lastSentHadArt = artBytes != null
        }

        onMediaStateChanged?.invoke(stateMap)
    }

    private fun getArtworkBitmap(metadata: MediaMetadata): Bitmap? {
        metadata.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART)?.let { return it }
        metadata.getBitmap(MediaMetadata.METADATA_KEY_ART)?.let { return it }
        metadata.getBitmap(MediaMetadata.METADATA_KEY_DISPLAY_ICON)?.let { return it }

        return decodeArtworkUri(metadata.getString(MediaMetadata.METADATA_KEY_ALBUM_ART_URI))
            ?: decodeArtworkUri(metadata.getString(MediaMetadata.METADATA_KEY_ART_URI))
            ?: decodeArtworkUri(metadata.getString(MediaMetadata.METADATA_KEY_DISPLAY_ICON_URI))
    }

    private fun decodeArtworkUri(uriString: String?): Bitmap? {
        if (uriString.isNullOrBlank()) return null

        return try {
            contentResolver.openInputStream(Uri.parse(uriString))?.use { stream ->
                BitmapFactory.decodeStream(stream)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Could not decode artwork URI", e)
            null
        }
    }

    /**
     * Compress a bitmap to bytes for transfer over platform channel.
     */
    private fun encodeBitmap(bitmap: Bitmap): ByteArray {
        val stream = ByteArrayOutputStream()
        // Keep enough detail for Flutter-side palette/background extraction.
        val maxDim = 512
        val scaled = if (bitmap.width > maxDim || bitmap.height > maxDim) {
            val ratio = minOf(
                maxDim.toFloat() / bitmap.width,
                maxDim.toFloat() / bitmap.height
            )
            Bitmap.createScaledBitmap(
                bitmap,
                (bitmap.width * ratio).toInt(),
                (bitmap.height * ratio).toInt(),
                true
            )
        } else {
            bitmap
        }
        
        scaled.compress(Bitmap.CompressFormat.JPEG, 82, stream)
        return stream.toByteArray()
    }

    private fun getEncodedBitmap(bitmap: Bitmap): ByteArray {
        // Strict identity check for caching
        val cachedBitmap = cachedArtBitmap
        val cachedBytes = cachedArtBytes
        if (cachedBitmap === bitmap && cachedBytes != null) {
            return cachedBytes
        }

        return encodeBitmap(bitmap).also {
            cachedArtBitmap = bitmap
            cachedArtBytes = it
        }
    }

    private fun getPlaybackStateInt(
        state: PlaybackState?,
        methodName: String,
        fallback: Int,
    ): Int {
        if (state == null) return fallback
        return try {
            val fn = state.javaClass.getMethod(methodName)
            (fn.invoke(state) as? Int) ?: fallback
        } catch (e: Exception) {
            fallback
        }
    }

    // ── Transport Controls ─────────────────────────────────────────

    fun play() {
        activeController?.transportControls?.play()
    }

    fun pause() {
        activeController?.transportControls?.pause()
    }

    fun next() {
        activeController?.transportControls?.skipToNext()
    }

    fun previous() {
        activeController?.transportControls?.skipToPrevious()
    }

    fun seekTo(positionMs: Long) {
        activeController?.transportControls?.seekTo(positionMs)
    }

    fun setRepeatMode(mode: Int) {
        invokeTransportControlsIntMethod("setRepeatMode", mode)
    }

    fun setShuffleMode(mode: Int) {
        invokeTransportControlsIntMethod("setShuffleMode", mode)
    }

    private fun invokeTransportControlsIntMethod(method: String, value: Int) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val controls = activeController?.transportControls ?: return
        try {
            val fn = controls.javaClass.getMethod(method, Int::class.javaPrimitiveType)
            fn.invoke(controls, value)
        } catch (e: Exception) {
            Log.w(TAG, "TransportControls method not available: $method", e)
        }
    }
}
