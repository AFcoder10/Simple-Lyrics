import 'dart:async';
import 'package:flutter/material.dart';
import '../services/media_session_service.dart';

/// Permission request screen shown when notification listener access
/// has not been granted yet.
///
/// Provides a clean explanation of why the permission is needed
/// and a button to open Android settings. Auto-detects when
/// permission is granted and navigates to home.
class PermissionScreen extends StatefulWidget {
  final MediaSessionService service;

  const PermissionScreen({super.key, required this.service});

  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen>
    with WidgetsBindingObserver {
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    super.dispose();
  }

  /// When the user returns from settings, check permission status.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermission();
    }
  }

  Future<void> _checkPermission() async {
    final granted = await widget.service.isPermissionGranted();
    if (granted && mounted) {
      Navigator.of(context).pushReplacementNamed('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(flex: 3),
              // Icon
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF1DB954).withValues(alpha: 0.2),
                      const Color(0xFF1DB954).withValues(alpha: 0.05),
                    ],
                  ),
                ),
                child: const Icon(
                  Icons.notifications_active_rounded,
                  color: Color(0xFF1DB954),
                  size: 40,
                ),
              ),
              const SizedBox(height: 32),
              // Title
              const Text(
                'Notification Access',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 12),
              // Description
              Text(
                'Simple Lyrics needs notification access to detect '
                'what music is currently playing and display lyrics '
                'in real time.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 40),
              // Grant button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () => widget.service.requestPermission(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1DB954),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
                    ),
                    elevation: 0,
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                  ),
                  child: const Text('Grant Access'),
                ),
              ),
              const SizedBox(height: 16),
              // Subtle hint
              Text(
                'You\'ll be redirected to Android Settings.\n'
                'Enable "Simple Lyrics" in the list.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.25),
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
              const Spacer(flex: 4),
            ],
          ),
        ),
      ),
    );
  }
}
