import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/font_fallbacks.dart';
import '../core/settings_route.dart';
import '../services/media_session_service.dart';
import '../services/update_service.dart';
import 'settings_appearance.dart';
import 'settings_haptics.dart';
import 'settings_immersive.dart';
import 'settings_lyrics.dart';
import 'settings_storage.dart';

enum _Section {
  appearance('Appearance', Icons.palette_outlined),
  lyrics('Lyrics', Icons.subtitles_rounded),
  immersive('Immersive Effects', Icons.auto_awesome_outlined),
  haptics('Haptics', Icons.vibration_rounded),
  storage('Storage & Cache', Icons.storage_rounded),
  updates('Updates', Icons.system_update_rounded);

  const _Section(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Opens the desktop settings as a two-pane overlay: section navigation down
/// the left, section content on the right.
///
/// This replaces the phone pattern of pushing a card list and then a full-screen
/// page per section — on a 1280px-wide window that leaves the content stranded
/// in the middle of an otherwise empty screen, and the back arrow in each
/// section's AppBar has nowhere sensible to go.
Future<void> showWindowsSettings(
    BuildContext context, MediaSessionService service) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.60),
    transitionDuration: const Duration(milliseconds: 520),
    pageBuilder: (context, animation, secondaryAnimation) =>
        WindowsSettings(service: service),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return buildSettingsTransition(
        animation: animation,
        secondaryAnimation: secondaryAnimation,
        child: child,
        includeSecondary: false,
      );
    },
  );
}

class WindowsSettings extends StatefulWidget {
  final MediaSessionService service;

  const WindowsSettings({super.key, required this.service});

  @override
  State<WindowsSettings> createState() => _WindowsSettingsState();
}

class _WindowsSettingsState extends State<WindowsSettings> {
  _Section _section = _Section.appearance;
  bool _checkingUpdate = false;

  @override
  Widget build(BuildContext context) {
    // Escape belongs to the settings overlay while it is open. Our own
    // desktop shortcut layer sits between this dialog and the app-level
    // bindings, so it would otherwise swallow the key first.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: Focus(
        autofocus: true,
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 64, vertical: 48),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980, maxHeight: 680),
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: const Color(0xFF1B1B1D),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Row(
                children: [
                  _buildNav(),
                  Container(
                    width: 1,
                    color: Colors.white.withValues(alpha: 0.07),
                  ),
                  Expanded(child: _buildPane()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNav() {
    return Container(
      width: 272,
      color: const Color(0xFF141416),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(22, 22, 22, 18),
            child: Text(
              'Settings',
              style: TextStyle(
                fontFamily: 'Display',
                fontFamilyFallback: kGlobalFontFallbacks,
                fontSize: 21,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          for (final section in _Section.values) _NavTile(
            section: section,
            selected: section == _section,
            onTap: () => setState(() => _section = section),
          ),
          const Spacer(),
          const Padding(
            padding: EdgeInsets.all(22),
            child: _VersionLabel(),
          ),
        ],
      ),
    );
  }

  Widget _buildPane() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(26, 16, 14, 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _section.label,
                  style: const TextStyle(
                    fontFamily: 'Display',
                    fontFamilyFallback: kGlobalFontFallbacks,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                tooltip: 'Close (Esc)',
                icon: const Icon(Icons.close_rounded,
                    color: Colors.white60, size: 22),
                hoverColor: Colors.white.withValues(alpha: 0.10),
                splashRadius: 20,
                constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
              ),
            ],
          ),
        ),
        Container(height: 1, color: Colors.white.withValues(alpha: 0.07)),
        Expanded(child: _buildSection()),
      ],
    );
  }

  Widget _buildSection() {
    switch (_section) {
      case _Section.appearance:
        return const AppearanceSettingsScreen(embedded: true);
      case _Section.lyrics:
        return const LyricsSettingsScreen(embedded: true);
      case _Section.immersive:
        return const ImmersiveEffectsSettingsScreen(embedded: true);
      case _Section.haptics:
        return const HapticSettingsScreen(embedded: true);
      case _Section.storage:
        return StorageCacheSettingsScreen(
            service: widget.service, embedded: true);
      case _Section.updates:
        return _UpdatesPane(
          checking: _checkingUpdate,
          onCheck: _checkForUpdate,
        );
    }
  }

  Future<void> _checkForUpdate() async {
    if (_checkingUpdate) return;
    setState(() => _checkingUpdate = true);
    try {
      await UpdateService.checkAndShowUpdate(context);
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }
}

class _NavTile extends StatelessWidget {
  final _Section section;
  final bool selected;
  final VoidCallback onTap;

  const _NavTile({
    required this.section,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: selected
            ? Colors.white.withValues(alpha: 0.10)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          hoverColor: Colors.white.withValues(alpha: 0.06),
          child: SizedBox(
            height: 40,
            child: Row(
              children: [
                const SizedBox(width: 14),
                Icon(
                  section.icon,
                  size: 19,
                  color: selected ? Colors.white : Colors.white54,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    section.label,
                    style: TextStyle(
                      fontFamily: 'Display',
                      fontFamilyFallback: kGlobalFontFallbacks,
                      fontSize: 14,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w400,
                      color: selected ? Colors.white : Colors.white70,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UpdatesPane extends StatelessWidget {
  final bool checking;
  final VoidCallback onCheck;

  const _UpdatesPane({required this.checking, required this.onCheck});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Check for updates',
            style: TextStyle(
              fontFamily: 'Display',
              fontFamilyFallback: kGlobalFontFallbacks,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Download the latest features and fixes.',
            style: TextStyle(
              fontFamily: 'Display',
              fontFamilyFallback: kGlobalFontFallbacks,
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: checking ? null : onCheck,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.12),
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            icon: checking
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.system_update_rounded, size: 18),
            label: Text(checking ? 'Checking…' : 'Check now'),
          ),
        ],
      ),
    );
  }
}

class _VersionLabel extends StatelessWidget {
  const _VersionLabel();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final version = snapshot.hasData ? snapshot.data!.version : '…';
        return Text(
          'Simple Lyrics v$version',
          style: TextStyle(
            fontFamily: 'Display',
            fontFamilyFallback: kGlobalFontFallbacks,
            fontSize: 12,
            color: Colors.white.withValues(alpha: 0.30),
          ),
        );
      },
    );
  }
}
