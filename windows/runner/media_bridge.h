#ifndef RUNNER_MEDIA_BRIDGE_H_
#define RUNNER_MEDIA_BRIDGE_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/event_channel.h>
#include <flutter/event_sink.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/method_call.h>
#include <flutter/method_channel.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>

#include <windows.h>

#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Media.Control.h>
#include <winrt/Windows.Media.Playback.h>
#include <winrt/Windows.Storage.Streams.h>

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <deque>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

// Custom window message used to hand media state snapshots produced on the
// background GSMTC thread over to the platform thread.
constexpr UINT kMediaBridgeEventMessage = WM_APP + 0x2D1;

// Bridges Dart's MediaSessionService to the Windows Global System Media
// Transport Controls (GSMTC), which is the direct analog of Android's
// MediaSessionManager + MediaController.
//
// Channel names are kept identical to the Android implementation so that
// lib/services/media_session_service.dart works unmodified on both platforms.
//
// All WinRT work is funnelled onto a single background MTA thread; results are
// marshalled back to the platform thread via a window message so that the
// EventSink is only ever touched from the thread that owns the Flutter engine.
class MediaBridge {
 public:
  MediaBridge(HWND message_window, flutter::BinaryMessenger* messenger);
  ~MediaBridge();

  // Starts the background GSMTC worker. Call once, after Flutter is ready.
  void Start();

  // Platform thread. Drains snapshots queued by the worker and forwards them
  // to Dart over the event channel.
  void FlushPendingEvents();

 private:
  using EncodableValue = flutter::EncodableValue;
  using EncodableMap = flutter::EncodableMap;
  using AutoRepeatMode = winrt::Windows::Media::MediaPlaybackAutoRepeatMode;
  using PlaybackStatus =
      winrt::Windows::Media::Control::
          GlobalSystemMediaTransportControlsSessionPlaybackStatus;
  using Session =
      winrt::Windows::Media::Control::GlobalSystemMediaTransportControlsSession;
  using SessionManager =
      winrt::Windows::Media::Control::
          GlobalSystemMediaTransportControlsSessionManager;

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void ThreadMain();
  void PostTask(std::function<void()> task);
  void QueueState(EncodableMap state);

  void RefreshActiveSession();
  void DetachActiveSession();
  Session ResolveCurrentSession();
  void PublishState();
  void InvokeTransport(const std::function<void(Session)>& action);

  // Suppresses redundant event-channel snapshots. GSMTC plus the Dart-side
  // refresh timer produce far more updates than the UI can use, and every
  // duplicate can re-trigger work in Dart.
  bool IsStatePublishable(const EncodableMap& state) const;
  void RememberPublishedState(const EncodableMap& state);

  HWND message_window_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      method_channel_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>>
      event_channel_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> event_sink_;

  std::thread worker_;
  std::mutex task_mutex_;
  std::condition_variable task_cv_;
  std::deque<std::function<void()>> tasks_;
  std::atomic<bool> shutting_down_{false};

  std::mutex queue_mutex_;
  std::vector<EncodableMap> pending_states_;
  std::atomic<bool> post_pending_{false};
  // Written on the platform thread, read on the worker thread.
  std::atomic<bool> sink_attached_{false};

  // Worker-thread-only state.
  SessionManager manager_{nullptr};
  winrt::event_token sessions_changed_token_{};
  winrt::event_token current_session_changed_token_{};
  Session active_session_{nullptr};
  winrt::event_token playback_info_token_{};
  winrt::event_token timeline_token_{};
  winrt::event_token media_properties_token_{};

  // Playback bookkeeping used to keep position in sync between GSMTC updates.
  //
  // GSMTC only refreshes MediaPlaybackTimelineProperties.Position when the
  // source app chooses to, which can be once every few seconds (or never, for
  // some players). Between those updates the real playback position has moved,
  // so the reported position is extrapolated from
  // (now - timeline.LastUpdatedTime) * PlaybackRate.
  bool last_playing_{false};
  bool tick_wanted_{false};
  bool has_raw_position_{false};
  int64_t last_raw_position_{0};
  int64_t last_gsm_position_{0};
  std::chrono::steady_clock::time_point last_raw_sampled_at_{};

  // Last metadata successfully read from the active session.
  //
  // `TryGetMediaPropertiesAsync()` throws regularly while the source app is
  // switching tracks or tearing its session down. Re-initialising the locals
  // on every publish meant one transient failure shipped "No media playing"
  // with empty artist/album, which changes Dart's track key and makes it throw
  // away lyrics that were correct a moment ago. The cache is invalidated when
  // the session itself changes, never on a read failure.
  bool has_metadata_{false};
  std::string metadata_title_;
  std::string metadata_artist_;
  std::string metadata_album_;

  bool has_published_{false};
  EncodableMap last_published_{};
  int64_t last_published_position_{0};
  std::chrono::steady_clock::time_point last_published_at_{};
};

#endif  // RUNNER_MEDIA_BRIDGE_H_