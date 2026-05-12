import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';

class FullScreenArtwork extends StatelessWidget {
  final Uint8List? artBytes;
  final String title;
  final String artist;

  const FullScreenArtwork({
    super.key,
    required this.artBytes,
    required this.title,
    required this.artist,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size.width * 0.85;

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
                        child: artBytes != null && artBytes!.isNotEmpty
                            ? Image.memory(
                                artBytes!,
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
                            title,
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
                          artist,
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
        ],
      ),
    );
  }
}
