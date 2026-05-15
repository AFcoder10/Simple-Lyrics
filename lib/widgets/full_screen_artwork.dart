import 'dart:typed_data';
import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../models/media_state.dart';
import '../services/media_session_service.dart';
import 'playback_controls.dart';

class FullScreenArtwork extends StatefulWidget {
  final Uint8List? artBytes;
  final String title;
  final String artist;
  final MediaState mediaState;
  final MediaSessionService service;

  const FullScreenArtwork({
    super.key,
    required this.artBytes,
    required this.title,
    required this.artist,
    required this.mediaState,
    required this.service,
  });

  @override
  State<FullScreenArtwork> createState() => _FullScreenArtworkState();
}

class _FullScreenArtworkState extends State<FullScreenArtwork>
    with SingleTickerProviderStateMixin {
  late MediaState _mediaState;
  late Duration _visualPosition;
  DateTime _lastPositionTick = DateTime.now();
  late final Ticker _positionTicker;
  StreamSubscription<MediaState>? _subscription;
  bool _isPreviewingPosition = false;

  @override
  void initState() {
    super.initState();
    _mediaState = widget.mediaState;
    _visualPosition = widget.mediaState.position;
    _positionTicker = createTicker((_) => _tickVisualPosition())..start();
    _subscription = widget.service.mediaStateStream.listen(_onMediaStateUpdate);
  }

  void _onMediaStateUpdate(MediaState state) {
    if (!mounted) return;
    setState(() {
      _mediaState = state;
      // Sync position if it drifts too much or if song changes
      final delta = (state.position.inMilliseconds - _visualPosition.inMilliseconds).abs();
      if (delta > 1000 || state.title != _mediaState.title) {
        _visualPosition = state.position;
      }
    });
  }

  void _tickVisualPosition() {
    final now = DateTime.now();
    final elapsed = now.difference(_lastPositionTick);
    _lastPositionTick = now;

    if (_isPreviewingPosition || !_mediaState.isPlaying || _mediaState.isEmpty) {
      return;
    }

    final duration = _mediaState.duration;
    final nextPosition = duration > Duration.zero &&
            _visualPosition + elapsed > duration
        ? duration
        : _visualPosition + elapsed;

    if (nextPosition == _visualPosition) return;

    setState(() {
      _visualPosition = nextPosition;
    });
  }

  void _previewVisualPosition(Duration position) {
    final duration = _mediaState.duration;
    final clampedPosition = duration > Duration.zero && position > duration
        ? duration
        : position;

    setState(() {
      _visualPosition = clampedPosition;
      _lastPositionTick = DateTime.now();
    });
  }

  @override
  void dispose() {
    _positionTicker.dispose();
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size.width * 0.85;
    final visualMediaState = _mediaState.copyWith(position: _visualPosition);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Dynamic Blur Background
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) {
              return BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: value * 25, 
                  sigmaY: value * 25,
                ),
                child: Container(
                  color: Colors.black.withValues(alpha: value * 0.6),
                ),
              );
            },
          ),
          // Interactive Layer
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            onVerticalDragUpdate: (details) {
              if (details.primaryDelta! > 10) {
                Navigator.of(context).pop();
              }
            },
            child: Container(
              width: double.infinity,
              height: double.infinity,
              color: Colors.transparent,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Hero(
                      tag: 'album_art',
                      child: Container(
                        width: size,
                        height: size,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.5),
                              blurRadius: 40,
                              spreadRadius: 4,
                              offset: const Offset(0, 20),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: widget.artBytes != null && widget.artBytes!.isNotEmpty
                            ? Image.memory(
                                widget.artBytes!,
                                fit: BoxFit.cover,
                              )
                            : Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [Colors.grey.shade800, Colors.grey.shade900],
                                  ),
                                ),
                                child: const Icon(Icons.music_note_rounded, color: Colors.white38, size: 80),
                              ),
                      ),
                    ),
                    const SizedBox(height: 40),
                    Hero(
                      tag: 'song_title',
                      child: Material(
                        type: MaterialType.transparency,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 40),
                          child: Text(
                            _mediaState.title,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontFamily: 'Display',
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Hero(
                      tag: 'song_artist',
                      child: Material(
                        type: MaterialType.transparency,
                        child: Text(
                          _mediaState.artist,
                          style: TextStyle(
                            fontFamily: 'Display',
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Playback Controls
          PlaybackControls(
            mediaState: visualMediaState,
            service: widget.service,
            visible: true,
            onInteraction: () {},
            onPositionPreview: _previewVisualPosition,
            onPositionPreviewing: (val) => setState(() => _isPreviewingPosition = val),
          ),
        ],
      ),
    );
  }
}
