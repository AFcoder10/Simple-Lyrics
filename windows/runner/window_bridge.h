#ifndef RUNNER_WINDOW_BRIDGE_H_
#define RUNNER_WINDOW_BRIDGE_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_call.h>
#include <flutter/method_channel.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>

#include <windows.h>

// Owns the native window's chrome: a fixed, non-resizable size plus an
// opt-in fullscreen mode. Simple Lyrics is a phone-shaped overlay, so letting
// the window be dragged to arbitrary desktop sizes produces layouts that were
// never designed (stretched lyric columns, half-hidden controls).
//
// Dart talks to this over the "com.simplelyrics/window" MethodChannel.
class WindowBridge {
 public:
  WindowBridge(HWND window, flutter::BinaryMessenger* messenger);
  ~WindowBridge();

  // Applies the initial fixed geometry. Safe to call after the window exists.
  void ApplyFixedSize();

  // Window thread only.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

 private:
  bool SetFullscreen(bool enabled);
  void SetAlwaysOnTop(bool enabled);
  bool SetFixedSize(int width_px, int height_px);

  HWND window_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;

  bool fullscreen_{false};
  bool always_on_top_{false};
  bool size_locked_{false};
  int fixed_width_{0};
  int fixed_height_{0};
  RECT restore_rect_{};
  LONG_PTR restore_style_{0};
  LONG_PTR restore_ex_style_{0};
};

#endif  // RUNNER_WINDOW_BRIDGE_H_