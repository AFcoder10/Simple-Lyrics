import 'package:flutter/material.dart';
import '../services/settings_service.dart';
import 'settings_background.dart';

class AppearanceSettingsScreen extends StatelessWidget {
  const AppearanceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = SettingsService();

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        elevation: 0,
        title: const Text(
          'Appearance',
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
          _buildSettingTile(
            title: 'Background Style',
            subtitle: 'Customize the lyrics background atmosphere',
            icon: Icons.wallpaper_rounded,
            trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white24, size: 16),
            onTap: () {
              Navigator.of(context).push(
                PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) => const BackgroundSettingsScreen(),
                  transitionsBuilder: (context, animation, secondaryAnimation, child) {
                    return FadeTransition(opacity: animation, child: child);
                  },
                  transitionDuration: const Duration(milliseconds: 350),
                  reverseTransitionDuration: const Duration(milliseconds: 350),
                ),
              );
            },
          ),
        ],
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
