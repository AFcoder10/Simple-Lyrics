import 'package:flutter/material.dart';

import '../core/font_fallbacks.dart';
import '../models/media_state.dart';
import '../services/media_session_service.dart';
import '../services/settings_service.dart';
import '../services/window_service.dart';
import 'animated_artwork_player.dart';
import 'backgrounds/background_controller.dart';

/// The desktop layout: square artwork, metadata and transport stacked down the
/// left, lyrics running down the right.
///
/// This is the default Windows window, not a special mode — the phone-shaped
/// home this app was ported from wastes the width of a desktop window, so the
/// split is what actually fills it. [fullscreen] only tightens the padding and
/// grows the artwork, because nothing about the layout itself changes.
class NowPlayingSplitView extends StatefulWidget {
  final MediaState mediaState;
  final MediaSessionService service;

  /// Built by the screen that owns the lyrics state, so windowed, fullscreen
  /// and compact all share one [LyricsView] (and therefore one autoscroll and
  /// offset state).
  final Widget lyrics;

  final ValueNotifier<Duration> positionNotifier;
  final bool fullscreen;
  final VoidCallback onSettings;
  final void Function(Duration) onPositionPreview;
  final void Function(bool) onPositionPreviewing;

  const NowPlayingSplitView({
    super.key,
    required this.mediaState,
    required this.service,
    required this.lyrics,
    required this.positionNotifier,
    required this.onSettings,
    required this.onPositionPreview,
    required this.onPositionPreviewing,
    this.fullscreen = false,
  });

  @override
  State<NowPlayingSplitView> createState() => _NowPlayingSplitViewState();
}

class _NowPlayingSplitViewState extends State<NowPlayingSplitView> {
  bool _dragging = false;
  double _dragMs = 0;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    final padH = widget.fullscreen ? 96.0 : 64.0;
    final padT = widget.fullscreen ? 72.0 : 56.0;

