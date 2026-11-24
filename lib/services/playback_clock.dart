/// The one authoritative playback position for the UI.
///
/// Lyric highlighting needs a position that is both *smooth* (advances every
/// frame) and *exact* (snaps the instant the user pauses, resumes or seeks),
/// but native media events only arrive every ~250ms and only when the source
/// app decides to report something. This class owns that translation.
///
/// Model: native samples are *corrections*, not the display clock. Between
/// samples the position is derived from a monotonic stopwatch.
///
/// * **Playing** — position = anchor + elapsed * rate. Ordinary sampling
///   noise is ignored so the highlight never steps; small drift is eased in;
///   a real jump (external seek) is adopted immediately.
/// * **Paused / buffering** — the clock freezes on its own derived position.
///   Stale native reports cannot rewind the highlight. A large jump while
///   paused is treated as a seek in the source app.
/// * **Local play / pause** — [setAdvancing] freezes or resumes on the next
///   frame, then native is ignored until it agrees (or the hold times out).
/// * **Seek** — the target becomes the anchor immediately. Native reports
///   are ignored until they land near the target (or until it is clear the
///   source went somewhere else). The highlight never springs back.
/// * **Track change** — everything resets from the sample we were given.
///
/// Timing uses a [Stopwatch] rather than [DateTime.now] because the latter is
/// only millisecond-resolution (and can be coarser than that on Windows). A
/// stopwatch uses the system's performance counter.
class PlaybackClock {
  PlaybackClock({
    int Function()? nowUs,
    this.nativeLag = Duration.zero,
  }) : _nowUsOverride = nowUs;

  final int Function()? _nowUsOverride;
  final Stopwatch _stopwatch = Stopwatch()..start();

  /// GSMTC / MediaSession position lags the audible playhead. Added to every
  /// native sample so lyrics at offset 0 match the audio. The lyrics-offset
  /// setting is extra trim on top of this.
  final Duration nativeLag;

  /// How long a seek target is protected from contradictory native reports.
  static const int _seekHoldUs = 900 * 1000;

  /// How long a local play/pause is protected from a lagging native state.
  static const int _transportHoldUs = 1500 * 1000;

  /// After the hold, keep ignoring stale reports until this many consecutive
  /// samples agree the source is somewhere else (seek rejected / redirected).
  static const int _seekRedirectVotes = 2;

  /// Native is close enough to our seek target to confirm it.
  static const Duration _seekConfirmTolerance = Duration(milliseconds: 180);

  /// Sampling jitter we refuse to paint. Inside this window we keep our own
  /// continuous estimate so a 250ms native tick never becomes a hitch.
  static const Duration _noiseTolerance = Duration(milliseconds: 80);

  /// Drift large enough to ease toward, but not large enough to treat as a
  /// seek. Hard-snapping this window is what made karaoke hitch.
  static const Duration _softCorrectTolerance = Duration(milliseconds: 400);

  /// Fraction of remaining error taken on each native sample in the soft
  /// window. 0.2 settles ~200ms of error in a few ticks without a visible jump.
  static const double _softCorrectGain = 0.2;

  /// While paused, native is only trusted when it moved this far — otherwise
  /// it is the same stale snapshot the player keeps republishing.
  static const Duration _pausedSeekTolerance = Duration(milliseconds: 350);

  /// How far behind a resume sample may be before we treat it as a real seek
  /// rather than GSMTC lag from the last pause.
  static const Duration _resumeLagTolerance = Duration(milliseconds: 1500);

  Duration _position = Duration.zero;
  bool _playing = false;
  double _rate = 1.0;
  Duration _duration = Duration.zero;

  /// Previous position reported by the source, used to reject stale repeats.
  Duration? _lastNativePosition;

  bool _previewing = false;
  Duration _previewPosition = Duration.zero;

  Duration? _seekTarget;
  int _seekExpiresUs = 0;
  int _seekRedirectCount = 0;

  bool? _wantedAdvancing;
  int _transportExpiresUs = 0;

  int get _nowUs => _nowUsOverride?.call() ?? _stopwatch.elapsedMicroseconds;
  bool get _seekPending => _seekTarget != null;
  bool get _seekHoldActive =>
      _seekTarget != null && _nowUs < _seekExpiresUs;

