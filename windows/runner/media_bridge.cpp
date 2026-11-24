#include "media_bridge.h"

#include <cstdint>
#include <cstdlib>
#include <utility>
#include <variant>

namespace {

// Must match the sentinel the Dart MediaState uses to detect "nothing playing"
// (see lib/models/media_state.dart MediaState.isEmpty).
constexpr char kNoMediaTitle[] = "No media playing";

// WinRT TimeSpan is expressed in 100-nanosecond ticks.
constexpr int64_t kTicksPerMillisecond = 10000;

// If the extrapolation anchor is older than this the source app has gone quiet
// (suspended, crashed, or stopped updating) and our estimate is worthless, so
// fall back to whatever the app last told us.
constexpr int64_t kMaxExtrapolationMs = 5000;
// GSMTC LastUpdatedTime catch-up smaller than this is sampling noise, not a
// seek. Re-anchoring on it makes the Dart clock hitch every metadata tick.
constexpr int64_t kAnchorNoiseMs = 80;

// Cadence of our own position clock while something is playing. Matches the
// cadence Dart asks for via refreshState(), so the two stay in step.
constexpr std::chrono::milliseconds kPositionTickInterval{250};

// These mirror android.media.session.PlaybackState so the existing Dart UI can
// be reused verbatim:
//   REPEAT_MODE_NONE = 0, REPEAT_MODE_ONE = 2, REPEAT_MODE_ALL = 3
//   SHUFFLE_MODE_NONE = 0, SHUFFLE_MODE_ALL = 1
constexpr int64_t kRepeatModeNone = 0;
constexpr int64_t kRepeatModeOne = 2;
constexpr int64_t kRepeatModeAll = 3;
constexpr int64_t kShuffleModeNone = 0;
constexpr int64_t kShuffleModeAll = 1;

// Windows.Media.MediaPlaybackAutoRepeatMode backing values.
constexpr int32_t kAutoRepeatNone = 0;
constexpr int32_t kAutoRepeatOne = 1;
constexpr int32_t kAutoRepeatAll = 2;

int64_t TicksToMilliseconds(int64_t ticks) {
  return ticks / kTicksPerMillisecond;
}

// Milliseconds between the position of the snapshot we published last and the
// one we are about to publish. Below this the UI cannot show a difference, so
// the snapshot is dropped.
constexpr int64_t kMinimumPositionDeltaMs = 200;

// Dart sends integers across the standard codec as int64.
int64_t ReadIntArgument(const flutter::EncodableValue* arguments) {
  if (arguments == nullptr) {
    return 0;
  }
  if (const auto* value = std::get_if<int64_t>(arguments)) {
    return *value;
  }
  if (const auto* value = std::get_if<int32_t>(arguments)) {
    return *value;
  }
  if (const auto* value = std::get_if<double>(arguments)) {
    return static_cast<int64_t>(*value);
  }
  return 0;
}

int64_t RepeatModeToDart(
    winrt::Windows::Media::MediaPlaybackAutoRepeatMode mode) {
  // The Windows SDK's C++/WinRT headers declare MediaPlaybackAutoRepeatMode but
  // never emit its enumerators, so switch on the documented int values:
  // None = 0, One = 1, All = 2.
  switch (static_cast<int32_t>(mode)) {
    case kAutoRepeatOne:
      return kRepeatModeOne;
    case kAutoRepeatAll:
      return kRepeatModeAll;
    default:
      return kRepeatModeNone;
  }
}

winrt::Windows::Media::MediaPlaybackAutoRepeatMode RepeatModeFromDart(
    int64_t mode) {
  if (mode == kRepeatModeOne) {
    return static_cast<winrt::Windows::Media::MediaPlaybackAutoRepeatMode>(
        kAutoRepeatOne);
  }
  if (mode == kRepeatModeAll) {
    return static_cast<winrt::Windows::Media::MediaPlaybackAutoRepeatMode>(
        kAutoRepeatAll);
  }
  return static_cast<winrt::Windows::Media::MediaPlaybackAutoRepeatMode>(
      kAutoRepeatNone);
}

}  // namespace

