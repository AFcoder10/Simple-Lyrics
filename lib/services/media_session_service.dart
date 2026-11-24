import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/media_state.dart';

/// Service that bridges Flutter ↔ Android MediaSession via platform channels.
///
/// Uses [MethodChannel] for commands (play, pause, seek, etc.)
/// and [EventChannel] for receiving real-time media state updates.
class MediaSessionService {
  static const _methodChannel = MethodChannel('com.simplelyrics/media');
  static const _eventChannel = EventChannel('com.simplelyrics/media_events');

  final _stateController = StreamController<MediaState>.broadcast();
  StreamSubscription? _eventSubscription;
  Timer? _refreshTimer;
  MediaState _currentState = MediaState.empty();

  /// Fired whenever a seek is requested, by any code path (scrub, keyboard,
  /// transport buttons). The PlaybackClock subscribes to this so the UI holds
  /// the target until the source app confirms it, instead of snapping back to
  /// the pre-seek position while the platform catches up.
  final ValueNotifier<Duration?> seekRequested = ValueNotifier<Duration?>(null);

  /// Fired on local play/pause so the lyric clock can freeze or resume on the
  /// next frame, instead of waiting for the source app to publish the new
  /// PlaybackStatus.
  final ValueNotifier<bool?> advancingRequested = ValueNotifier<bool?>(null);

  /// The position the UI is currently showing. Keyboard seeks add to this
  /// rather than the lagging native snapshot, so repeated arrow-key seeks
  /// stack on what the user sees.
  Duration displayPosition = Duration.zero;

  /// The track currently displayed, used to spot a track change on the very
  /// first snapshot instead of waiting for a second, differing one.
  String _activeTrackKey = '';

  String _trackKeyOf(MediaState state) => '${state.title}|${state.artist}';
  
  /// Whether the user is currently interacting (dragging slider, seeking, etc).
  /// Used to hide interludes and other UI elements that should clear on user action.
  final userInteractingNotifier = ValueNotifier<bool>(false);
  Timer? _interactionResetTimer;

  /// Call this when the user starts an interaction (seeking, dragging).
  /// It sets the notifier to true and schedules a reset after 1.5s of no calls.
  void notifyUserInteraction() {
    userInteractingNotifier.value = true;
    _interactionResetTimer?.cancel();
    _interactionResetTimer = Timer(const Duration(milliseconds: 1500), () {
      userInteractingNotifier.value = false;
    });
  }

  /// Stream of media state updates.
  Stream<MediaState> get mediaStateStream => _stateController.stream;

  /// The current media state snapshot.
  MediaState get currentState => _currentState;

  /// Publish artwork updates sourced from the Flutter side (iTunes fetch).
  void updateArtworkForSong({
    required String title,
    required String artist,
    required Uint8List? artworkBytes,
    Uint8List? thumbnailBytes,
    String? tallMasterUrl,
    String? squareMasterUrl,
  }) {
    if (_currentState.title != title || _currentState.artist != artist) {
      return;
    }

    _currentState = _currentState.copyWithArtwork(
      artworkBytes,
      thumbnailBytes: thumbnailBytes,
      tallMasterUrl: tallMasterUrl,
      squareMasterUrl: squareMasterUrl,
    );
    _stateController.add(_currentState);
  }

  /// Initialize the service and start listening to native events.
  void init() {
    _eventSubscription = _eventChannel
        .receiveBroadcastStream()
        .map((event) {
          return MediaState.fromMap(
            event as Map<dynamic, dynamic>,
            previousArtwork: _currentState.albumArtBytes,
            previousThumbnail: _currentState.thumbnailArtBytes,
            previousTitle: _currentState.title,
            previousArtist: _currentState.artist,
            previousTallMasterUrl: _currentState.tallMasterUrl,
            previousSquareMasterUrl: _currentState.squareMasterUrl,
          );
        })
        .listen(
      (state) {
        final nextSongKey = _trackKeyOf(state);
        final songChanged =
            _activeTrackKey.isNotEmpty && nextSongKey != _activeTrackKey;

        if (songChanged) {
          _activeTrackKey = nextSongKey;
        } else if (nextSongKey != _activeTrackKey) {
          // First snapshot ever: adopt the track without treating it as a
          // change.
          _activeTrackKey = nextSongKey;
        }

        _currentState = state;
        _stateController.add(state);
        _syncRefreshTimer();

        if (songChanged) {
          _refreshAfterTrackChange();
        }
      },
      onError: (error) {
        // ignore: avoid_print
        print('MediaSessionService EventChannel error: $error');
      },
    );

    refreshState();
  }

