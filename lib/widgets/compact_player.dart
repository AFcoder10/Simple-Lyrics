import 'package:flutter/material.dart';

import '../core/font_fallbacks.dart';
import '../models/media_state.dart';
import '../services/media_session_service.dart';
import '../services/settings_service.dart';
import '../services/window_service.dart';
import 'backgrounds/background_controller.dart';

/// The single-pane floating mini player: a small always-on-top window with just
/// enough chrome to identify the track, read the lyrics and reach the
/// transport — meant to sit over other applications rather than be the app.
///
/// Artwork is deliberately a small thumbnail here instead of a pane: at 400px
/// wide a cover card would leave nothing for the lyrics, which are the whole
/// point of a player you leave parked on screen.
class CompactPlayer extends StatefulWidget {
  final MediaState mediaState;
  final MediaSessionService service;
  final Widget lyrics;
  final ValueNotifier<Duration> positionNotifier;
  final VoidCallback onSettings;
  final void Function(Duration) onPositionPreview;
  final void Function(bool) onPositionPreviewing;

  const CompactPlayer({
    super.key,
    required this.mediaState,
    required this.service,
    required this.lyrics,
    required this.positionNotifier,
    required this.onSettings,
    required this.onPositionPreview,
    required this.onPositionPreviewing,
  });

  @override
  State<CompactPlayer> createState() => _CompactPlayerState();
}

class _CompactPlayerState extends State<CompactPlayer> {
  bool _dragging = false;
  double _dragMs = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Stack(
        children: [
          Positioned.fill(child: _buildBackground()),
          Positioned.fill(
            child: IgnorePointer(
              child: Container(color: Colors.black.withValues(alpha: 0.72)),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
              child: Column(
                children: [
                  _buildHeader(),
                  const SizedBox(height: 18),
                  Expanded(child: widget.lyrics),
                  const SizedBox(height: 12),
                  _buildControls(),
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

  Widget _buildHeader() {
    final state = widget.mediaState;
    final bytes = state.albumArtBytes ?? state.thumbnailArtBytes;

    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 52,
            height: 52,
            child: bytes != null && bytes.isNotEmpty
                ? Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true)
                : Container(
                    color: Colors.white.withValues(alpha: 0.06),
                    child: const Icon(Icons.music_note_rounded,
                        color: Colors.white30, size: 26),
                  ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                state.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Display',
                  fontFamilyFallback: kGlobalFontFallbacks,
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              if (state.artist.trim().isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  state.artist.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Display',
                    fontFamilyFallback: kGlobalFontFallbacks,
                    color: Colors.white.withValues(alpha: 0.66),
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: widget.onSettings,
          tooltip: 'Settings',
          icon: const Icon(Icons.settings_outlined,
              color: Colors.white54, size: 20),
          hoverColor: Colors.white.withValues(alpha: 0.10),
          splashRadius: 20,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        ),
        IconButton(
          onPressed: WindowService.toggleFullscreen,
          tooltip: 'Fullscreen (F11)',
          icon: const Icon(Icons.fullscreen_rounded,
              color: Colors.white54, size: 22),
          hoverColor: Colors.white.withValues(alpha: 0.10),
          splashRadius: 20,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        ),
        IconButton(
          onPressed: () => WindowService.setMode(WindowMode.windowed),
          tooltip: 'Back to main window',
          icon: const Icon(Icons.open_in_full_rounded,
              color: Colors.white54, size: 18),
          hoverColor: Colors.white.withValues(alpha: 0.10),
          splashRadius: 20,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        ),
      ],
    );
  }

  Widget _buildControls() {
    final state = widget.mediaState;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildSeekBar(),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _Glyph(
              icon: Icons.skip_previous_rounded,
              onTap: () => widget.service.previous(),
            ),
            const SizedBox(width: 36),
            _Glyph(
              icon:
                  state.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 38,
              onTap: () => state.isPlaying
                  ? widget.service.pause()
                  : widget.service.play(),
            ),
            const SizedBox(width: 36),
            _Glyph(
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
                trackHeight: 4,
                trackShape: const RoundedRectSliderTrackShape(),
                thumbShape: SliderComponentShape.noThumb,
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 0),
                activeTrackColor: Colors.white,
                inactiveTrackColor: Colors.white.withValues(alpha: 0.18),
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_format(currentVal), style: _timeStyle),
                  Text(
                    '-${_format((maxVal - currentVal).clamp(0.0, maxVal))}',
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
        fontSize: 11,
        fontWeight: FontWeight.w600,
        fontFamily: 'Display',
        fontFamilyFallback: kGlobalFontFallbacks,
      );

  static String _format(double ms) {
    final total = (ms / 1000).round();
    return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
  }
}

class _Glyph extends StatelessWidget {
  final IconData icon;
  final double size;
  final VoidCallback onTap;

  const _Glyph({required this.icon, required this.onTap, this.size = 30});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: size, color: Colors.white),
      hoverColor: Colors.white.withValues(alpha: 0.10),
      highlightColor: Colors.white.withValues(alpha: 0.16),
      splashRadius: 24,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      padding: EdgeInsets.zero,
    );
  }
}
