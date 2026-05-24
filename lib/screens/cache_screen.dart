import 'package:flutter/material.dart';
import '../services/cache_service.dart';
import '../services/media_session_service.dart';

enum _CacheSortMode { recent, title, artist }

class CacheScreen extends StatefulWidget {
  final MediaSessionService service;
  const CacheScreen({super.key, required this.service});

  @override
  State<CacheScreen> createState() => _CacheScreenState();
}

class _CacheScreenState extends State<CacheScreen> {
  Map<String, dynamic> _cacheIndex = {};
  bool _isLoading = true;
  int _cacheSizeBytes = 0;
  _CacheSortMode _sortMode = _CacheSortMode.recent;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCache();
  }

  Future<void> _loadCache() async {
    await CacheService.syncIndexWithFiles();
    final index = await CacheService.getIndex();
    final sizeBytes = await CacheService.cacheSizeBytes();
    if (mounted) {
      setState(() {
        _cacheIndex = index;
        _cacheSizeBytes = sizeBytes;
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteSong(String key) async {
    await CacheService.clearSong(key);
    _loadCache();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final sortedKeys = _cacheIndex.keys.where((key) {
      final item = _cacheIndex[key] as Map<String, dynamic>? ?? {};
      final title = (item['title'] ?? '').toString().toLowerCase();
      final artist = (item['artist'] ?? '').toString().toLowerCase();
      return query.isEmpty || title.contains(query) || artist.contains(query);
    }).toList()
      ..sort((a, b) {
        final aItem = _cacheIndex[a] as Map<String, dynamic>? ?? {};
        final bItem = _cacheIndex[b] as Map<String, dynamic>? ?? {};
        switch (_sortMode) {
          case _CacheSortMode.title:
            return (aItem['title'] ?? '').toString().toLowerCase()
                .compareTo((bItem['title'] ?? '').toString().toLowerCase());
          case _CacheSortMode.artist:
            return (aItem['artist'] ?? '').toString().toLowerCase()
                .compareTo((bItem['artist'] ?? '').toString().toLowerCase());
          case _CacheSortMode.recent:
            final aTime = aItem['timestamp'] is int ? aItem['timestamp'] as int : 0;
            final bTime = bItem['timestamp'] is int ? bItem['timestamp'] as int : 0;
            return bTime.compareTo(aTime);
        }
      });

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
          else ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _searchController,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Search songs or artists',
                        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
                        prefixIcon: const Icon(Icons.search_rounded, color: Colors.white38),
                        suffixIcon: query.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close_rounded, color: Colors.white38),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {});
                                },
                              ),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.06),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${sortedKeys.length} of ${_cacheIndex.length} songs / ${_formatBytes(_cacheSizeBytes)}',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.42),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        _buildSortChip('Recent', _CacheSortMode.recent),
                        const SizedBox(width: 6),
                        _buildSortChip('Title', _CacheSortMode.title),
                        const SizedBox(width: 6),
                        _buildSortChip('Artist', _CacheSortMode.artist),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          if (sortedKeys.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.folder_off_rounded, size: 64, color: Colors.white.withValues(alpha: 0.1)),
                    const SizedBox(height: 16),
                    Text(
                      query.isEmpty ? 'No saved songs yet' : 'No matches found',
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
        ],
      ),
    );
  }

  Widget _buildSortChip(String label, _CacheSortMode mode) {
    final selected = _sortMode == mode;
    return ChoiceChip(
      selected: selected,
      label: Text(label),
      onSelected: (_) => setState(() => _sortMode = mode),
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      labelStyle: TextStyle(
        color: selected ? Colors.black : Colors.white.withValues(alpha: 0.7),
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
      selectedColor: Colors.white,
      backgroundColor: Colors.white.withValues(alpha: 0.08),
      side: BorderSide(color: Colors.white.withValues(alpha: selected ? 0.0 : 0.08)),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)} MB';
  }
}
