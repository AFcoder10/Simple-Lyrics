#include "window_bridge.h"

#include <algorithm>
#include <cstdint>
#include <utility>

#include <dwmapi.h>

namespace {

// Logical size of the normal (windowed) mode at 96 DPI. The default layout
// splits the window into an artwork/metadata pane and a lyrics pane, so it
// needs real desktop width — 420 was the phone layout this app was ported
// from. Compact mode asks for its own size through `setFixedSize`.
constexpr int kLogicalWidth = 1280;
constexpr int kLogicalHeight = 800;

// Never offer a window smaller than this, even if a display is tiny.
constexpr int kMinimumWidth = 320;
constexpr int kMinimumHeight = 480;

int ScaleForDpi(HWND window, int logical) {
  // Flutter works in physical pixels, so a window sized in logical pixels
  // would look tiny on a 150% or 200% display.
  UINT dpi = GetDpiForWindow(window);
  if (dpi == 0) {
    dpi = 96;
  }
  return MulDiv(logical, static_cast<int>(dpi), 96);
}

// Centre `width` x `height` inside the work area of the monitor the window is
// currently on, so it never spawns straddling two displays or under the taskbar.
void CenterOnCurrentMonitor(HWND window, int width, int height) {
  HMONITOR monitor = MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST);
  MONITORINFO info{};
  info.cbSize = sizeof(info);
  if (!GetMonitorInfoW(monitor, &info)) {
    return;
  }
  const RECT& work = info.rcWork;

  const int work_width = static_cast<int>(work.right - work.left);
  const int work_height = static_cast<int>(work.bottom - work.top);

  const int clamped_width = std::clamp(width, kMinimumWidth, work_width);
  const int clamped_height = std::clamp(height, kMinimumHeight, work_height);

  const int x = work.left + (work_width - clamped_width) / 2;
  const int y = work.top + (work_height - clamped_height) / 2;

  ::SetWindowPos(window, nullptr, x, y, clamped_width, clamped_height,
                 SWP_NOZORDER | SWP_NOACTIVATE);
}

}  // namespace

WindowBridge::WindowBridge(HWND window, flutter::BinaryMessenger* messenger)
    : window_(window) {
  channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "com.simplelyrics/window",
          &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        HandleMethodCall(call, std::move(result));
      });
}

WindowBridge::~WindowBridge() {
  if (channel_) {
    channel_->SetMethodCallHandler(nullptr);
  }
}

void WindowBridge::ApplyFixedSize() {
  if (!window_) {
    return;
  }

  // Drop the sizing frame and the maximise button: the app is fixed-size or
  // fullscreen, and an enabled maximise button would let the user drag the
  // window out to an arbitrary desktop shape anyway. The title bar stays, so
  // the user still has a close button and a way to move/alt-tab the window.
  // Minimize is kept so the app can be tucked away.
  LONG_PTR style = ::GetWindowLongPtrW(window_, GWL_STYLE);
  style &= ~(static_cast<LONG_PTR>(WS_THICKFRAME) | WS_MAXIMIZEBOX);
  style |= WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX;
  ::SetWindowLongPtrW(window_, GWL_STYLE, style);

  const int width = ScaleForDpi(window_, kLogicalWidth);
  const int height = ScaleForDpi(window_, kLogicalHeight);

  // AdjustWindowRectEx converts the requested client area into a window rect
  // that accounts for the borders and taskbar the shell draws around it.
  RECT rect{0, 0, width, height};
  ::AdjustWindowRectEx(&rect, static_cast<DWORD>(style), FALSE, 0);

  CenterOnCurrentMonitor(window_, rect.right - rect.left, rect.bottom - rect.top);

  // SWP_FRAMECHANGED forces the shell to recompute the non-client area, which
  // is what actually applies the style edit above. Without it the window keeps
  // the resizable frame the user would otherwise drag around.
  ::SetWindowPos(window_, nullptr, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                     SWP_FRAMECHANGED);
  ::ShowWindow(window_, SW_SHOWNORMAL);

  size_locked_ = true;
  fixed_width_ = width;
  fixed_height_ = height;
}

