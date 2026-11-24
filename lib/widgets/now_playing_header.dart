import 'package:simple_lyrics/core/font_fallbacks.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../core/settings_route.dart';
import '../models/media_state.dart';
import '../screens/settings_screen.dart';
import '../services/media_session_service.dart';
import '../services/settings_service.dart';
import '../services/window_service.dart';
import 'full_screen_artwork.dart';
import 'animated_artwork_player.dart';

/// Header widget displaying album artwork, song title, and artist name.
///
/// Uses [AnimatedSwitcher] for smooth cross-fade transitions
/// when the currently playing track changes.
class NowPlayingHeader extends StatelessWidget {
  final MediaState mediaState;
  final MediaSessionService service;
  final VoidCallback? onSettingsClosed;

  const NowPlayingHeader({
    super.key,
    required this.mediaState,
    required this.service,
    this.onSettingsClosed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
      // Removed the heavy dark gradient at the top. Apple Music relies 
      // entirely on the fluid blurred background for depth.
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            // Album artwork (Letting Image.memory gaplessPlayback handle transitions natively without popping)
            _buildAlbumArt(
              context,
              mediaState.thumbnailArtBytes ?? mediaState.albumArtBytes,
            ),
            const SizedBox(width: 18),
            // Song info
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
                  return Stack(
                    alignment: Alignment.centerLeft,
                    children: <Widget>[
                      ...previousChildren,
                      ?currentChild,
                    ],
                  );
                },
                child: _buildSongInfo(
                  mediaState.title,
                  mediaState.artist,
                ),
              ),
            ),
            // Desktop window controls. Both are Windows-only: the window
            // itself is what changes, and neither means anything on a phone.
            if (WindowService.isSupported) ...[
              IconButton(
                onPressed: () => WindowService.toggleCompact(),
                tooltip: 'Mini player (Ctrl+M)',
                icon: Icon(
                  WindowService.isCompact
                      ? Icons.close_fullscreen_rounded
                      : Icons.picture_in_picture_alt_rounded,
                  color: Colors.white54,
                  size: 22,
                ),
                visualDensity: VisualDensity.compact,
                splashRadius: 24,
              ),
              IconButton(
                onPressed: () => WindowService.toggleFullscreen(),
                tooltip: 'Fullscreen (F11)',
                icon: Icon(
                  WindowService.isFullscreen
                      ? Icons.fullscreen_exit_rounded
                      : Icons.fullscreen_rounded,
                  color: Colors.white54,
                  size: 26,
                ),
                visualDensity: VisualDensity.compact,
                splashRadius: 24,
              ),
            ],
            // Settings Button
            const SizedBox(width: 12),
            IconButton(
              onPressed: () {
                Navigator.of(context)
                    .push(buildSettingsRoute(SettingsScreen(service: service)))
                    .then((_) => onSettingsClosed?.call());
              },
              icon: const Icon(
                Icons.settings_outlined,
                color: Colors.white54,
                size: 24,
              ),
              visualDensity: VisualDensity.compact,
              splashRadius: 24,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlbumArt(BuildContext context, Uint8List? artBytes) {
    return GestureDetector(
      onTap: () async {
        final showBg = SettingsService().showBackgroundInFullScreenArtwork.value;
        SettingsService().isFullScreenArtworkOpen.value = true;
        await Navigator.of(context).push(
          PageRouteBuilder(
            opaque: false,
            barrierColor: showBg ? Colors.transparent : Colors.black.withValues(alpha: 0.8),
            transitionDuration: const Duration(milliseconds: 550),
            reverseTransitionDuration: const Duration(milliseconds: 450),
            pageBuilder: (context, _, _) => FullScreenArtwork(
              artBytes: mediaState.albumArtBytes ?? mediaState.thumbnailArtBytes,
              title: mediaState.title,
              artist: mediaState.artist,
              mediaState: mediaState,
              service: service,
            ),
            transitionsBuilder: (context, animation, _, child) {
              final fadeAnimation = CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
                reverseCurve: Curves.easeInCubic,
              );
              return FadeTransition(
                opacity: fadeAnimation,
                child: RepaintBoundary(child: child),
              );
            },
          ),
        );
        SettingsService().isFullScreenArtworkOpen.value = false;
      },
      child: Hero(
        tag: 'album_art',
        flightShuttleBuilder: (context, animation, direction, fromContext, toContext) {
          const shadow = BoxShadow(
            color: Color.fromARGB(64, 0, 0, 0),
            blurRadius: 16,
            offset: Offset(0, 8),
          );

          final flightArt = artBytes != null && artBytes.isNotEmpty
              ? Image.memory(
                  artBytes,
                  fit: BoxFit.cover,
                  cacheWidth: 512,
                  cacheHeight: 512,
                  gaplessPlayback: true,
                )
              : Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Colors.grey.shade800, Colors.grey.shade900],
                    ),
                  ),
                  child: const Icon(Icons.music_note_rounded, color: Colors.white38),
                );

          return Center(
            child: AspectRatio(
              aspectRatio: 1.0,
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: animation,
                  child: flightArt,
                  builder: (context, child) {
                    // Lerp radius between small (8) and large (12)
                    final radius = 8.0 + (12.0 - 8.0) * animation.value;

                    return Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(radius),
                        boxShadow: const [shadow],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: SizedBox.expand(child: child),
                    );
                  },
                ),
              ),
            ),
          );
        },
        child: Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: ValueListenableBuilder<bool>(
            valueListenable: SettingsService().animatedArtworkEnabled,
            builder: (context, enabled, _) {
              final hasSquareUrl = mediaState.squareMasterUrl != null && mediaState.squareMasterUrl!.isNotEmpty;
              final isLiveActive = enabled && hasSquareUrl;

              final placeholder = artBytes != null && artBytes.isNotEmpty
                  ? Image.memory(
                      artBytes,
                      key: const ValueKey('static_art'),
                      fit: BoxFit.cover,
                      cacheWidth: 300,
                      cacheHeight: 300,
                      filterQuality: FilterQuality.high,
                      gaplessPlayback: true,
                    )
                  : Container(
                      key: const ValueKey('static_placeholder'),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Colors.grey.shade800, Colors.grey.shade900],
                        ),
                      ),
                      child: const Icon(Icons.music_note_rounded, color: Colors.white38, size: 36),
                    );

              return AnimatedSwitcher(
                duration: const Duration(milliseconds: 600),
                switchInCurve: Curves.easeIn,
                switchOutCurve: Curves.easeOut,
                child: isLiveActive
                    ? AnimatedArtworkPlayer(
                        key: ValueKey('live_art_${mediaState.squareMasterUrl}'),
                        url: mediaState.squareMasterUrl!,
                        placeholder: placeholder,
                        fit: BoxFit.cover,
                      )
                    : SizedBox.expand(
                        key: const ValueKey('static_art_wrapper'),
                        child: placeholder,
                      ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSongInfo(String title, String artist) {
    return Column(
      key: ValueKey('$title-$artist'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          type: MaterialType.transparency,
          child: _MarqueeText(
            text: title,
            style: const TextStyle(
              fontFamily: 'Display', fontFamilyFallback: kGlobalFontFallbacks,
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              height: 1.1,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Material(
          type: MaterialType.transparency,
          child: _MarqueeText(
            text: artist,
            style: TextStyle(
              fontFamily: 'Display', fontFamilyFallback: kGlobalFontFallbacks,
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 16,
              fontWeight: FontWeight.w400,
              letterSpacing: -0.2,
            ),
          ),
        ),
      ],
    );
  }
}

class _MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;

  const _MarqueeText({required this.text, required this.style});

  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText> {
  late final ScrollController _scrollController;
  bool _needsScroll = false;
  bool _isScrolling = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkScroll());
  }

  @override
  void didUpdateWidget(_MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _isScrolling = false;
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkScroll());
    }
  }

  void _checkScroll() {
    if (!mounted || !_scrollController.hasClients) return;
    final maxExtent = _scrollController.position.maxScrollExtent;
    if (maxExtent > 0) {
      if (!_needsScroll) {
        setState(() => _needsScroll = true);
        _startScroll();
      }
    } else {
      if (_needsScroll) {
        setState(() => _needsScroll = false);
      }
    }
  }

  void _startScroll() async {
    if (_isScrolling) return;
    _isScrolling = true;
    while (_needsScroll && mounted) {
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted || !_needsScroll) break;
      
      final maxExtent = _scrollController.position.maxScrollExtent;
      final duration = Duration(milliseconds: (maxExtent * 35).toInt()); // Slow, readable speed
      
      await _scrollController.animateTo(
        maxExtent,
        duration: duration,
        curve: Curves.linear,
      );
      
      if (!mounted || !_needsScroll) break;
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted || !_needsScroll) break;
      
      if (_scrollController.hasClients) {
        // Animate smoothly back to the beginning (ping-pong)
        await _scrollController.animateTo(
          0,
          duration: duration,
          curve: Curves.linear,
        );
      }
    }
    _isScrolling = false;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      child: Text(
        widget.text,
        style: widget.style,
        maxLines: 1,
      ),
    );
  }
}