MediaBridge::MediaBridge(HWND message_window,
                         flutter::BinaryMessenger* messenger)
    : message_window_(message_window) {
  method_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "com.simplelyrics/media",
          &flutter::StandardMethodCodec::GetInstance());
  method_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        HandleMethodCall(call, std::move(result));
      });

  event_channel_ =
      std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
          messenger, "com.simplelyrics/media_events",
          &flutter::StandardMethodCodec::GetInstance());
  event_channel_->SetStreamHandler(
      std::make_unique<flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
          [this](const flutter::EncodableValue* arguments,
                 std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>
                     events) {
            event_sink_ = std::move(events);
            sink_attached_.store(true);
            // Mirror the Android listener, which emits an initial snapshot as
            // soon as Dart subscribes.
            PostTask([this] { PublishState(); });
            return nullptr;
          },
          [this](const flutter::EncodableValue* arguments) {
            event_sink_ = nullptr;
            sink_attached_.store(false);
            return nullptr;
          }));
}

MediaBridge::~MediaBridge() {
  shutting_down_.store(true);
  {
    std::lock_guard<std::mutex> lock(task_mutex_);
    tasks_.clear();
  }
  task_cv_.notify_all();

  if (worker_.joinable()) {
    worker_.join();
  }

  if (event_channel_) {
    event_channel_->SetStreamHandler(nullptr);
  }
  if (method_channel_) {
    method_channel_->SetMethodCallHandler(nullptr);
  }
}

void MediaBridge::Start() {
  worker_ = std::thread(&MediaBridge::ThreadMain, this);
}

void MediaBridge::FlushPendingEvents() {
  // Clear the flag *before* draining. If the worker queues another snapshot
  // while we drain, it will post a fresh window message instead of having that
  // snapshot silently swallowed.
  post_pending_.store(false);

  std::vector<EncodableMap> states;
  {
    std::lock_guard<std::mutex> lock(queue_mutex_);
    states.swap(pending_states_);
  }

  if (!event_sink_) {
    return;
  }
  for (auto& state : states) {
    event_sink_->Success(EncodableValue(std::move(state)));
  }
}

// ─── Method channel ──────────────────────────────────────────────────────

void MediaBridge::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto& method = call.method_name();
  const auto* arguments = call.arguments();

  // Android gates the whole UI behind NotificationListenerService consent.
  // GSMTC has no equivalent requirement, so the gate is always open here.
  if (method == "isPermissionGranted") {
    result->Success(EncodableValue(true));
    return;
  }
  if (method == "requestPermission") {
    result->Success(EncodableValue());
    return;
  }

  if (method == "refreshState") {
    PostTask([this] { PublishState(); });
    result->Success(EncodableValue());
    return;
  }

  if (method == "play") {
    PostTask([this] {
      InvokeTransport(
          [](Session session) { (void)session.TryPlayAsync().get(); });
    });
    result->Success(EncodableValue());
    return;
  }

  if (method == "pause") {
    PostTask([this] {
      InvokeTransport(
          [](Session session) { (void)session.TryPauseAsync().get(); });
    });
    result->Success(EncodableValue());
    return;
  }

  if (method == "next") {
    PostTask([this] {
      InvokeTransport(
          [](Session session) { (void)session.TrySkipNextAsync().get(); });
    });
    result->Success(EncodableValue());
    return;
  }

  if (method == "previous") {
    PostTask([this] {
      InvokeTransport(
          [](Session session) { (void)session.TrySkipPreviousAsync().get(); });
    });
    result->Success(EncodableValue());
    return;
  }

  if (method == "seekTo") {
    const int64_t position_ms = ReadIntArgument(arguments);
    PostTask([this, position_ms] {
      InvokeTransport([position_ms](Session session) {
        // TryChangePlaybackPositionAsync takes a raw tick count (100 ns units),
        // not a TimeSpan.
        (void)session
            .TryChangePlaybackPositionAsync(position_ms *
                                            kTicksPerMillisecond)
            .get();
      });
    });
    result->Success(EncodableValue());
    return;
  }

  if (method == "setShuffleMode") {
    const bool shuffle = ReadIntArgument(arguments) != kShuffleModeNone;
    PostTask([this, shuffle] {
      InvokeTransport([shuffle](Session session) {
        (void)session.TryChangeShuffleActiveAsync(shuffle).get();
      });
    });
    result->Success(EncodableValue());
    return;
  }

  if (method == "setRepeatMode") {
    const AutoRepeatMode repeat = RepeatModeFromDart(ReadIntArgument(arguments));
    PostTask([this, repeat] {
      InvokeTransport([repeat](Session session) {
        (void)session.TryChangeAutoRepeatModeAsync(repeat).get();
      });
    });
    result->Success(EncodableValue());
    return;
  }

  result->NotImplemented();
}

