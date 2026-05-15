import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/media_state.dart';
import '../services/media_session_service.dart';

/// Floating playback controls overlay with modern glassmorphism.
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
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: IgnorePointer(
        ignoring: !widget.visible,
        child: AnimatedOpacity(
          opacity: widget.visible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.0),
                      Colors.black.withValues(alpha: 0.45),
                    ],
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildSeekBar(context),
                        const SizedBox(height: 12),
                        _buildMainControlsRow(),
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
            trackHeight: 4,
            trackShape: const RoundedRectSliderTrackShape(),
            thumbShape: SliderComponentShape.noThumb,
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 0),
            activeTrackColor: Colors.white,
            inactiveTrackColor: Colors.white.withValues(alpha: 0.15),
          ),
          child: Slider(
            value: currentVal,
            min: 0.0,
            max: maxVal,
            onChanged: (value) {
              widget.onInteraction();
              setState(() {
                _isDragging = true;
                _smoothPositionMs = value;
              });
              widget.onPositionPreviewing(true);
              widget.onPositionPreview(Duration(milliseconds: value.toInt()));
            },
            onChangeEnd: (value) {
              widget.onInteraction();
              _isDragging = false;
              widget.onPositionPreviewing(false);
              widget.service.seekTo(Duration(milliseconds: value.toInt()));
            },
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(Duration(milliseconds: currentVal.toInt())),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Display',
                ),
              ),
              Text(
                _formatDuration(widget.mediaState.duration),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Display',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMainControlsRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _SecondaryControl(
          icon: widget.mediaState.shuffleMode == 0 ? Icons.shuffle_rounded : Icons.shuffle_on_rounded,
          isActive: widget.mediaState.shuffleMode != 0,
          onTap: () => widget.service.setShuffleMode(widget.mediaState.shuffleMode == 0 ? 1 : 0),
        ),
        _TransportButton(
          icon: Icons.skip_previous_rounded,
          size: 40,
          onTap: () {
            widget.onInteraction();
            widget.service.previous();
          },
        ),
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
        _TransportButton(
          icon: Icons.skip_next_rounded,
          size: 40,
          onTap: () {
            widget.onInteraction();
            widget.service.next();
          },
        ),
        _SecondaryControl(
          icon: widget.mediaState.repeatMode == 0 ? Icons.repeat_rounded : Icons.repeat_on_rounded,
          isActive: widget.mediaState.repeatMode != 0,
          onTap: () => widget.service.setRepeatMode(widget.mediaState.repeatMode == 0 ? 1 : 0),
        ),
      ],
    );
  }
}

class _TransportButton extends StatefulWidget {
  final IconData icon;
  final double size;
  final VoidCallback onTap;

  const _TransportButton({
    required this.icon,
    required this.size,
    required this.onTap,
  });

  @override
  State<_TransportButton> createState() => _TransportButtonState();
}

class _TransportButtonState extends State<_TransportButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressController;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      reverseDuration: const Duration(milliseconds: 200),
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _pressController.forward(),
      onTapUp: (_) => _pressController.reverse(),
      onTapCancel: () => _pressController.reverse(),
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: ScaleTransition(
        scale: Tween<double>(begin: 1.0, end: 0.82).animate(
          CurvedAnimation(parent: _pressController, curve: Curves.easeOutCubic),
        ),
        child: ClipOval(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.12),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.15),
                  width: 0.5,
                ),
              ),
              child: Icon(
                widget.icon,
                size: widget.size,
                color: Colors.white.withValues(alpha: 0.95),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayPauseButton extends StatefulWidget {
  final bool isPlaying;
  final VoidCallback onTap;

  const _PlayPauseButton({required this.isPlaying, required this.onTap});

  @override
  State<_PlayPauseButton> createState() => _PlayPauseButtonState();
}

class _PlayPauseButtonState extends State<_PlayPauseButton>
    with TickerProviderStateMixin {
  late final AnimationController _pressController;
  late final AnimationController _iconController;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 250),
    );
    _iconController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: widget.isPlaying ? 1.0 : 0.0,
    );
  }

  @override
  void didUpdateWidget(_PlayPauseButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _iconController.forward();
      } else {
        _iconController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _pressController.dispose();
    _iconController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _pressController.forward(),
      onTapUp: (_) => _pressController.reverse(),
      onTapCancel: () => _pressController.reverse(),
      onTap: widget.onTap,
      child: ScaleTransition(
        scale: Tween<double>(begin: 1.0, end: 0.88).animate(
          CurvedAnimation(parent: _pressController, curve: Curves.easeOutCubic),
        ),
        child: ClipOval(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.92),
                boxShadow: [
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.12),
                    blurRadius: 24,
                    spreadRadius: 2,
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: AnimatedIcon(
                icon: AnimatedIcons.play_pause,
                progress: CurvedAnimation(
                  parent: _iconController,
                  curve: Curves.easeInOutCubic,
                ),
                size: 38,
                color: Colors.black,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SecondaryControl extends StatefulWidget {
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  const _SecondaryControl({
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_SecondaryControl> createState() => _SecondaryControlState();
}

class _SecondaryControlState extends State<_SecondaryControl>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressController;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 200),
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isActive
        ? Colors.white
        : Colors.white.withValues(alpha: 0.35);

    return GestureDetector(
      onTapDown: (_) => _pressController.forward(),
      onTapUp: (_) => _pressController.reverse(),
      onTapCancel: () => _pressController.reverse(),
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: ScaleTransition(
        scale: Tween<double>(begin: 1.0, end: 0.85).animate(
          CurvedAnimation(parent: _pressController, curve: Curves.easeOutCubic),
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.isActive
                ? Colors.white.withValues(alpha: 0.15)
                : Colors.transparent,
          ),
          child: Icon(
            widget.icon,
            color: color,
            size: 20,
          ),
        ),
      ),
    );
  }
}
