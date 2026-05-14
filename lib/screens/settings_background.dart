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
                      value: currentStyle,
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
                                  fontFamily: 'Display',
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
              if (currentStyle != BackgroundStyle.acrylic) {
                return const SizedBox(height: 20);
              }
              return Column(
                children: [
                  const SizedBox(height: 20),
                  _buildSettingSection(
                    title: 'Acrylic Texture',
                    child: ValueListenableBuilder<AcrylicTexture>(
                      valueListenable: settings.acrylicTexture,
                      builder: (context, currentTexture, _) {
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
                            child: DropdownButtonFormField<AcrylicTexture>(
                              value: currentTexture,
                              decoration: const InputDecoration(
                                contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                border: InputBorder.none,
                              ),
                              icon: const Icon(Icons.expand_more_rounded, color: Colors.white38),
                              dropdownColor: const Color(0xFF161616),
                              borderRadius: BorderRadius.circular(20),
                              items: AcrylicTexture.values.map((texture) {
                                return DropdownMenuItem<AcrylicTexture>(
                                  value: texture,
                                  child: Row(
                                    children: [
                                      Icon(_getIconForTexture(texture), color: Colors.white70, size: 20),
                                      const SizedBox(width: 12),
                                      Text(
                                        _getTextureName(texture),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                          fontFamily: 'Display',
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                              onChanged: (AcrylicTexture? newTexture) {
                                if (newTexture != null) {
                                  settings.acrylicTexture.value = newTexture;
                                }
                              },
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              );
            },
          ),
          _buildInfoTile(
            'Each style is optimized for performance and ensures lyric legibility by automatically adjusting brightness based on the current artwork.',
          ),
        ],
      ),
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
              fontWeight: FontWeight.bold,
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
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
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

  String _getTextureName(AcrylicTexture texture) {
    switch (texture) {
      case AcrylicTexture.fineGrain: return 'Fine Grain';
      case AcrylicTexture.frosted: return 'Frosted';
      case AcrylicTexture.ripple: return 'Ripple / Water';
      case AcrylicTexture.crystalline: return 'Crystalline';
    }
  }

  IconData _getIconForTexture(AcrylicTexture texture) {
    switch (texture) {
      case AcrylicTexture.fineGrain: return Icons.grain_rounded;
      case AcrylicTexture.frosted: return Icons.cloud_rounded;
      case AcrylicTexture.ripple: return Icons.water_drop_rounded;
      case AcrylicTexture.crystalline: return Icons.diamond_rounded;
    }
  }
}
