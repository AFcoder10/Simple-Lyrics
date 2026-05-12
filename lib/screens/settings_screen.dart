import 'package:flutter/material.dart';
import '../services/settings_service.dart';
import '../services/media_session_service.dart';
import '../services/cache_service.dart';
import '../models/media_state.dart';
import 'cache_screen.dart';

class SettingsScreen extends StatelessWidget {
  final MediaSessionService service;

  const SettingsScreen({super.key, required this.service});

  @override
  Widget build(BuildContext context) {
    final settings = SettingsService();

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: const Color(0xFF0A0A0A),
            floating: true,
            pinned: true,
            elevation: 0,
            automaticallyImplyLeading: false,
            title: const Text(
              'Settings',
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
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _buildSectionHeader('Appearance'),
                _buildSettingTile(
                  title: 'Romanization',
                  subtitle: 'Show transliterated lyrics (e.g. Hindi to Latin)',
                  icon: Icons.translate_rounded,
                  trailing: ValueListenableBuilder<bool>(
                    valueListenable: settings.romanizationEnabled,
                    builder: (context, enabled, _) {
                      return Switch.adaptive(
                        value: enabled,
                        onChanged: (val) => settings.romanizationEnabled.value = val,
                        activeThumbColor: const Color(0xFF1DB954),
                      );
                    },
                  ),
                ),
                _buildSettingTile(
                  title: 'Lyrics Font Size',
                  subtitle: 'Adjust the size of the lyric text',
                  icon: Icons.format_size_rounded,
                  trailing: ValueListenableBuilder<double>(
                    valueListenable: settings.lyricsFontSize,
                    builder: (context, size, _) {
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildStepperButton(
                            icon: Icons.remove_rounded,
                            onTap: () => settings.updateFontSize(-2),
                            enabled: size > 20,
                          ),
                          Container(
                            width: 40,
                            alignment: Alignment.center,
                            child: Text(
                              size.toInt().toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Display',
                              ),
                            ),
                          ),
                          _buildStepperButton(
                            icon: Icons.add_rounded,
                            onTap: () => settings.updateFontSize(2),
                            enabled: size < 60,
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24),
                _buildSectionHeader('Immersive Effects'),
                _buildSettingTile(
                  title: '3D Parallax',
                  subtitle: 'Smooth floating depth using gyroscope',
                  icon: Icons.unfold_more_rounded,
                  trailing: ValueListenableBuilder<bool>(
                    valueListenable: settings.parallaxEnabled,
                    builder: (context, enabled, _) {
                      return Switch.adaptive(
                        value: enabled,
                        onChanged: (val) => settings.parallaxEnabled.value = val,
                        activeThumbColor: const Color(0xFF1DB954),
                      );
                    },
                  ),
                ),
                _buildSettingTile(
                  title: 'Haptic Lyrics',
                  subtitle: 'Feel the rhythm through vibrations',
                  icon: Icons.vibration_rounded,
                  trailing: ValueListenableBuilder<bool>(
                    valueListenable: settings.hapticLyricsEnabled,
                    builder: (context, enabled, _) {
                      return Switch.adaptive(
                        value: enabled,
                        onChanged: (val) => settings.hapticLyricsEnabled.value = val,
                        activeThumbColor: const Color(0xFF1DB954),
                      );
                    },
                  ),
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: settings.hapticLyricsEnabled,
                  builder: (context, enabled, _) {
                    return AnimatedSize(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOutCubic,
                      child: !enabled 
                        ? const SizedBox(width: double.infinity, height: 0)
                        : Padding(
                            padding: const EdgeInsets.only(top: 4, bottom: 12),
                            child: _buildSettingTile(
                              title: 'Haptic Intensity',
                              subtitle: 'Adjust vibration strength',
                              icon: Icons.graphic_eq_rounded,
                              trailing: SizedBox(
                                width: 140,
                                child: ValueListenableBuilder<double>(
                                  valueListenable: settings.hapticIntensity,
                                  builder: (context, intensity, _) {
                                    return SliderTheme(
                                      data: SliderTheme.of(context).copyWith(
                                        trackHeight: 4,
                                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                                        activeTrackColor: const Color(0xFF1DB954),
                                        inactiveTrackColor: Colors.white10,
                                        thumbColor: Colors.white,
                                      ),
                                      child: Slider(
                                        value: intensity,
                                        onChanged: (val) => settings.hapticIntensity.value = val,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                    );
                  }
                ),
                const SizedBox(height: 24),
                _buildSectionHeader('Storage & Cache'),
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
                const SizedBox(height: 40),
                Center(
                  child: Text(
                    'Simple Lyrics v1.0.0',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.2),
                      fontSize: 12,
                    ),
                  ),
                ),
              ]),
            ),
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

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12, top: 10),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.3),
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildStepperButton({
    required IconData icon,
    required VoidCallback onTap,
    required bool enabled,
  }) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: enabled ? 0.1 : 0.02),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          color: enabled ? Colors.white70 : Colors.white10,
          size: 20,
        ),
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

  Widget _buildSettingTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget trailing,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white70, size: 24),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 14,
            ),
          ),
        ),
        trailing: trailing,
      ),
    );
  }
}
