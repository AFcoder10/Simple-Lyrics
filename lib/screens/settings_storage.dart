import 'package:flutter/material.dart';
import '../services/media_session_service.dart';
import '../services/cache_service.dart';
import '../models/media_state.dart';
import 'cache_screen.dart';

class StorageCacheSettingsScreen extends StatelessWidget {
  final MediaSessionService service;

  const StorageCacheSettingsScreen({super.key, required this.service});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        elevation: 0,
        title: const Text(
          'Storage & Cache',
          style: TextStyle(fontFamily: 'Display', fontSize: 20, color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white70, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        children: [
          _buildActionTile(
            title: 'View Cache',
            subtitle: 'Manage individual saved songs',
            icon: Icons.folder_open_rounded,
            onTap: () {
              Navigator.of(context).push(
                PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) => CacheScreen(service: service),
                  transitionsBuilder: (context, animation, secondaryAnimation, child) {
                    return FadeTransition(opacity: animation, child: child);
                  },
                  transitionDuration: const Duration(milliseconds: 300),
                ),
              );
            },
          ),
          StreamBuilder<MediaState>(
            stream: service.mediaStateStream,
            builder: (context, snapshot) {
              final media = snapshot.data;
              final hasCurrent = media != null && !media.isEmpty;
              final currentKey = hasCurrent ? CacheService.makeKey(media.title, media.artist) : null;

              return Column(
                children: [
                  _buildActionTile(
                    title: 'Clear Current Song',
                    subtitle: hasCurrent ? 'Delete cache for "${media.title}"' : 'No active song to clear',
                    icon: Icons.music_note_rounded,
                    onTap: hasCurrent ? () => _confirmClear(context, 'current', currentKey!) : null,
                    enabled: hasCurrent,
                  ),
                  _buildActionTile(
                    title: 'Clear All Songs',
                    subtitle: 'Delete all saved lyrics and artwork',
                    icon: Icons.delete_sweep_rounded,
                    onTap: () => _confirmClear(context, 'all', null),
                    isDestructive: true,
                  ),
                ],
              );
            }
          ),
        ],
      ),
    );
  }

  void _confirmClear(BuildContext context, String mode, String? key) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF151515),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(mode == 'all' ? 'Clear All Cache?' : 'Clear Song Cache?', style: const TextStyle(color: Colors.white)),
        content: Text(
          mode == 'all' 
            ? 'This will delete all saved lyrics and artwork from your device.'
            : 'This will delete the saved lyrics and artwork for the current song.', 
          style: const TextStyle(color: Colors.white70)
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL', style: TextStyle(color: Colors.white24)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              if (mode == 'all') {
                await CacheService.clearAll();
              } else if (key != null) {
                await CacheService.clearSong(key);
              }
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Cache cleared successfully'),
                    duration: Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                  )
                );
              }
            },
            child: const Text('CLEAR', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  Widget _buildActionTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback? onTap,
    bool enabled = true,
    bool isDestructive = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: ListTile(
        onTap: onTap,
        enabled: enabled,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: (isDestructive ? Colors.redAccent : Colors.white).withValues(alpha: 0.05),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: isDestructive ? Colors.redAccent.withValues(alpha: 0.7) : Colors.white70, size: 24),
        ),
        title: Text(
          title,
          style: TextStyle(
            color: enabled ? Colors.white : Colors.white24,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            subtitle,
            style: TextStyle(
              color: enabled ? Colors.white.withValues(alpha: 0.5) : Colors.white10,
              fontSize: 14,
            ),
          ),
        ),
        trailing: Icon(Icons.chevron_right_rounded, color: enabled ? Colors.white24 : Colors.transparent),
      ),
    );
  }
}
