import 'package:flutter/material.dart';
import '../services/cache_service.dart';
import '../services/media_session_service.dart';

class CacheScreen extends StatefulWidget {
  final MediaSessionService service;
  const CacheScreen({super.key, required this.service});

  @override
  State<CacheScreen> createState() => _CacheScreenState();
}

class _CacheScreenState extends State<CacheScreen> {
  Map<String, dynamic> _cacheIndex = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCache();
  }

  Future<void> _loadCache() async {
    await CacheService.syncIndexWithFiles();
    final index = await CacheService.getIndex();
    if (mounted) {
      setState(() {
        _cacheIndex = index;
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteSong(String key) async {
    await CacheService.clearSong(key);
    _loadCache();
  }

  @override
  Widget build(BuildContext context) {
    final sortedKeys = _cacheIndex.keys.toList()
      ..sort((a, b) => (_cacheIndex[b]['timestamp'] ?? 0)
          .compareTo(_cacheIndex[a]['timestamp'] ?? 0));

    return Scaffold(
      backgroundColor: Colors.black,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: Colors.black,
            floating: true,
            pinned: true,
            elevation: 0,
            automaticallyImplyLeading: false,
            title: const Text(
              'Manage Cache',
              style: TextStyle(
                fontFamily: 'Display',
                fontSize: 22,
                color: Colors.white,
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white70),
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 8),
            ],
          ),
          if (_isLoading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator(color: Colors.white24)),
            )
          else if (sortedKeys.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.folder_off_rounded, size: 64, color: Colors.white.withValues(alpha: 0.1)),
                    const SizedBox(height: 16),
                    Text(
                      'No saved songs yet',
                      style: TextStyle(
                        fontFamily: 'Display',
                        color: Colors.white.withValues(alpha: 0.3),
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final key = sortedKeys[index];
                    final item = _cacheIndex[key];
                    final title = item['title'] ?? 'Unknown Title';
                    final artist = item['artist'] ?? 'Unknown Artist';

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          FutureBuilder<CachedArtworkBytes?>(
                            future: CacheService.readArtwork(key),
                            builder: (context, snapshot) {
                              final bytes = snapshot.data?.smallBytes;
                              return Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  color: Colors.white10,
                                  borderRadius: BorderRadius.circular(8),
                                  image: bytes != null
                                      ? DecorationImage(
                                          image: MemoryImage(bytes),
                                          fit: BoxFit.cover,
                                        )
                                      : null,
                                ),
                                child: bytes == null
                                    ? const Icon(Icons.music_note_rounded, color: Colors.white24)
                                    : null,
                              );
                            },
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'Display',
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  artist,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.5),
                                    fontSize: 14,
                                    fontFamily: 'Display',
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                            onPressed: () => _deleteSong(key),
                          ),
                        ],
                      ),
                    );
                  },
                  childCount: sortedKeys.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
