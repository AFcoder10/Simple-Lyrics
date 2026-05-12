import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/media_state.dart';
import '../services/media_session_service.dart';

/// Floating playback controls overlay.
class PlaybackControls extends StatefulWidget {
  final MediaState mediaState;
  final MediaSessionService service;
  final bool visible;
  final VoidCallback onInteraction;
  final ValueChanged<Duration> onPositionPreview;
  final ValueChanged<bool> onPositionPreviewing;

  const PlaybackControls({
    super.key,
    required this.mediaState,
    required this.service,
    required this.visible,
    required this.onInteraction,
    required this.onPositionPreview,
    required this.onPositionPreviewing,
  });

  @override
  State<PlaybackControls> createState() => _PlaybackControlsState();
}

class _PlaybackControlsState extends State<PlaybackControls> {
  double _smoothPositionMs = 0.0;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _smoothPositionMs = widget.mediaState.position.inMilliseconds.toDouble();
  }

  @override
  void didUpdateWidget(PlaybackControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    final songChanged = widget.mediaState.title != oldWidget.mediaState.title ||
        widget.mediaState.artist != oldWidget.mediaState.artist;

    if (songChanged) {
      _smoothPositionMs = widget.mediaState.position.inMilliseconds.toDouble();
    } else if (!_isDragging) {
      _smoothPositionMs = widget.mediaState.position.inMilliseconds.toDouble();
    }
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: GestureDetector(
        onTap: widget.onInteraction,
        onPanDown: (_) => widget.onInteraction(),
        behavior: HitTestBehavior.opaque,
        child: AnimatedOpacity(
          opacity: widget.visible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          child: IgnorePointer(
            ignoring: !widget.visible,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 12), // Reduced bottom padding
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.0),
                        Colors.black.withValues(alpha: 0.5),
                        Colors.black.withValues(alpha: 0.8),
                      ],
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildSeekBar(context),
                        const SizedBox(height: 16),
                        _buildTransportRow(),
                        const SizedBox(height: 12), 
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSeekBar(BuildContext context) {
    final durationMs = widget.mediaState.duration.inMilliseconds.toDouble();
    final maxVal = durationMs > 0 ? durationMs : 1.0;
    final positionMs = _isDragging
        ? _smoothPositionMs
        : widget.mediaState.position.inMilliseconds.toDouble();
    final currentVal = positionMs.clamp(0.0, maxVal);

    return Column(
      children: [
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 6, // Thicker, modular look
            trackShape: const RoundedRectSliderTrackShape(),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8, elevation: 3),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            activeTrackColor: Colors.white,
            inactiveTrackColor: Colors.white.withValues(alpha: 0.15),
            thumbColor: Colors.white,
          ),
          child: Slider(
            value: currentVal,
            min: 0.0,
            max: maxVal,
            onChanged: (value) {
              widget.onInteraction();
              widget.service.notifyUserInteraction();
              setState(() {
                _isDragging = true;
                _smoothPositionMs = value;
              });
              widget.onPositionPreviewing(true);
              widget.onPositionPreview(
                Duration(milliseconds: value.toInt()),
              );
            },
            onChangeEnd: (value) {
              widget.onInteraction();
              widget.service.notifyUserInteraction();
              _isDragging = false;
              widget.onPositionPreview(
                Duration(milliseconds: value.toInt()),
              );
              widget.onPositionPreviewing(false);
              widget.service.seekTo(Duration(milliseconds: value.toInt()));
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(Duration(milliseconds: currentVal.toInt())),
                style: const TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5),
              ),
              Text(
                _formatDuration(widget.mediaState.duration),
                style: const TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTransportRow() {
    final shuffleActive = widget.mediaState.shuffleMode != 0;
    final repeatMode = widget.mediaState.repeatMode;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Shuffle
        IconButton(
          icon: Icon(
            shuffleActive ? Icons.shuffle_on_rounded : Icons.shuffle_rounded,
            color: shuffleActive ? Colors.white : Colors.white24,
            size: 22,
          ),
          onPressed: () {
            widget.onInteraction();
            widget.service.setShuffleMode(shuffleActive ? 0 : 1);
          },
        ),
        
        // Prev
        IconButton(
          icon: const Icon(Icons.skip_previous_rounded, size: 38),
          color: Colors.white,
          onPressed: () {
            widget.onInteraction();
            widget.service.previous();
          },
        ),
        
        // Play/Pause
        _PlayPauseButton(
          isPlaying: widget.mediaState.isPlaying,
          onTap: () {
            widget.onInteraction();
            if (widget.mediaState.isPlaying) {
              widget.service.pause();
            } else {
              widget.service.play();
            }
          },
        ),

        // Next
        IconButton(
          icon: const Icon(Icons.skip_next_rounded, size: 38),
          color: Colors.white,
          onPressed: () {
            widget.onInteraction();
            widget.service.next();
          },
        ),

        // Repeat
        IconButton(
          icon: Icon(
            repeatMode == 0 ? Icons.repeat_rounded : (repeatMode == 1 ? Icons.repeat_on_rounded : Icons.repeat_one_on_rounded),
            color: repeatMode == 0 ? Colors.white24 : Colors.white,
            size: 22,
          ),
          onPressed: () {
            widget.onInteraction();
            widget.service.setRepeatMode((repeatMode + 1) % 3);
          },
        ),
      ],
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  final bool isPlaying;
  final VoidCallback onTap;

  const _PlayPauseButton({required this.isPlaying, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 68,
        height: 68,
        decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
        child: Icon(
          isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          size: 42,
          color: Colors.black,
        ),
      ),
    );
  }
}
