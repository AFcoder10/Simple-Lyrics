import 'package:simple_lyrics/core/font_fallbacks.dart';
import 'package:flutter/material.dart';
import '../services/settings_service.dart';

/// Dedicated screen for lyrics-related settings.
/// Includes font size, offset timing, and romanization options.
class LyricsSettingsScreen extends StatelessWidget {
  /// See [AppearanceSettingsScreen.embedded].
  final bool embedded;

  const LyricsSettingsScreen({super.key, this.embedded = false});

  @override
  Widget build(BuildContext context) {
    final settings = SettingsService();

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: embedded ? null : AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        elevation: 0,
        title: const Text(
          'Lyrics Settings',
          style: TextStyle(fontFamily: 'Display', fontFamilyFallback: kGlobalFontFallbacks, fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white70, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        children: [
          // Font Size
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
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 120),
                        switchInCurve: Curves.easeOutCubic,
                        child: Text(
                          size.toInt().toString(),
                          key: ValueKey(size.toInt()),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Display', fontFamilyFallback: kGlobalFontFallbacks,
                          ),
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
          const SizedBox(height: 16),

          // Lyrics Offset
          _buildSettingTile(
            title: 'Lyrics Offset',
            subtitle: 'Adjust lyrics timing (ms)',
            icon: Icons.speed_rounded,
            trailing: ValueListenableBuilder<int>(
              valueListenable: settings.lyricsOffsetMs,
              builder: (context, offset, _) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildStepperButton(
                      icon: Icons.remove_rounded,
                      onTap: () {
                        if (offset > -10000) {
                          settings.lyricsOffsetMs.value = offset - 50;
                        }
                      },
                      enabled: offset > -10000,
                    ),
                    Container(
                      width: 50,
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 120),
                            switchInCurve: Curves.easeOutCubic,
                            child: Text(
                              offset.toString(),
                              key: ValueKey(offset),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Display', fontFamilyFallback: kGlobalFontFallbacks,
                              ),
                            ),
                          ),
                          Text(
                            'ms',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 10,
                              fontFamily: 'Display', fontFamilyFallback: kGlobalFontFallbacks,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _buildStepperButton(
                      icon: Icons.add_rounded,
                      onTap: () {
                        if (offset < 10000) {
                          settings.lyricsOffsetMs.value = offset + 50;
                        }
                      },
                      enabled: offset < 10000,
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 16),

          // Romanization
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
          const SizedBox(height: 16),

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildStepperButton({
    required IconData icon,
    required VoidCallback onTap,
    required bool enabled,
  }) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
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
      ),
    );
  }

  Widget _buildSettingTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget trailing,
    VoidCallback? onTap,
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
            fontFamily: 'Display', fontFamilyFallback: kGlobalFontFallbacks,
            fontWeight: FontWeight(1000),
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 14,
              fontFamily: 'Display', fontFamilyFallback: kGlobalFontFallbacks,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
        trailing: trailing,
      ),
    );
  }
}
