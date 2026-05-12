import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/media_session_service.dart';
import 'screens/home_screen.dart';
import 'screens/permission_screen.dart';
import 'services/settings_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await SettingsService().init();

  // Immersive edge-to-edge system UI
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
    ),
  );

  runApp(const SimpleLyricsApp());
}

class SimpleLyricsApp extends StatefulWidget {
  const SimpleLyricsApp({super.key});

  @override
  State<SimpleLyricsApp> createState() => _SimpleLyricsAppState();
}

class _SimpleLyricsAppState extends State<SimpleLyricsApp> {
  final _mediaService = MediaSessionService();
  bool _permissionChecked = false;
  bool _hasPermission = false;

  @override
  void initState() {
    super.initState();
    _checkInitialPermission();
  }

  Future<void> _checkInitialPermission() async {
    final granted = await _mediaService.isPermissionGranted();
    setState(() {
      _hasPermission = granted;
      _permissionChecked = true;
    });
  }

  @override
  void dispose() {
    _mediaService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Simple Lyrics',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF1DB954),
          surface: Color(0xFF121212),
          onPrimary: Colors.black,
          onSurface: Colors.white,
        ),
        fontFamily: 'Display',
        useMaterial3: true,
      ),
      routes: {
        '/home': (_) => HomeScreen(service: _mediaService),
        '/permission': (_) => PermissionScreen(service: _mediaService),
      },
      home: _buildInitialScreen(),
    );
  }

  Widget _buildInitialScreen() {
    if (!_permissionChecked) {
      // Show loading while checking permission
      return const Scaffold(
        backgroundColor: Color(0xFF0A0A0A),
        body: Center(
          child: CircularProgressIndicator(
            color: Color(0xFF1DB954),
            strokeWidth: 2,
          ),
        ),
      );
    }

    if (_hasPermission) {
      return HomeScreen(service: _mediaService);
    } else {
      return PermissionScreen(service: _mediaService);
    }
  }
}