  /// Position the UI should display right now.
  Duration get position {
    if (_previewing) {
      return _previewPosition;
    }
    return _advancingPosition;
  }

  Duration get _advancingPosition {
    if (!_playing) return _position;

    final elapsedUs = _nowUs - _anchorUs;
    if (elapsedUs <= 0) return _position;

    final scaledUs = _rate == 1.0
        ? elapsedUs
        : (elapsedUs * _rate).round();
    final next = _position + Duration(microseconds: scaledUs);
    if (_duration > Duration.zero && next > _duration) return _duration;
    return next;
  }

  int _anchorUs = 0;

  bool get isPlaying => _playing;
  double get rate => _rate;
  Duration get duration => _duration;
  bool get previewing => _previewing;
  bool get seeking => _seekPending;

  /// Adopt a sample published by the native layer.
  ///
  /// [isPlaying] here means "the audio is advancing" — paused, stopped and
  /// buffering are all false. The transport UI may still show a play glyph
  /// during buffering; that is a different flag.
  ///
  /// [songChanged] forces a full reset so a new track does not inherit the
  /// previous track's position.
  void sync({
    required Duration position,
    required bool isPlaying,
    Duration duration = Duration.zero,
    double playbackRate = 1.0,
    bool songChanged = false,
  }) {
    if (nativeLag != Duration.zero) {
      position += nativeLag;
      if (duration > Duration.zero && position > duration) {
        position = duration;
      }
    }

    if (songChanged) {
      reset();
      _duration = duration;
      _position = position;
      _anchorUs = _nowUs;
      _playing = isPlaying;
      _rate = playbackRate > 0 && isPlaying ? playbackRate : 1.0;
      _lastNativePosition = position;
      return;
    }

    _duration = duration;

    final advancing = _resolveAdvancing(isPlaying);
    final rate = playbackRate > 0 && advancing ? playbackRate : 1.0;

    // Fold elapsed time into the anchor *before* any decision below. Every
    // exit path therefore leaves the clock continuous; otherwise a sample we
    // chose to ignore would silently rewind or freeze the position back to
    // its previous anchor.
    final derived = _advancingPosition;
    _position = derived;
    _anchorUs = _nowUs;
    _rate = rate;

    final wasPlaying = _playing;
    final previousNative = _lastNativePosition;
    _lastNativePosition = position;

    if (_applySeekGate(position, derived, advancing)) {
      _playing = advancing;
      return;
    }

    // Local play/pause is in flight and native still disagrees. Keep the
    // freeze/resume point; only a huge jump is treated as an overlapping seek.
    if (_wantedAdvancing != null) {
      _playing = advancing;
      if (_abs(position - derived) > _resumeLagTolerance) {
        _position = position;
        _anchorUs = _nowUs;
      }
      return;
    }

    if (!advancing) {
      _playing = false;
      _applyPausedSample(position, derived, wasPlaying: wasPlaying);
      return;
    }

    _playing = true;

    if (!wasPlaying) {
      _applyResumeSample(position, derived);
      return;
    }

    // A duplicate sample while playing means the source app has gone quiet.
    // Adopting it would pin us to a stale value, so keep deriving instead.
    if (previousNative == position && position != derived) {
      return;
    }

    _applyPlayingSample(position, derived);
  }

  bool _resolveAdvancing(bool nativeAdvancing) {
    final wanted = _wantedAdvancing;
    if (wanted == null) return nativeAdvancing;

    if (nativeAdvancing == wanted) {
      _wantedAdvancing = null;
      return nativeAdvancing;
    }
    if (_nowUs < _transportExpiresUs) {
      return wanted;
    }
    _wantedAdvancing = null;
    return nativeAdvancing;
  }

  /// Freeze or resume immediately from a local play/pause, then ignore native
  /// transport until it agrees (or the hold expires).
  void setAdvancing(bool advancing) {
    final derived = _advancingPosition;
    _position = derived;
    _anchorUs = _nowUs;
    _playing = advancing;
    _wantedAdvancing = advancing;
    _transportExpiresUs = _nowUs + _transportHoldUs;
  }

