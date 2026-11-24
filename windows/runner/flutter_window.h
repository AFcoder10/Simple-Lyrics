#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>

#include "media_bridge.h"
#include "win32_window.h"
#include "window_bridge.h"

// A window that hosts a Flutter view and the GSMTC media bridge.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

  // Applies the fixed, non-resizable window geometry. Call after Create().
  void ApplyFixedSize();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Bridges Dart to the Windows Global System Media Transport Controls.
  std::unique_ptr<MediaBridge> media_bridge_;

  // Fullscreen / always-on-top / fixed-size support for the Dart side.
  std::unique_ptr<WindowBridge> window_bridge_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
