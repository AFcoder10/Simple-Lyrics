import 'dart:async';
import 'dart:typed_data';
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
  }) {
    if (_currentState.title != title || _currentState.artist != artist) {
      return;
    }

    _currentState = _currentState.copyWithArtwork(
      artworkBytes,
      thumbnailBytes: thumbnailBytes,
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
          );
        })
        .listen(
      (state) {
        final currentSongKey = '${_currentState.title}|${_currentState.artist}';
        final nextSongKey = '${state.title}|${state.artist}';
        final songChanged = !_currentState.isEmpty &&
            !state.isEmpty &&
            currentSongKey != nextSongKey;

        final syncedState = songChanged
            ? state.copyWith(position: Duration.zero)
            : state;

        _currentState = syncedState;
        _stateController.add(syncedState);
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
    if (_currentState.isPlaying && !_currentState.isEmpty) {
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

  void _publishLocalPosition(Duration position) {
    final duration = _currentState.duration;
    final clampedPosition = duration > Duration.zero && position > duration
        ? duration
        : position;
    _currentState = _currentState.copyWith(
      position: clampedPosition,
      lastUpdated: DateTime.now(),
    );
    _stateController.add(_currentState);
  }

  // ─── Transport Controls ───────────────────────────────────────────────

  Future<void> play() async {
    try {
      await _methodChannel.invokeMethod('play');
      await refreshState();
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('play() failed: ${e.message}');
    }
  }

  Future<void> pause() async {
    try {
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
      _publishLocalPosition(position);
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
    _stateController.close();
  }
}