// ─── Worker thread ───────────────────────────────────────────────────────

void MediaBridge::PostTask(std::function<void()> task) {
  if (shutting_down_.load()) {
    return;
  }
  {
    std::lock_guard<std::mutex> lock(task_mutex_);
    if (shutting_down_.load()) {
      return;
    }
    tasks_.push_back(std::move(task));
  }
  task_cv_.notify_one();
}

void MediaBridge::ThreadMain() {
  winrt::init_apartment(winrt::apartment_type::multi_threaded);

  try {
    manager_ = winrt::Windows::Media::Control::
        GlobalSystemMediaTransportControlsSessionManager::RequestAsync().get();
  } catch (const winrt::hresult_error&) {
    manager_ = nullptr;
  }

  if (manager_) {
    sessions_changed_token_ = manager_.SessionsChanged(
        [this](const MediaBridge::SessionManager&,
               const winrt::Windows::Media::Control::
                   SessionsChangedEventArgs&) {
          PostTask([this] { PublishState(); });
        });
    current_session_changed_token_ = manager_.CurrentSessionChanged(
        [this](const MediaBridge::SessionManager&,
               const winrt::Windows::Media::Control::
                   CurrentSessionChangedEventArgs&) {
          PostTask([this] { PublishState(); });
        });
  }

  for (;;) {
    std::function<void()> task;
    bool timed_out = false;
    {
      std::unique_lock<std::mutex> lock(task_mutex_);
      timed_out = !task_cv_.wait_for(
          lock, kPositionTickInterval,
          [this] { return shutting_down_.load() || !tasks_.empty(); });
      if (shutting_down_.load()) {
        break;
      }

      // Source apps update their timeline as rarely as once every few seconds,
      // and some never do at all. Drive our own clock on a fixed cadence while
      // playing so the lyric highlight keeps stepping in real time instead of
      // jumping between the app's refreshes.
      if (timed_out && tick_wanted_ && !task) {
        task = [this] { PublishState(); };
      } else if (!timed_out) {
        task = std::move(tasks_.front());
        tasks_.pop_front();
      }
    }

    if (!task) {
      continue;
    }

    try {
      task();
    } catch (const winrt::hresult_error&) {
      // A source app can disappear mid-call; drop this tick and let the next
      // poll recover.
    }
  }

  // Revoke every delegate before `this` dies: the source apps hold references
  // to our handlers and would otherwise call into freed memory.
  DetachActiveSession();
  if (manager_) {
    manager_.SessionsChanged(sessions_changed_token_);
    manager_.CurrentSessionChanged(current_session_changed_token_);
    manager_ = nullptr;
  }

  winrt::uninit_apartment();
}

void MediaBridge::QueueState(EncodableMap state) {
  // Dart is not listening yet; a snapshot would only pile up stale state that
  // gets replayed the moment it does subscribe.
  if (!sink_attached_.load()) {
    return;
  }
  if (!IsStatePublishable(state)) {
    return;
  }
  RememberPublishedState(state);
  {
    std::lock_guard<std::mutex> lock(queue_mutex_);
    pending_states_.push_back(std::move(state));
  }
  if (!post_pending_.exchange(true)) {
    ::PostMessageW(message_window_, kMediaBridgeEventMessage, 0, 0);
  }
}

// ─── Publish de-duplication ──────────────────────────────────────────────

