import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:video_player/video_player.dart';

import '../core/platform_capabilities.dart';

/// A premium, self-contained video player for HLS animated artwork.
/// Streams looping, muted videos and handles seamless transitions between tracks.
class AnimatedArtworkPlayer extends StatefulWidget {
  final String url;
  final Widget placeholder;
  final BoxFit fit;
  final Alignment alignment;
  final bool enableCrossFade;

  const AnimatedArtworkPlayer({
    super.key,
    required this.url,
    required this.placeholder,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.enableCrossFade = true,
  });

  @override
  State<AnimatedArtworkPlayer> createState() => _AnimatedArtworkPlayerState();
}

class _AnimatedArtworkPlayerState extends State<AnimatedArtworkPlayer> {
  static final Map<String, VideoPlayerController> _controllerCache = {};
  static final Map<String, int> _refCount = {};

  VideoPlayerController? _controller;
  VideoPlayerController? _oldController;
  bool _isInitialized = false;
  bool _showNewVideo = false;

  @override
  void initState() {
    super.initState();
    _initializePlayer(widget.url);
  }

  @override
  void didUpdateWidget(covariant AnimatedArtworkPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.url != oldWidget.url) {
      _transitionToNewUrl(widget.url);
    }
  }

  Future<void> _initializePlayer(String url) async {
    if (url.isEmpty) return;

    // video_player has no Windows backend, so fall back to the static
    // placeholder rather than throwing MissingPluginException.
    if (!supportsVideoPlayback) return;

    VideoPlayerController controller;
    bool isNew = false;

    if (_controllerCache.containsKey(url)) {
      controller = _controllerCache[url]!;
      _refCount[url] = (_refCount[url] ?? 0) + 1;
    } else {
      controller = VideoPlayerController.networkUrl(
        Uri.parse(url),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      _controllerCache[url] = controller;
      _refCount[url] = 1;
      isNew = true;
    }

    _controller = controller;

    try {
      if (isNew) {
        await controller.initialize();
        if (!mounted || _controller != controller) {
          _disposeController(url, controller);
          return;
        }
        await controller.setLooping(true);
        await controller.setVolume(0.0);
        await controller.play();
      } else if (!controller.value.isInitialized) {
        // Wait for the other instance to finish initializing it
        while (!controller.value.isInitialized && mounted && _controller == controller) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }

      if (mounted && _controller == controller) {
        setState(() {
          _isInitialized = true;
          _showNewVideo = true;
        });
      }

      // Safely dispose old controller after transition is done
      if (_oldController != null) {
        final oldUrl = widget.url; // We need the old URL to decrement ref count. Wait, widget.url is the NEW url here!
        // Actually, we can just store the old url in a variable when transitioning
      }
    } catch (e) {
      // ignore: avoid_print
      print("AnimatedArtworkPlayer initialization error: $e");
      if (mounted && _controller == controller) {
        setState(() {
          _isInitialized = false;
        });
      }
      _disposeController(url, controller);
    }
  }

  void _disposeController(String url, VideoPlayerController controller) {
    if (_refCount.containsKey(url)) {
      _refCount[url] = _refCount[url]! - 1;
      if (_refCount[url]! <= 0) {
        controller.dispose();
        _controllerCache.remove(url);
        _refCount.remove(url);
      }
    } else {
      controller.dispose();
    }
  }

  String? _oldUrl;

  void _transitionToNewUrl(String newUrl) {
    if (!supportsVideoPlayback) return;

    if (!widget.enableCrossFade) {
      if (_controller != null) {
        _disposeController(widget.url, _controller!);
        _controller = null;
      }
      _oldController = null;
      _isInitialized = false;
      _showNewVideo = true;
      _initializePlayer(newUrl);
      return;
    }
    // Save current as old controller for cross-fade
    if (_controller != null && _isInitialized) {
      _oldController = _controller;
      _oldUrl = widget.url; // store the old URL for proper disposal
      _showNewVideo = false;

      // Dispose it after fade
      final urlToDispose = _oldUrl!;
      final ctrlToDispose = _oldController!;
      _oldController = null;
      Future.delayed(const Duration(milliseconds: 600), () {
        _disposeController(urlToDispose, ctrlToDispose);
      });

    } else if (_controller != null) {
      _disposeController(widget.url, _controller!);
      _controller = null;
    }

    _isInitialized = false;
    _initializePlayer(newUrl);
  }

  @override
  void dispose() {
    if (_controller != null) {
      _disposeController(widget.url, _controller!);
    }
    if (_oldController != null && _oldUrl != null) {
      _disposeController(_oldUrl!, _oldController!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Desktop has no video_player implementation, so HLS artwork is rendered by
    // media_kit instead. Keying on the URL makes a track change tear down and
    // rebuild the decoder, which avoids showing the previous track's frames
    // over the new one.
    if (supportsAnimatedArtwork) {
      if (widget.url.isEmpty) return widget.placeholder;
      return _MediaKitArtwork(
        key: ValueKey('media_kit_artwork:${widget.url}'),
        url: widget.url,
        placeholder: widget.placeholder,
        fit: widget.fit,
        alignment: widget.alignment,
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. Static Placeholder is always at the bottom
        widget.placeholder,

        if (!widget.enableCrossFade && _controller != null && _isInitialized)
          SizedBox.expand(
            child: FittedBox(
              fit: widget.fit,
              alignment: widget.alignment,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: _controller!.value.size.width,
                height: _controller!.value.size.height,
                child: VideoPlayer(_controller!),
              ),
            ),
          ),

        // 2. Old Video playing during cross-fade transition
        if (widget.enableCrossFade && _oldController != null && _oldController!.value.isInitialized)
          AnimatedOpacity(
            opacity: _showNewVideo ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
            child: SizedBox.expand(
              child: FittedBox(
                fit: widget.fit,
                alignment: widget.alignment,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: _oldController!.value.size.width,
                  height: _oldController!.value.size.height,
                  child: VideoPlayer(_oldController!),
                ),
              ),
            ),
          ),

        // 3. New Video fading in once initialized
        if (widget.enableCrossFade && _controller != null && _isInitialized)
          AnimatedOpacity(
            opacity: _showNewVideo ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
            child: SizedBox.expand(
              child: FittedBox(
                fit: widget.fit,
                alignment: widget.alignment,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: _controller!.value.size.width,
                  height: _controller!.value.size.height,
                  child: VideoPlayer(_controller!),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Desktop animated-artwork renderer backed by media_kit (libmpv).
///
/// [video_player] ships no Windows implementation, so on Windows this is the
/// only path that can play Apple Music's animated artwork. The static artwork
/// stays underneath so the box is never empty while the stream buffers.
class _MediaKitArtwork extends StatefulWidget {
  final String url;
  final Widget placeholder;
  final BoxFit fit;
  final Alignment alignment;

  const _MediaKitArtwork({
    super.key,
    required this.url,
    required this.placeholder,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
  });

  @override
  State<_MediaKitArtwork> createState() => _MediaKitArtworkState();
}

class _MediaKitArtworkState extends State<_MediaKitArtwork> {
  Player? _player;
  VideoController? _controller;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    final player = Player();

    try {
      await player.open(Media(widget.url), play: true);
      // The source music app owns the audio; artwork is purely decorative.
      await player.setVolume(0.0);
      await player.setPlaylistMode(PlaylistMode.loop);
    } catch (e) {
      debugPrint('AnimatedArtworkPlayer media_kit error: $e');
      await player.dispose();
      if (mounted) {
        setState(() => _failed = true);
      }
      return;
    }

    if (!mounted) {
      await player.dispose();
      return;
    }

    setState(() {
      _player = player;
      _controller = VideoController(player);
      _ready = true;
    });
  }

  @override
  void dispose() {
    final player = _player;
    _player = null;
    _controller = null;
    if (player != null) {
      // Fire and forget: awaiting inside dispose would delay the next track.
      player.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed || !_ready || _controller == null) {
      return widget.placeholder;
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Static artwork underneath, so there is never a blank frame while the
        // HLS stream fills its buffer.
        widget.placeholder,
        Video(
          controller: _controller!,
          fit: widget.fit,
          alignment: widget.alignment,
          // Transparent so the placeholder shows through until the first frame
          // arrives, instead of flashing black over it.
          fill: Colors.transparent,
          controls: null,
          wakelock: false,
        ),
      ],
    );
  }
}