    // Square artwork sized off whichever constraint binds first, so it stays a
    // square card rather than stretching with the window.
    final artSize = (screen.height * (widget.fullscreen ? 0.58 : 0.52))
        .clamp(220.0, 720.0);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Stack(
        children: [
          Positioned.fill(child: _buildBackground()),
          Positioned.fill(
            child: IgnorePointer(
              child: Container(color: Colors.black.withValues(alpha: 0.74)),
            ),
          ),
          Positioned(top: 12, right: 16, child: _Toolbar(onSettings: widget.onSettings)),
          SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(padH, padT, padH, 40),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 44, child: _buildLeftColumn(artSize)),
                  const SizedBox(width: 56),
                  Expanded(flex: 56, child: widget.lyrics),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackground() {
    return ValueListenableBuilder<bool>(
      valueListenable: SettingsService().performanceModeEnabled,
      builder: (context, performanceMode, _) {
        return BackgroundController(
          albumArtBytes: widget.mediaState.albumArtBytes,
          forceStatic: performanceMode,
        );
      },
    );
  }

  Widget _buildLeftColumn(double artSize) {
    final state = widget.mediaState;

    return Column(
      children: [
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildArtwork(artSize),
                  const SizedBox(height: 34),
                  Text(
                    state.title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Display',
                      fontFamilyFallback: kGlobalFontFallbacks,
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                      letterSpacing: -0.4,
                    ),
                  ),
                  if (_subtitle(state).isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      _subtitle(state),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Display',
                        fontFamilyFallback: kGlobalFontFallbacks,
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 17,
                        fontWeight: FontWeight.w400,
                        height: 1.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        _buildControls(),
      ],
    );
  }

  /// "Artist — Album" when an album is known, matching the reference layout.
  static String _subtitle(MediaState state) {
    final artist = state.artist.trim();
    final album = state.album?.trim() ?? '';
    if (artist.isEmpty) return album;
    if (album.isEmpty) return artist;
    return '$artist — $album';
  }

  Widget _buildArtwork(double artSize) {
    final state = widget.mediaState;
    final bytes = state.albumArtBytes ?? state.thumbnailArtBytes;

    final Widget staticArt = bytes != null && bytes.isNotEmpty
        ? Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true)
        : Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF2A2A2A), Color(0xFF151515)],
              ),
            ),
            child: const Center(
              child:
                  Icon(Icons.music_note_rounded, size: 72, color: Colors.white24),
            ),
          );

    // Only the square live artwork is used here: the tall variant is a
    // full-bleed background and would not read as cover art in a square card.
    return Container(
      width: artSize,
      height: artSize,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 48,
            spreadRadius: 4,
            offset: const Offset(0, 24),
          ),
        ],
      ),
      child: ValueListenableBuilder<bool>(
        valueListenable: SettingsService().animatedArtworkEnabled,
        builder: (context, animatedEnabled, _) {
          final squareUrl = state.squareMasterUrl;
          final useLive = animatedEnabled &&
              squareUrl != null &&
              squareUrl.isNotEmpty;

          if (!useLive) return staticArt;
          return AnimatedArtworkPlayer(
            key: ValueKey('split_art_$squareUrl'),
            url: squareUrl,
            placeholder: staticArt,
            fit: BoxFit.cover,
          );
        },
      ),
    );
  }

  Widget _buildControls() {
    final state = widget.mediaState;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildSeekBar(),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _TransportGlyph(
              icon: Icons.skip_previous_rounded,
              onTap: () => widget.service.previous(),
            ),
            const SizedBox(width: 44),
            _TransportGlyph(
              icon: state.isPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              size: 44,
              onTap: () => state.isPlaying
                  ? widget.service.pause()
                  : widget.service.play(),
            ),
            const SizedBox(width: 44),
            _TransportGlyph(
              icon: Icons.skip_next_rounded,
              onTap: () => widget.service.next(),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSeekBar() {
    final durationMs = widget.mediaState.duration.inMilliseconds.toDouble();
    final maxVal = durationMs > 0 ? durationMs : 1.0;

    return ValueListenableBuilder<Duration>(
      valueListenable: widget.positionNotifier,
      builder: (context, visualPosition, _) {
        final currentVal =
            (_dragging ? _dragMs : visualPosition.inMilliseconds.toDouble())
                .clamp(0.0, maxVal);

        return Column(
          children: [
            SliderTheme(
              data: SliderThemeData(
                trackHeight: 5,
                trackShape: const RoundedRectSliderTrackShape(),
                thumbShape: SliderComponentShape.noThumb,
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 0),
                activeTrackColor: Colors.white,
                inactiveTrackColor: Colors.white.withValues(alpha: 0.16),
              ),
              child: Slider(
                value: currentVal,
                min: 0.0,
                max: maxVal,
                onChanged: (value) {
                  setState(() {
                    _dragging = true;
                    _dragMs = value;
                  });
                  widget.onPositionPreviewing(true);
                  widget.onPositionPreview(
                      Duration(milliseconds: value.toInt()));
                },
                onChangeEnd: (value) {
                  setState(() => _dragging = false);
                  widget.onPositionPreviewing(false);
                  widget.service.seekTo(Duration(milliseconds: value.toInt()));
                },
              ),
            ),
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatDuration(currentVal),
                    style: _timeStyle,
                  ),
                  Text(
                    '-${_formatDuration((maxVal - currentVal).clamp(0.0, maxVal))}',
                    style: _timeStyle,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  static TextStyle get _timeStyle => TextStyle(
        color: Colors.white.withValues(alpha: 0.55),
        fontSize: 13,
        fontWeight: FontWeight.w600,
        fontFamily: 'Display',
        fontFamilyFallback: kGlobalFontFallbacks,
      );

  static String _formatDuration(double ms) {
    final total = (ms / 1000).round();
    final minutes = total ~/ 60;
    final seconds = total % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

/// Settings / mini player / fullscreen controls, floating top-right.
class _Toolbar extends StatelessWidget {
  final VoidCallback onSettings;

  const _Toolbar({required this.onSettings});

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToolButton(
            icon: Icons.settings_outlined,
            tooltip: 'Settings',
            onTap: onSettings,
          ),
          _ToolButton(
            icon: WindowService.isCompact
                ? Icons.close_fullscreen_rounded
                : Icons.picture_in_picture_alt_rounded,
            tooltip: 'Mini player (Ctrl+M)',
            onTap: WindowService.toggleCompact,
          ),
          _ToolButton(
            icon: WindowService.isFullscreen
                ? Icons.fullscreen_exit_rounded
                : Icons.fullscreen_rounded,
            tooltip: 'Fullscreen (F11)',
            onTap: WindowService.toggleFullscreen,
          ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _ToolButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      icon: Icon(icon, size: 22, color: Colors.white60),
      hoverColor: Colors.white.withValues(alpha: 0.10),
      highlightColor: Colors.white.withValues(alpha: 0.16),
      splashRadius: 22,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
    );
  }
}

class _TransportGlyph extends StatelessWidget {
  final IconData icon;
  final double size;
  final VoidCallback onTap;

  const _TransportGlyph({
    required this.icon,
    required this.onTap,
    this.size = 32,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: size, color: Colors.white),
      color: Colors.white,
      hoverColor: Colors.white.withValues(alpha: 0.10),
      highlightColor: Colors.white.withValues(alpha: 0.16),
      splashRadius: 28,
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      padding: EdgeInsets.zero,
    );
  }
}
