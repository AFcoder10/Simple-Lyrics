import 'package:simple_lyrics/core/font_fallbacks.dart';
import 'package:flutter/material.dart';
import '../services/settings_service.dart';

class BackgroundSettingsScreen extends StatelessWidget {
  const BackgroundSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = SettingsService();

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        elevation: 0,
        title: const Text(
          'Background Style',
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
          _buildSettingSection(
            title: 'Select Background',
            child: ValueListenableBuilder<BackgroundStyle>(
              valueListenable: settings.backgroundStyle,
              builder: (context, currentStyle, _) {
                return Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Theme(
                    data: Theme.of(context).copyWith(
                      canvasColor: const Color(0xFF161616),
                      splashColor: Colors.transparent,
                    ),
                    child: DropdownButtonFormField<BackgroundStyle>(
                      initialValue: currentStyle,
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        border: InputBorder.none,
                      ),
                      icon: const Icon(Icons.expand_more_rounded, color: Colors.white38),
                      dropdownColor: const Color(0xFF161616),
                      borderRadius: BorderRadius.circular(20),
                      items: BackgroundStyle.values.map((style) {
                        return DropdownMenuItem<BackgroundStyle>(
                          value: style,
                          child: Row(
                            children: [
                              Icon(_getIconForStyle(style), color: Colors.white70, size: 20),
                              const SizedBox(width: 12),
                              Text(
                                _getStyleName(style),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  fontFamily: 'Inter', fontFamilyFallback: kGlobalFontFallbacks,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (BackgroundStyle? newStyle) {
                        if (newStyle != null) {
                          settings.backgroundStyle.value = newStyle;
                        }
                      },
                    ),
                  ),
                );
              },
            ),
          ),
          ValueListenableBuilder<BackgroundStyle>(
            valueListenable: settings.backgroundStyle,
            builder: (context, currentStyle, _) {
              return AnimatedSize(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                clipBehavior: Clip.hardEdge,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  layoutBuilder: (currentChild, previousChildren) {
                    return Stack(
                      alignment: Alignment.topCenter,
                      children: [
                        for (final prev in previousChildren)
                          Positioned(top: 0, left: 0, right: 0, child: prev),
                        ?currentChild,
                      ],
                    );
                  },
                  child: KeyedSubtree(
                    key: ValueKey(currentStyle),
                    child: _buildStyleOptions(currentStyle, settings),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          _buildInfoTile(
            'Each style is optimized for performance and ensures lyric legibility by automatically adjusting brightness based on the current artwork.',
          ),
        ],
      ),
    );
  }

  Widget _buildStyleOptions(BackgroundStyle style, SettingsService settings) {
    switch (style) {
      case BackgroundStyle.spinningBlur:
        return _buildOptionsGroup(
          title: 'Dynamic Blur Settings',
          rows: [
            _buildSliderRow(
              label: 'Blur Intensity',
              icon: Icons.blur_linear_rounded,
              valueListenable: settings.blurIntensity,
              min: 0.0,
              max: 80.0,
            ),
            _buildSliderRow(
              label: 'Animation Speed',
              icon: Icons.speed_rounded,
              valueListenable: settings.blurAnimationSpeed,
              min: 0.2,
              max: 3.0,
            ),
          ],
          onReset: () {
            settings.blurIntensity.value = 10.0;
            settings.blurAnimationSpeed.value = 1.0;
          },
        );
      case BackgroundStyle.acrylic:
        return _buildOptionsGroup(
          title: 'Acrylic Texture Settings',
          rows: [
            _buildSliderRow(
              label: 'Grain Intensity',
              icon: Icons.grain_rounded,
              valueListenable: settings.grainIntensity,
              min: 0.0,
              max: 0.15,
            ),
          ],
          onReset: () {
            settings.grainIntensity.value = 0.04;
          },
        );
      case BackgroundStyle.staticColor:
        return _buildOptionsGroup(
          title: 'Static Color Settings',
          rows: [
            _buildSliderRow(
              label: 'Vibrancy',
              icon: Icons.contrast_rounded,
              valueListenable: settings.staticVibrancy,
              min: 0.0,
              max: 3.0,
            ),
            _buildSliderRow(
              label: 'Contrast',
              icon: Icons.brightness_medium_rounded,
              valueListenable: settings.staticContrast,
              min: 0.2,
              max: 2.5,
            ),
          ],
          onReset: () {
            settings.staticVibrancy.value = 1.8;
            settings.staticContrast.value = 1.0;
          },
        );
    }
  }

  Widget _buildOptionsGroup({
    required String title,
    required List<Widget> rows,
    required VoidCallback onReset,
  }) {
    return Column(
      children: [
        const SizedBox(height: 20),
        _buildSettingSection(
          title: title,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
              children: [
                for (final row in rows) ...[
                  row,
                  const Divider(color: Colors.white10, height: 1),
                ],
                TextButton.icon(
                  onPressed: onReset,
                  icon: const Icon(Icons.refresh_rounded, size: 18, color: Colors.white70),
                  label: const Text(
                    'Reset Defaults',
                    style: TextStyle(color: Colors.white70, fontFamily: 'Display', fontFamilyFallback: kGlobalFontFallbacks),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    minimumSize: const Size(double.infinity, 0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSettingSection({required String title, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12, top: 10),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 12,
              fontFamily: 'Display', fontFamilyFallback: kGlobalFontFallbacks,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ),
        child,
      ],
    );
  }

  Widget _buildInfoTile(String text) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: Colors.white38, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 13,
                fontFamily: 'Display', fontFamilyFallback: kGlobalFontFallbacks,
                fontWeight: FontWeight.w400,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliderRow({
    required String label,
    required IconData icon,
    required ValueNotifier<double> valueListenable,
    required double min,
    required double max,
  }) {
    return ValueListenableBuilder<double>(
      valueListenable: valueListenable,
      builder: (context, val, _) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: Colors.white70, size: 18),
                  const SizedBox(width: 12),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      fontFamily: 'Inter', fontFamilyFallback: kGlobalFontFallbacks,
                    ),
                  ),
                ],
              ),
              SliderTheme(
                data: SliderThemeData(
                  activeTrackColor: Colors.white,
                  inactiveTrackColor: Colors.white24,
                  thumbColor: Colors.white,
                  overlayColor: Colors.white.withValues(alpha: 0.1),
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                ),
                child: Slider(
                  value: val,
                  min: min,
                  max: max,
                  onChanged: (newVal) => valueListenable.value = newVal,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _getStyleName(BackgroundStyle style) {
    switch (style) {
      case BackgroundStyle.spinningBlur: return 'Dynamic Blur';
      case BackgroundStyle.acrylic: return 'Acrylic Texture';
      case BackgroundStyle.staticColor: return 'Static Color';
    }
  }

  IconData _getIconForStyle(BackgroundStyle style) {
    switch (style) {
      case BackgroundStyle.spinningBlur: return Icons.auto_awesome_rounded;
      case BackgroundStyle.acrylic: return Icons.blur_on_rounded;
      case BackgroundStyle.staticColor: return Icons.palette_rounded;
    }
  }
}