bool MediaBridge::IsStatePublishable(const EncodableMap& state) const {
  if (!has_published_) {
    return true;
  }

  // Everything except `position` must match exactly. Position is allowed to
  // drift a little so a genuinely advancing clock is still reported, but a
  // paused player re-publishing the same value is suppressed.
  for (const auto& [key, value] : state) {
    if (EncodableValue(key) == EncodableValue("position")) {
      continue;
    }
    const auto it = last_published_.find(key);
    if (it == last_published_.end() || !(it->second == value)) {
      return true;
    }
  }

  // Guard against a key present last time but missing now.
  for (const auto& [key, value] : last_published_) {
    if (EncodableValue(key) == EncodableValue("position")) {
      continue;
    }
    if (state.find(key) == state.end()) {
      return true;
    }
  }

  int64_t position_ms = 0;
  if (const auto position = state.find(EncodableValue("position"));
      position != state.end()) {
    if (const auto* value = std::get_if<int64_t>(&position->second)) {
      position_ms = *value;
    }
  }

  // While playing the position should keep advancing, so only collapse ticks
  // that arrive faster than the UI can render. While paused, suppress entirely.
  if (last_playing_ && std::llabs(position_ms - last_published_position_) <
                           kMinimumPositionDeltaMs) {
    return false;
  }

  return true;
}

void MediaBridge::RememberPublishedState(const EncodableMap& state) {
  last_published_ = state;
  has_published_ = true;
  if (const auto position = state.find(EncodableValue("position"));
      position != state.end()) {
    if (const auto* value = std::get_if<int64_t>(&position->second)) {
      last_published_position_ = *value;
    }
  }
  last_published_at_ = std::chrono::steady_clock::now();
}

// ─── Session tracking ────────────────────────────────────────────────────

MediaBridge::Session MediaBridge::ResolveCurrentSession() {
  if (!manager_) {
    return nullptr;
  }

  if (Session current = manager_.GetCurrentSession()) {
    return current;
  }

  // Fall back to any session that is actively playing, mirroring the Android
  // listener's preference for a STATE_PLAYING controller.
  auto sessions = manager_.GetSessions();
  if (!sessions) {
    return nullptr;
  }
  for (const auto& candidate : sessions) {
    auto info = candidate.GetPlaybackInfo();
    if (info && info.PlaybackStatus() == PlaybackStatus::Playing) {
      return candidate;
    }
  }
  return nullptr;
}

void MediaBridge::RefreshActiveSession() {
  Session next = ResolveCurrentSession();
  if (next == active_session_) {
    return;
  }

  DetachActiveSession();
  active_session_ = next;
  // Position and metadata both belong to the session we just left. Leaving
  // them in place lets the first publish against a new session extrapolate
  // from the old session's anchor, and lets a failed metadata read fall back
  // to the previous track's identity.
  has_raw_position_ = false;
  last_gsm_position_ = 0;
  has_metadata_ = false;
  if (!active_session_) {
    return;
  }

  playback_info_token_ = active_session_.PlaybackInfoChanged(
      [this](const MediaBridge::Session&,
             const winrt::Windows::Media::Control::
                 PlaybackInfoChangedEventArgs&) {
        PostTask([this] { PublishState(); });
      });
  timeline_token_ = active_session_.TimelinePropertiesChanged(
      [this](const MediaBridge::Session&,
             const winrt::Windows::Media::Control::
                 TimelinePropertiesChangedEventArgs&) {
        PostTask([this] { PublishState(); });
      });
  media_properties_token_ = active_session_.MediaPropertiesChanged(
      [this](const MediaBridge::Session&,
             const winrt::Windows::Media::Control::
                 MediaPropertiesChangedEventArgs&) {
        PostTask([this] { PublishState(); });
      });
}

void MediaBridge::DetachActiveSession() {
  if (!active_session_) {
    return;
  }
  active_session_.PlaybackInfoChanged(playback_info_token_);
  active_session_.TimelinePropertiesChanged(timeline_token_);
  active_session_.MediaPropertiesChanged(media_properties_token_);
  active_session_ = nullptr;
}

void MediaBridge::InvokeTransport(const std::function<void(Session)>& action) {
  RefreshActiveSession();
  if (!active_session_) {
    return;
  }
  action(active_session_);
}

// ─── State publishing ────────────────────────────────────────────────────

