import 'package:simple_lyrics/core/font_fallbacks.dart';
import 'package:flutter/material.dart';
import '../core/settings_route.dart';
import '../services/settings_service.dart';
import 'settings_background.dart';

class AppearanceSettingsScreen extends StatelessWidget {
  /// Hosted inside the desktop settings pane, which supplies its own title, so
  /// the section drops its back-arrow [AppBar] rather than rendering a second
  /// one the user cannot usefully press.
  final bool embedded;

  const AppearanceSettingsScreen({super.key, this.embedded = false});

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: embedded ? null : AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        elevation: 0,
        title: const Text(
          'Appearance',
          style: TextStyle(
            fontFamily: 'Display', fontFamilyFallback: kGlobalFontFallbacks,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white70, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        children: [
          // OLED protection removed
          const SizedBox(height: 16),
          ValueListenableBuilder<bool>(
            valueListenable: SettingsService().animatedArtworkEnabled,
            builder: (context, enabled, _) {
              return _buildSettingTile(
                title: 'Animated Artwork',
                subtitle: 'Play looping motion artwork when available',
                icon: Icons.play_circle_outline_rounded,
                showBeta: true,
                trailing: Switch.adaptive(
                  value: enabled,
                  activeThumbColor: const Color(0xFF00C853), // Modern premium green
                  onChanged: (val) {
                    SettingsService().animatedArtworkEnabled.value = val;
                  },
                ),
              );
            },
          ),
          const SizedBox(height: 4),
          ValueListenableBuilder<bool>(
            valueListenable: SettingsService().showBackgroundInFullScreenArtwork,
            builder: (context, enabled, _) {
              return _buildSettingTile(
                title: 'Full Screen Background',
                subtitle: 'Show ambient background instead of solid black behind artwork',
                icon: Icons.layers_outlined,
                trailing: Switch.adaptive(
                  value: enabled,
                  activeThumbColor: const Color(0xFF00C853),
                  onChanged: (val) {
                    SettingsService().showBackgroundInFullScreenArtwork.value = val;
                  },
                ),
              );
            },
          ),
          const SizedBox(height: 4),
          _buildSettingTile(
            title: 'Background Style',
            subtitle: 'Customize the lyrics background atmosphere',
            icon: Icons.wallpaper_rounded,
            trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white24, size: 16),
            onTap: () {
              Navigator.of(context).push(
                buildSettingsRoute(const BackgroundSettingsScreen()),
              );
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildSettingTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget trailing,
    VoidCallback? onTap,
    bool showBeta = false,
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
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Material(
              type: MaterialType.transparency,
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
            ),
          ),
        ),
        if (showBeta)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF00C853).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: const Color(0xFF00C853).withValues(alpha: 0.4),
                  width: 0.5,
                ),
              ),
              child: const Text(
                'BETA',
                style: TextStyle(
                  color: Color(0xFF00C853),
                  fontSize: 8,
                  fontWeight: FontWeight(1000),
                  fontFamily: 'Display', fontFamilyFallback: kGlobalFontFallbacks,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
