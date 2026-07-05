import 'package:simple_lyrics/core/font_fallbacks.dart';
import 'package:flutter/material.dart';
import '../services/cache_service.dart';
import '../widgets/pie_chart_3d.dart';

class CacheSummaryScreen extends StatefulWidget {
  const CacheSummaryScreen({super.key});

  @override
  State<CacheSummaryScreen> createState() => _CacheSummaryScreenState();
}

class _CacheSummaryScreenState extends State<CacheSummaryScreen> {
  late Future<CacheBreakdown> _breakdownFuture;

  @override
  void initState() {
    super.initState();
    _breakdownFuture = CacheService.getCacheBreakdown();
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text(
          'Cache Summary',
          style: TextStyle(fontFamily: 'Display', fontFamilyFallback: kGlobalFontFallbacks, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: FutureBuilder<CacheBreakdown>(
        future: _breakdownFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.white54));
          }

          final breakdown = snapshot.data ?? const CacheBreakdown(lyricsBytes: 0, artworkImagesBytes: 0, liveArtworkLinkBytes: 0);
          final totalBytes = breakdown.totalBytes;

          if (totalBytes == 0) {
            return const Center(
              child: Text(
                'Cache is completely empty',
                style: TextStyle(color: Colors.white54, fontSize: 16),
              ),
            );
          }

          // Enforce minimum slice values for visibility (so tiny JSON files aren't invisible)
          // Minimum slice size is 5% of total mathematically for rendering only.
          final double minSliceSize = totalBytes * 0.05;
          final double renderLyrics = breakdown.lyricsBytes > 0 && breakdown.lyricsBytes < minSliceSize ? minSliceSize : breakdown.lyricsBytes.toDouble();
          final double renderArt = breakdown.artworkImagesBytes > 0 && breakdown.artworkImagesBytes < minSliceSize ? minSliceSize : breakdown.artworkImagesBytes.toDouble();
          final double renderLinks = breakdown.liveArtworkLinkBytes > 0 && breakdown.liveArtworkLinkBytes < minSliceSize ? minSliceSize : breakdown.liveArtworkLinkBytes.toDouble();

          final slices = [
            if (breakdown.artworkImagesBytes > 0)
              PieSlice3D(
                value: renderArt,
                color: const Color(0xFF2196F3), // Apple Music Blueish
              ),
            if (breakdown.lyricsBytes > 0)
              PieSlice3D(
                value: renderLyrics,
                color: const Color(0xFF4CAF50), // Green
              ),
            if (breakdown.liveArtworkLinkBytes > 0)
              PieSlice3D(
                value: renderLinks,
                color: const Color(0xFFE91E63), // Pink
              ),
          ];

          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 20),
                  // 3D Pie Chart Container
                  Container(
                    height: 300,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                    ),
                    padding: const EdgeInsets.all(20),
                    child: PieChart3D(
                      slices: slices,
                      height: 35.0, // 3D Extrusion depth
                    ),
                  ),
                  const SizedBox(height: 40),
                  const Text(
                    'Breakdown',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontFamily: 'Display', fontFamilyFallback: kGlobalFontFallbacks,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildLegendItem(
                    color: const Color(0xFF2196F3),
                    title: 'Static Artworks',
                    bytes: breakdown.artworkImagesBytes,
                    total: totalBytes,
                  ),
                  _buildLegendItem(
                    color: const Color(0xFF4CAF50),
                    title: 'Cached Lyrics',
                    bytes: breakdown.lyricsBytes,
                    total: totalBytes,
                  ),
                  _buildLegendItem(
                    color: const Color(0xFFE91E63),
                    title: 'Live Artwork Links',
                    bytes: breakdown.liveArtworkLinkBytes,
                    total: totalBytes,
                  ),
                  const SizedBox(height: 30),
                  Center(
                    child: RichText(
                      text: TextSpan(
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 16,
                          fontFamily: 'Display', fontFamilyFallback: kGlobalFontFallbacks,
                        ),
                        children: [
                          const TextSpan(text: 'Total Space Used: '),
                          TextSpan(
                            text: _formatBytes(totalBytes),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLegendItem({
    required Color color,
    required String title,
    required int bytes,
    required int total,
  }) {
    if (bytes == 0) return const SizedBox.shrink();

    final percentage = ((bytes / total) * 100).toStringAsFixed(1);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white, 
                fontSize: 16,
                fontFamily: 'Display', fontFamilyFallback: kGlobalFontFallbacks,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatBytes(bytes),
                style: const TextStyle(
                  color: Colors.white, 
                  fontSize: 16, 
                  fontFamily: 'Display', fontFamilyFallback: kGlobalFontFallbacks,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                '$percentage%',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5), 
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
