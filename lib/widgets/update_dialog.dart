import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../services/update_service.dart';
import '../core/font_fallbacks.dart';

class UpdateDialog extends StatefulWidget {
  final UpdateInfo updateInfo;

  const UpdateDialog({super.key, required this.updateInfo});

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  double _downloadProgress = 0.0;
  bool _isDownloading = false;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 400,
          maxHeight: 500,
        ),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Update Available',
                style: TextStyle(
                  fontFamily: 'Display',
                  fontFamilyFallback: kGlobalFontFallbacks,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Version ${widget.updateInfo.version} is ready to install.',
                style: const TextStyle(color: Colors.white70, fontSize: 15),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    child: widget.updateInfo.notes.isEmpty 
                      ? const Text('No release notes.', style: TextStyle(color: Colors.white60, fontSize: 13))
                      : MarkdownBody(
                          data: widget.updateInfo.notes,
                          styleSheet: MarkdownStyleSheet(
                            p: const TextStyle(fontFamily: 'Display', fontFamilyFallback: kGlobalFontFallbacks, color: Colors.white70, fontSize: 14),
                            listBullet: const TextStyle(color: Colors.white70),
                            h1: const TextStyle(fontFamily: 'Display', fontFamilyFallback: kGlobalFontFallbacks, color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                            h2: const TextStyle(fontFamily: 'Display', fontFamilyFallback: kGlobalFontFallbacks, color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                            h3: const TextStyle(fontFamily: 'Display', fontFamilyFallback: kGlobalFontFallbacks, color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                            strong: const TextStyle(fontFamily: 'Display', fontFamilyFallback: kGlobalFontFallbacks, color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                  ),
                ),
              ),
              if (_isDownloading) ...[
                const SizedBox(height: 20),
                LinearProgressIndicator(
                  value: _downloadProgress,
                  backgroundColor: Colors.white12,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    '${(_downloadProgress * 100).toStringAsFixed(1)}%',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isDownloading ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _isDownloading
                        ? null
                        : () async {
                            setState(() {
                              _isDownloading = true;
                            });
                            await UpdateService().downloadAndInstall(
                              widget.updateInfo.downloadUrl,
                              (progress) {
                                if (mounted) {
                                  setState(() {
                                    _downloadProgress = progress;
                                  });
                                }
                              },
                            );
                            if (mounted) {
                              Navigator.of(context).pop();
                            }
                          },
                    child: Text(
                      _isDownloading ? 'Downloading...' : 'Update Now',
                      style: const TextStyle(color: Colors.blueAccent),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
