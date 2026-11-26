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
    private var lastBroadcastPos: Long = -1L
    private var lastReportedState: Int? = null
    private var lastReportedSpeed: Float = 1f
    private var lastReportedTitle: String? = null
    private var listenerRegistered = false

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
            if (state == null) {
                if (lastReportedState != null) {
                    broadcastState()
                }
                return
            }

            val stateCode = state.state
            val speed = state.playbackSpeed
            val now = SystemClock.elapsedRealtime()

            var isExternalSeek = false
            val pos = state.position
            if (pos >= 0L && lastBroadcastPos >= 0L) {
                val elapsed = (now - lastBroadcastTime).coerceAtLeast(0L)
                val expected = if (lastReportedState == PlaybackState.STATE_PLAYING && lastReportedSpeed != 0f) {
                    lastBroadcastPos + (elapsed * lastReportedSpeed).toLong()
                } else {
                    lastBroadcastPos
                }
                if (kotlin.math.abs(pos - expected) > 350L) {
                    isExternalSeek = true
                }
            }

            // Broadcast immediately on state/rate change or external seek (even while paused),
            // otherwise throttle noisy periodic ticks to every ~2s.
            if (stateCode != lastReportedState ||
                speed != lastReportedSpeed ||
                isExternalSeek ||
                (now - lastBroadcastTime) > 2000L
            ) {
                broadcastState()
            }
        }

        override fun onSessionDestroyed() {
            activeController?.unregisterCallback(this)
            activeController = null
            lastSentArtKey = null
            lastSentHadArt = false
            lastReportedTitle = null
            lastReportedState = null
            lastBroadcastPos = -1L
            broadcastState()
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
        ensureActiveSessionListener()
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        instance = this
        Log.d(TAG, "Listener connected")
        mediaSessionManager =
            getSystemService(Context.MEDIA_SESSION_SERVICE) as? MediaSessionManager
        ensureActiveSessionListener()
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        listenerRegistered = false
        try {
            mediaSessionManager?.removeOnActiveSessionsChangedListener(sessionsChangedListener)
        } catch (_: Exception) {
        }
    }

    private fun ensureActiveSessionListener() {
        val manager = mediaSessionManager ?: return
        try {
            val componentName = ComponentName(this, this::class.java)
            if (!listenerRegistered) {
                manager.addOnActiveSessionsChangedListener(
                    sessionsChangedListener, componentName
                )
                listenerRegistered = true
            }
            val controllers = manager.getActiveSessions(componentName)
            updateActiveController(controllers)
        } catch (e: SecurityException) {
            Log.e(TAG, "SecurityException - notification access not granted", e)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        instance = null
        listenerRegistered = false
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

        val album = metadata?.getString(MediaMetadata.METADATA_KEY_ALBUM) ?: ""

        val duration = (metadata?.getLong(MediaMetadata.METADATA_KEY_DURATION) ?: 0L).coerceAtLeast(0L)
        val rawPosition = playbackState?.position ?: PlaybackState.PLAYBACK_POSITION_UNKNOWN
        var position = if (rawPosition >= 0L) rawPosition else 0L
        val stateCode = playbackState?.state ?: lastReportedState
        val playbackSpeed = playbackState?.playbackSpeed ?: 1f
        val isAdvancing = stateCode == PlaybackState.STATE_PLAYING && playbackSpeed != 0f
        // Buffering still counts as "playing" for the transport glyph, but the
        // lyric clock must freeze until audio is moving again.
        val isPlaying = isAdvancing || stateCode == PlaybackState.STATE_BUFFERING
        val repeatMode = getPlaybackStateInt(playbackState, "repeatMode", repeatModeNone)
        val shuffleMode = getPlaybackStateInt(playbackState, "shuffleMode", shuffleModeNone)
        val actions = playbackState?.actions ?: 0L
        val supportsRepeatMode = (actions and actionSetRepeatMode) != 0L
        val supportsShuffleMode = (actions and actionSetShuffleMode) != 0L

        if (isAdvancing && playbackState != null && rawPosition >= 0L) {
            val updateTime = playbackState.lastPositionUpdateTime
            if (updateTime > 0L) {
                val timeDelta = (SystemClock.elapsedRealtime() - updateTime).coerceAtLeast(0L)
                position += (timeDelta * playbackSpeed).toLong()
            }
        }
        position = if (duration > 0L) position.coerceIn(0L, duration) else position.coerceAtLeast(0L)

        lastReportedState = stateCode
        lastReportedSpeed = playbackSpeed
        lastBroadcastTime = SystemClock.elapsedRealtime()
        lastBroadcastPos = position

        val stateMap = mutableMapOf<String, Any?>(
            "title" to title,
            "artist" to artist,
            "album" to album,
            "position" to position,
            "duration" to duration,
            "isPlaying" to isPlaying,
            "isAdvancing" to isAdvancing,
            "playbackRate" to playbackSpeed.toDouble(),
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