void WindowBridge::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto& method = call.method_name();

  const auto* arguments = call.arguments();
  const auto* flag = arguments == nullptr
                         ? nullptr
                         : std::get_if<bool>(arguments);

  if (method == "setFullscreen") {
    if (flag == nullptr) {
      result->Error("bad_args", "setFullscreen expects a bool");
      return;
    }
    SetFullscreen(*flag);
    result->Success(flutter::EncodableValue(fullscreen_));
    return;
  }

  if (method == "isFullscreen") {
    result->Success(flutter::EncodableValue(fullscreen_));
    return;
  }

  if (method == "setAlwaysOnTop") {
    if (flag == nullptr) {
      result->Error("bad_args", "setAlwaysOnTop expects a bool");
      return;
    }
    SetAlwaysOnTop(*flag);
    result->Success(flutter::EncodableValue(always_on_top_));
    return;
  }

  if (method == "setFixedSize") {
    const auto* list = arguments == nullptr
                           ? nullptr
                           : std::get_if<flutter::EncodableList>(arguments);
    if (list == nullptr || list->size() != 2) {
      result->Error("bad_args", "setFixedSize expects [width, height]");
      return;
    }
    const auto* width = std::get_if<int32_t>(&(*list)[0]);
    const auto* height = std::get_if<int32_t>(&(*list)[1]);
    if (width == nullptr || height == nullptr) {
      result->Error("bad_args", "setFixedSize expects integer dimensions");
      return;
    }
    SetFixedSize(*width, *height);
    result->Success(flutter::EncodableValue());
    return;
  }

  result->NotImplemented();
}

bool WindowBridge::SetFullscreen(bool enabled) {
  if (!window_ || enabled == fullscreen_) {
    return fullscreen_;
  }

  if (enabled) {
    restore_rect_ = {};
    ::GetWindowRect(window_, &restore_rect_);
    restore_style_ = ::GetWindowLongPtrW(window_, GWL_STYLE);
    restore_ex_style_ = ::GetWindowLongPtrW(window_, GWL_EXSTYLE);

    // Borderless popup covering the whole monitor, not just the work area: a
    // fullscreen presentation should use every pixel the display offers.
    HMONITOR monitor = MonitorFromWindow(window_, MONITOR_DEFAULTTONEAREST);
    MONITORINFO info{};
    info.cbSize = sizeof(info);
    if (!GetMonitorInfoW(monitor, &info)) {
      return fullscreen_;
    }

    // WS_VISIBLE must be kept: SetWindowLongPtr applies the style bit to the
    // window's current visibility, so dropping it here would hide the window.
    ::SetWindowLongPtrW(window_, GWL_STYLE,
                        WS_POPUP | static_cast<LONG_PTR>(WS_VISIBLE));
    ::SetWindowLongPtrW(
        window_, GWL_EXSTYLE,
        restore_ex_style_ & ~static_cast<LONG_PTR>(WS_EX_APPWINDOW));

    ::SetWindowPos(window_, HWND_TOP, info.rcMonitor.left, info.rcMonitor.top,
                   info.rcMonitor.right - info.rcMonitor.left,
                   info.rcMonitor.bottom - info.rcMonitor.top,
                   SWP_NOOWNERZORDER | SWP_FRAMECHANGED);

    fullscreen_ = true;
    return fullscreen_;
  }

  ::SetWindowLongPtrW(window_, GWL_STYLE, restore_style_);
  ::SetWindowLongPtrW(window_, GWL_EXSTYLE, restore_ex_style_);

  if (restore_rect_.right > restore_rect_.left &&
      restore_rect_.bottom > restore_rect_.top) {
    ::SetWindowPos(window_, nullptr, restore_rect_.left, restore_rect_.top,
                   restore_rect_.right - restore_rect_.left,
                   restore_rect_.bottom - restore_rect_.top,
                   SWP_NOZORDER | SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
  }

  fullscreen_ = false;
  return fullscreen_;
}

void WindowBridge::SetAlwaysOnTop(bool enabled) {
  if (!window_) {
    return;
  }
  // WS_EX_TOPMOST is what actually keeps the window above others; the
  // SetWindowPos call is needed to apply the change immediately.
  LONG_PTR ex_style = ::GetWindowLongPtrW(window_, GWL_EXSTYLE);
  if (enabled) {
    ex_style |= static_cast<LONG_PTR>(WS_EX_TOPMOST);
  } else {
    ex_style &= ~static_cast<LONG_PTR>(WS_EX_TOPMOST);
  }
  ::SetWindowLongPtrW(window_, GWL_EXSTYLE, ex_style);
  ::SetWindowPos(window_, enabled ? HWND_TOPMOST : HWND_NOTOPMOST, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
  always_on_top_ = enabled;
}

bool WindowBridge::SetFixedSize(int width_px, int height_px) {
  if (!window_) {
    return false;
  }

  const LONG_PTR style = ::GetWindowLongPtrW(window_, GWL_STYLE);
  RECT rect{0, 0, std::max(width_px, kMinimumWidth),
            std::max(height_px, kMinimumHeight)};
  ::AdjustWindowRectEx(&rect, static_cast<DWORD>(style), FALSE, 0);

  CenterOnCurrentMonitor(window_, rect.right - rect.left, rect.bottom - rect.top);
  fixed_width_ = std::max(width_px, kMinimumWidth);
  fixed_height_ = std::max(height_px, kMinimumHeight);
  size_locked_ = true;
  return true;
}