  /// Returns true if the sample was consumed by the in-flight seek and the
  /// caller should not apply the normal play/pause rules.
  bool _applySeekGate(Duration native, Duration derived, bool isPlaying) {
    final target = _seekTarget;
    if (target == null) return false;

    final awayFromTarget = _abs(native - target);
    if (awayFromTarget <= _seekConfirmTolerance) {
      _clearSeek();
      _position = native;
      _anchorUs = _nowUs;
      return true;
    }

    if (_seekHoldActive) {
      _seekRedirectCount = 0;
      return true;
    }

    // Hold expired but native still disagrees. Keep our target clock unless
    // the source has *consistently* settled somewhere else (rejected seek,
    // or the user seeked again in the other app).
    if (_abs(native - derived) > _seekConfirmTolerance) {
      _seekRedirectCount += 1;
      if (_seekRedirectCount >= _seekRedirectVotes) {
        _clearSeek();
        _position = native;
        _anchorUs = _nowUs;
        _playing = isPlaying;
        return true;
      }
    } else {
      _seekRedirectCount = 0;
    }
    return true;
  }

  void _applyPausedSample(
    Duration native,
    Duration derived, {
    required bool wasPlaying,
  }) {
    // The instant audio stops, freeze on our own derived position. Native
    // reports lag by hundreds of milliseconds and would yank the highlight
    // backwards if we trusted them here.
    if (wasPlaying) {
      if (_abs(native - derived) <= _resumeLagTolerance) {
        return;
      }
      _position = native;
      _anchorUs = _nowUs;
      return;
    }

    if (_abs(native - derived) <= _pausedSeekTolerance) {
      return;
    }
    _position = native;
    _anchorUs = _nowUs;
  }

  void _applyResumeSample(Duration native, Duration derived) {
    // Native is almost always still sitting on the pre-pause snapshot
    // (behind us). Keep the freeze point in that case.
    if (native + _noiseTolerance < derived) {
      return;
    }
    // Close enough to the freeze point that a hitch would be worse than
    // waiting for the next honest sample. Skip this on a true cold start
    // (derived is still zero) so the first native snapshot is adopted.
    if (derived > Duration.zero &&
        _abs(native - derived) <= _resumeLagTolerance) {
      return;
    }
    _position = native;
    _anchorUs = _nowUs;
  }

  void _applyPlayingSample(Duration native, Duration derived) {
    final error = native - derived;
    final abs = _abs(error);
    if (abs <= _noiseTolerance) {
      return;
    }

    if (abs <= _softCorrectTolerance) {
      final correctionUs =
          (error.inMicroseconds * _softCorrectGain).round();
      _position = derived + Duration(microseconds: correctionUs);
      _anchorUs = _nowUs;
      return;
    }

    // Far enough to be a real correction: source-app seek, restart, or
    // accumulated drift above what jitter can explain.
    _position = native;
    _anchorUs = _nowUs;
  }

  void _clearSeek() {
    _seekTarget = null;
    _seekExpiresUs = 0;
    _seekRedirectCount = 0;
  }

  static Duration _abs(Duration value) =>
      value < Duration.zero ? -value : value;

  /// The user is dragging the scrubber: hold the previewed value verbatim.
  void beginPreview() {
    _previewPosition = position;
    _previewing = true;
  }

  void updatePreview(Duration value) {
    if (!_previewing) return;
    _previewPosition = value;
  }

  /// The drag finished — commit the previewed position as a pending seek so
  /// the UI stays put until the source app confirms it.
  void endPreview() {
    if (!_previewing) return;
    _previewing = false;
    beginSeek(_previewPosition);
  }

  /// Protect [target] from the stale reports most players emit right after a
  /// seek. Called from every seek path (scrub, keyboard, transport buttons).
  void beginSeek(Duration target) {
    _position = target;
    _anchorUs = _nowUs;
    _seekTarget = target;
    _seekExpiresUs = _nowUs + _seekHoldUs;
    _seekRedirectCount = 0;
    _lastNativePosition = null;
  }

  void reset() {
    _position = Duration.zero;
    _anchorUs = _nowUs;
    _playing = false;
    _rate = 1.0;
    _duration = Duration.zero;
    _lastNativePosition = null;
    _previewing = false;
    _previewPosition = Duration.zero;
    _wantedAdvancing = null;
    _transportExpiresUs = 0;
    _clearSeek();
  }
}
