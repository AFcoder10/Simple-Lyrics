import 'package:simple_lyrics/core/font_fallbacks.dart';
import 'package:flutter/material.dart';
import '../services/settings_service.dart';

class ImmersiveEffectsSettingsScreen extends StatelessWidget {
  const ImmersiveEffectsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = SettingsService();

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        elevation: 0,
        title: const Text(
          'Immersive Effects',
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
          _buildSettingTile(
            title: '3D Parallax',
            subtitle: 'Smooth floating depth for lyrics',
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
          ValueListenableBuilder<bool>(
            valueListenable: settings.parallaxEnabled,
            builder: (context, enabled, _) {
              return _buildSlideIn(
                visible: enabled,
                child: Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: ValueListenableBuilder<double>(
                    valueListenable: settings.parallaxStrength,
                    builder: (context, value, _) {
                      return _buildSliderTile(
                        title: 'Parallax Strength',
                        subtitle: _strengthLabel(value),
                        icon: Icons.speed_rounded,
                        value: value,
                        onChanged: (next) => settings.parallaxStrength.value = next,
                      );
                    },
                  ),
                ),
              );
            },
          ),

        ],
      ),
    );
  }

  String _strengthLabel(double value) {
    if (value < 0.82) return 'Subtle';
    if (value > 1.18) return 'Strong';
    return 'Medium';
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

  Widget _buildSliderTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 16, 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white70, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontFamily: 'Display', fontFamilyFallback: kGlobalFontFallbacks,
                            fontWeight: FontWeight(1000),
                          ),
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 3,
                      activeTrackColor: const Color(0xFF1DB954),
                      inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
                      thumbColor: Colors.white,
                      overlayColor: const Color(0xFF1DB954).withValues(alpha: 0.12),
                    ),
                    child: Slider(
                      value: value,
                      min: 0.6,
                      max: 1.4,
                      divisions: 8,
                      onChanged: onChanged,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlideIn({
    required bool visible,
    required Widget child,
  }) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return SizeTransition(
          sizeFactor: animation,
          axis: Axis.vertical,
          axisAlignment: -1.0,
          child: FadeTransition(opacity: animation, child: child),
        );
      },
      child: visible ? child : const SizedBox.shrink(key: ValueKey('hidden')),
    );
  }
}