  void _syncRefreshTimer() {
    if (_currentState.isAdvancing && !_currentState.isEmpty) {
      if (_refreshTimer?.isActive ?? false) return;
      _refreshTimer = Timer.periodic(
        const Duration(milliseconds: 500),
        (_) => refreshState(),
      );
    } else {
      _refreshTimer?.cancel();
      _refreshTimer = null;
    }
  }

  void _refreshAfterTrackChange() {
    refreshState();
    for (final delay in const [
      Duration(milliseconds: 120),
      Duration(milliseconds: 300),
      Duration(milliseconds: 700),
    ]) {
      Timer(delay, refreshState);
    }
  }

  Future<void> refreshState() async {
    try {
      await _methodChannel.invokeMethod('refreshState');
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('refreshState() failed: ${e.message}');
    }
  }

  // ─── Transport Controls ───────────────────────────────────────────────

  Future<void> play() async {
    try {
      advancingRequested.value = true;
      advancingRequested.value = null;
      await _methodChannel.invokeMethod('play');
      await refreshState();
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('play() failed: ${e.message}');
    }
  }

  Future<void> pause() async {
    try {
      advancingRequested.value = false;
      advancingRequested.value = null;
      await _methodChannel.invokeMethod('pause');
      await refreshState();
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('pause() failed: ${e.message}');
    }
  }

  Future<void> next() async {
    try {
      await _methodChannel.invokeMethod('next');
      await refreshState();
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('next() failed: ${e.message}');
    }
  }

  Future<void> previous() async {
    try {
      await _methodChannel.invokeMethod('previous');
      await refreshState();
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('previous() failed: ${e.message}');
    }
  }

  Future<void> seekTo(Duration position) async {
    try {
      // Let the playback clock lock onto the target before the source app has
      // had a chance to answer, so the scrubber does not spring back first.
      // Do *not* publish a fake native sample: that would confirm the seek
      // and then the next stale GSMTC report would yank the highlight back.
      seekRequested.value = position;
      seekRequested.value = null;
      await _methodChannel.invokeMethod('seekTo', position.inMilliseconds);
      await refreshState();
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('seekTo() failed: ${e.message}');
    }
  }

  Future<void> setShuffleMode(int mode) async {
    try {
      await _methodChannel.invokeMethod('setShuffleMode', mode);
      await refreshState();
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('setShuffleMode() failed: ${e.message}');
    }
  }

  Future<void> setRepeatMode(int mode) async {
    try {
      await _methodChannel.invokeMethod('setRepeatMode', mode);
      await refreshState();
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('setRepeatMode() failed: ${e.message}');
    }
  }

  // ─── Permission Handling ──────────────────────────────────────────────

  /// Check if notification listener permission is granted.
  Future<bool> isPermissionGranted() async {
    try {
      final result =
          await _methodChannel.invokeMethod<bool>('isPermissionGranted');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Open Android notification listener settings.
  Future<void> requestPermission() async {
    try {
      await _methodChannel.invokeMethod('requestPermission');
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('requestPermission() failed: ${e.message}');
    }
  }

  /// Dispose streams and timers.
  void dispose() {
    _refreshTimer?.cancel();
    _interactionResetTimer?.cancel();
    _eventSubscription?.cancel();
    seekRequested.dispose();
    advancingRequested.dispose();
    _stateController.close();
  }
}
