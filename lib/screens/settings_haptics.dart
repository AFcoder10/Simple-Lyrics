import 'package:flutter/material.dart';
import '../services/settings_service.dart';

class HapticSettingsScreen extends StatelessWidget {
  const HapticSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = SettingsService();

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        elevation: 0,
        title: const Text(
          'Haptics',
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
          _buildSettingTile(
            title: 'Haptic Feedback',
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
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeInOutCubic,
                child: !enabled 
                  ? const SizedBox(width: double.infinity, height: 0)
                  : Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        children: [
                          _buildSettingTile(
                            title: 'Haptic Intensity',
                            subtitle: 'Adjust vibration strength',
                            icon: Icons.graphic_eq_rounded,
                            trailing: SizedBox(
                              width: 120,
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
                          _buildSettingTile(
                            title: 'Word-to-Word Vibration',
                            subtitle: 'Vibrate for each individual word',
                            icon: Icons.text_fields_rounded,
                            trailing: ValueListenableBuilder<bool>(
                              valueListenable: settings.wordToWordHapticsEnabled,
                              builder: (context, enabled, _) {
                                return Switch.adaptive(
                                  value: enabled,
                                  onChanged: (val) => settings.wordToWordHapticsEnabled.value = val,
                                  activeThumbColor: const Color(0xFF1DB954),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
              );
            }
          ),
        ],
      ),
    );
  }

  Widget _buildSettingTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget trailing,
  }) {
    return Stack(
      children: [
        Container(
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
        ),
        if (title == 'Word-to-Word Vibration')
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF1DB954).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: const Color(0xFF1DB954).withValues(alpha: 0.4),
                  width: 0.5,
                ),
              ),
              child: const Text(
                'BETA',
                style: TextStyle(
                  color: Color(0xFF1DB954),
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
