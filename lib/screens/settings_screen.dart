import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/media_session_service.dart';
import 'settings_appearance.dart';
import 'settings_immersive.dart';
import 'settings_haptics.dart';
import 'settings_storage.dart';

class SettingsScreen extends StatelessWidget {
  final MediaSessionService service;

  const SettingsScreen({super.key, required this.service});

  @override
  Widget build(BuildContext context) {
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
                _buildMenuTile(
                  context,
                  title: 'Appearance',
                  subtitle: 'Font size, romanization, and visuals',
                  icon: Icons.palette_rounded,
                  page: const AppearanceSettingsScreen(),
                ),
                _buildMenuTile(
                  context,
                  title: 'Immersive Effects',
                  subtitle: '3D Parallax and motion effects',
                  icon: Icons.blur_on_rounded,
                  page: const ImmersiveEffectsSettingsScreen(),
                ),
                _buildMenuTile(
                  context,
                  title: 'Haptics',
                  subtitle: 'Intensity, word-level vibrations',
                  icon: Icons.vibration_rounded,
                  page: const HapticSettingsScreen(),
                ),
                _buildMenuTile(
                  context,
                  title: 'Storage & Cache',
                  subtitle: 'Manage saved lyrics and artwork',
                  icon: Icons.storage_rounded,
                  page: StorageCacheSettingsScreen(service: service),
                ),
                const SizedBox(height: 40),
                Center(
                  child: FutureBuilder<PackageInfo>(
                    future: PackageInfo.fromPlatform(),
                    builder: (context, snapshot) {
                      final version = snapshot.hasData ? snapshot.data!.version : '...';
                      return Text(
                        'Simple Lyrics v$version',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.2),
                          fontSize: 12,
                        ),
                      );
                    },
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget page,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: ListTile(
        onTap: () {
          Navigator.of(context).push(
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) => page,
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return FadeTransition(opacity: animation, child: child);
              },
              transitionDuration: const Duration(milliseconds: 300),
            ),
          );
        },
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
        trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white24),
      ),
    );
  }
}