void MediaBridge::PublishState() {
  RefreshActiveSession();

  EncodableMap state;

  if (!active_session_) {
    tick_wanted_ = false;
    state[EncodableValue("title")] = EncodableValue(kNoMediaTitle);
    state[EncodableValue("artist")] = EncodableValue("");
    state[EncodableValue("album")] = EncodableValue("");
    state[EncodableValue("position")] = EncodableValue(int64_t{0});
    state[EncodableValue("duration")] = EncodableValue(int64_t{0});
    state[EncodableValue("isPlaying")] = EncodableValue(false);
    state[EncodableValue("isAdvancing")] = EncodableValue(false);
    state[EncodableValue("playbackRate")] = EncodableValue(1.0);
    state[EncodableValue("repeatMode")] = EncodableValue(kRepeatModeNone);
    state[EncodableValue("shuffleMode")] = EncodableValue(kShuffleModeNone);
    state[EncodableValue("supportsRepeatMode")] = EncodableValue(false);
    state[EncodableValue("supportsShuffleMode")] = EncodableValue(false);
    QueueState(std::move(state));
    return;
  }

  Session session = active_session_;

  std::string title;
  std::string artist;
  std::string album;
  bool read_ok = false;
  try {
    auto properties = session.TryGetMediaPropertiesAsync().get();
    if (properties) {
      const auto raw_title = properties.Title();
      if (!raw_title.empty()) {
        title = winrt::to_string(raw_title);
      }
      artist = winrt::to_string(properties.Artist());
      album = winrt::to_string(properties.AlbumTitle());
      read_ok = true;
    }
  } catch (const winrt::hresult_error&) {
    // Source app is mid-switch or tearing its session down. Fall through and
    // publish the last metadata we actually saw; reporting "No media playing"
    // here would change Dart's track key and throw away correct lyrics.
  }

  // Title is the primary identity and the thing Dart keys its lyrics fetch on,
  // so only commit a snapshot the app actually filled in — and commit all three
  // fields together, since a partial answer would pair a new title with the
  // previous track's artist.
  if (read_ok && !title.empty()) {
    metadata_title_ = std::move(title);
    metadata_artist_ = std::move(artist);
    metadata_album_ = std::move(album);
    has_metadata_ = true;
  }

  title = has_metadata_ ? metadata_title_ : std::string(kNoMediaTitle);
  artist = has_metadata_ ? metadata_artist_ : std::string();
  album = has_metadata_ ? metadata_album_ : std::string();

  auto info = session.GetPlaybackInfo();

  // Captured before the status block below mutates last_playing_, because the
  // extrapolation anchor has to know what we believed *last* time.
  const bool was_playing = last_playing_;

  bool is_playing = false;
  bool is_advancing = false;
  double rate = 1.0;
  int64_t repeat_mode = kRepeatModeNone;
  int64_t shuffle_mode = kShuffleModeNone;
  bool supports_repeat = false;
  bool supports_shuffle = false;

  if (info) {
    const auto status = info.PlaybackStatus();

    // `Changing` only means "the status is in transition", not "playing".
    // Advancing the clock through it makes lyrics run away from a pause or
    // seek. Keep the previous *glyph* (so the pause button does not flicker)
    // but freeze the clock until we have a definite Playing/Paused.
    if (status == PlaybackStatus::Playing) {
      last_playing_ = true;
    } else if (status == PlaybackStatus::Paused ||
               status == PlaybackStatus::Stopped ||
               status == PlaybackStatus::Closed) {
      last_playing_ = false;
    }
    is_playing = last_playing_;
    is_advancing = status == PlaybackStatus::Playing;

    // These three are nullable WinRT properties (IReference<T>), so each one
    // has to be unwrapped and null-checked explicitly.
    if (const auto value = info.PlaybackRate()) {
      rate = value.Value();
    }
    if (rate <= 0.0) {
      is_advancing = false;
    }
    if (const auto value = info.AutoRepeatMode()) {
      repeat_mode = RepeatModeToDart(value.Value());
    }
    if (const auto value = info.IsShuffleActive()) {
      shuffle_mode = value.Value() ? kShuffleModeAll : kShuffleModeNone;
    }

    auto controls = info.Controls();
    if (controls) {
      supports_repeat = controls.IsRepeatEnabled();
      supports_shuffle = controls.IsShuffleEnabled();
    }
  }

  int64_t position_ms = 0;
  int64_t duration_ms = 0;
  tick_wanted_ = is_advancing;
  try {
    auto timeline = session.GetTimelineProperties();
    if (timeline) {
      duration_ms = TicksToMilliseconds(timeline.EndTime().count());

      // `Position` is only a snapshot of where the source app last looked, and
      // apps refresh it lazily (once every few seconds, or never for some).
      // Anchor on the raw sample with a steady clock and advance it locally.
      // This mirrors the Android listener, which advances
      // playbackState.position by (elapsedRealtime - lastPositionUpdateTime) *
      // playbackSpeed, and is what keeps the lyric highlight and progress bar
      // in step with the audio instead of stepping forward in jumps.
      const int64_t sampled_position =
          TicksToMilliseconds(timeline.Position().count());

      int64_t age_ms = 0;
      if (is_advancing && rate > 0.0) {
        try {
          const auto last_updated = timeline.LastUpdatedTime();
          const auto age = winrt::clock::now() - last_updated;
          age_ms = std::chrono::duration_cast<std::chrono::milliseconds>(age)
                       .count();
          if (age_ms < 0 || age_ms > kMaxExtrapolationMs) {
            age_ms = 0;
          }
        } catch (...) {
          age_ms = 0;
        }
      }

      const bool sample_changed =
          !has_raw_position_ || sampled_position != last_gsm_position_;
      bool should_anchor = sample_changed || !was_playing;

      const int64_t candidate_anchor =
          sampled_position +
          static_cast<int64_t>(static_cast<double>(age_ms) * rate);

      if (should_anchor && has_raw_position_ && was_playing && is_advancing) {
        int64_t current_extrap = last_raw_position_;
        const auto elapsed_ms =
            std::chrono::duration_cast<std::chrono::milliseconds>(
                std::chrono::steady_clock::now() - last_raw_sampled_at_)
                .count();
        if (elapsed_ms > 0 && elapsed_ms <= kMaxExtrapolationMs && rate > 0.0) {
          current_extrap +=
              static_cast<int64_t>(static_cast<double>(elapsed_ms) * rate);
        }
        const int64_t delta = candidate_anchor > current_extrap
                                  ? candidate_anchor - current_extrap
                                  : current_extrap - candidate_anchor;
        if (delta <= kAnchorNoiseMs) {
          // Same timeline, noisier snapshot. Keep the running clock; only
          // remember the raw GSMTC value so the next real change is noticed.
          last_gsm_position_ = sampled_position;
          should_anchor = false;
        }
      }

      if (should_anchor) {
        last_gsm_position_ = sampled_position;
        last_raw_position_ = candidate_anchor;
        last_raw_sampled_at_ = std::chrono::steady_clock::now();
        has_raw_position_ = true;
      }

      position_ms = last_raw_position_;
      if (is_advancing && rate > 0.0) {
        auto elapsed_ms =
            std::chrono::duration_cast<std::chrono::milliseconds>(
                std::chrono::steady_clock::now() - last_raw_sampled_at_)
                .count();

        // If our anchor has gone stale (app went away, or we missed updates
        // while suspended) trust the app's value instead of racing ahead.
        if (elapsed_ms > kMaxExtrapolationMs) {
          elapsed_ms = 0;
          last_raw_sampled_at_ = std::chrono::steady_clock::now();
        }

        position_ms +=
            static_cast<int64_t>(static_cast<double>(elapsed_ms) * rate);
      }

      if (duration_ms > 0 && position_ms > duration_ms) {
        position_ms = duration_ms;
      }
    }
  } catch (const winrt::hresult_error&) {
    // Source app does not expose a timeline; report zeros.
  }

  state[EncodableValue("title")] = EncodableValue(title);
  state[EncodableValue("artist")] = EncodableValue(artist);
  state[EncodableValue("album")] = EncodableValue(album);
  state[EncodableValue("position")] = EncodableValue(position_ms);
  state[EncodableValue("duration")] = EncodableValue(duration_ms);
  state[EncodableValue("isPlaying")] = EncodableValue(is_playing);
  state[EncodableValue("isAdvancing")] = EncodableValue(is_advancing);
  state[EncodableValue("playbackRate")] = EncodableValue(rate);
  state[EncodableValue("repeatMode")] = EncodableValue(repeat_mode);
  state[EncodableValue("shuffleMode")] = EncodableValue(shuffle_mode);
  state[EncodableValue("supportsRepeatMode")] = EncodableValue(supports_repeat);
  state[EncodableValue("supportsShuffleMode")] =
      EncodableValue(supports_shuffle);

  // Note: no `albumArt` key is sent. Dart deliberately ignores native artwork
  // (MediaState.fromMap) and fetches iTunes artwork instead, so shipping the
  // bitmap over the channel would only add per-tick overhead.
  QueueState(std::move(state));
}