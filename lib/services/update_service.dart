import 'dart:io';
import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

class UpdateInfo {
  final String version;
  final String notes;
  final String downloadUrl;

  UpdateInfo({required this.version, required this.notes, required this.downloadUrl});
}

class UpdateService {
  static const String _apiUrl = 'https://api.github.com/repos/AFcoder10/Simple-Lyrics/releases/latest';

  /// Checks GitHub for a newer version of the app.
  Future<UpdateInfo?> checkForUpdate() async {
    try {
      final response = await Dio().get(_apiUrl);
      if (response.statusCode == 200) {
        final data = response.data;
        final latestTag = data['tag_name'] as String; // e.g., v1.0.4
        final latestVersion = latestTag.replaceAll('v', '');
        
        final packageInfo = await PackageInfo.fromPlatform();
        final currentVersion = packageInfo.version; // e.g., 1.0.3

        if (_isNewerVersion(latestVersion, currentVersion)) {
          final notes = data['body'] as String;
          final assets = data['assets'] as List;
          
          String downloadUrl = '';
          for (var asset in assets) {
            if (asset['name'] == 'Simple-Lyrics.apk') {
              downloadUrl = asset['browser_download_url'];
              break;
            }
          }
          
          if (downloadUrl.isNotEmpty) {
            return UpdateInfo(version: latestTag, notes: notes, downloadUrl: downloadUrl);
          }
        }
      }
    } catch (e) {
      // Silently fail if no internet or API limit reached
    }
    return null;
  }

  /// Simple semver comparison
  bool _isNewerVersion(String latest, String current) {
    List<int> l = latest.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    List<int> c = current.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    
    for (int i = 0; i < 3; i++) {
      int lVal = i < l.length ? l[i] : 0;
      int cVal = i < c.length ? c[i] : 0;
      if (lVal > cVal) return true;
      if (lVal < cVal) return false;
    }
    return false;
  }

  /// Downloads the APK and triggers the Android package installer.
  Future<void> downloadAndInstall(String url, Function(double) onProgress) async {
    try {
      final dir = await getTemporaryDirectory();
      
      // Clean up old APKs in the temp directory before downloading
      final files = dir.listSync();
      for (var file in files) {
        if (file.path.endsWith('.apk')) {
          try {
            file.deleteSync();
          } catch (_) {}
        }
      }

      final savePath = '${dir.path}/Simple-Lyrics-update.apk';

      await Dio().download(
        url,
        savePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            onProgress(received / total);
          }
        },
      );

      // Open the APK to prompt the user to install
      await OpenFilex.open(savePath);
    } catch (e) {
      // Silently fail
    }
  }
}
