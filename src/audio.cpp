#include "audio.h"

#include <QCoreApplication>
#include <QJSEngine>
#include <QTimer>

#include <chrono>
#include <cmath>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Media.Core.h>
#include <winrt/Windows.Media.Playback.h>
#include <winrt/Windows.Media.h>
#include <winrt/Windows.Storage.Streams.h>

#include "session.h"

using namespace winrt;
using namespace winrt::Windows::Foundation;
using namespace winrt::Windows::Media::Core;
using namespace winrt::Windows::Media::Playback;

namespace {

hstring hs(const QString& s) { return hstring(s.toStdWString()); }

TimeSpan toSpan(double seconds) {
  return std::chrono::duration_cast<TimeSpan>(std::chrono::duration<double>(seconds));
}

double toSeconds(TimeSpan span) { return std::chrono::duration<double>(span).count(); }

}  // namespace

struct Audio::Impl {
  MediaPlayer player{nullptr};
  MediaPlayer::MediaOpened_revoker opened;
  MediaPlayer::MediaEnded_revoker ended;
  MediaPlayer::MediaFailed_revoker failed;
  MediaPlaybackCommandManager::NextReceived_revoker next;
  MediaPlaybackCommandManager::PreviousReceived_revoker previous;
};

Audio::Audio(QObject* parent) : QObject(parent), impl_(std::make_unique<Impl>()) {
  // Qt has already initialised COM on this thread; the player's events arrive on
  // other threads and are passed back to the main thread before touching state.
  try {
    impl_->player = MediaPlayer();
    MediaPlayer& player = impl_->player;
    player.AutoPlay(false);
    player.AudioCategory(MediaPlayerAudioCategory::Media);

    impl_->opened = player.MediaOpened(auto_revoke, [this](MediaPlayer const& p, IInspectable const&) {
      // A start position only sticks once the media is open.
      const double start = pendingStart_;
      if (start > 0.5) p.PlaybackSession().Position(toSpan(start));
    });

    impl_->ended = player.MediaEnded(auto_revoke, [this](MediaPlayer const&, IInspectable const&) {
      const int serial = serial_.load();
      Session::onMain([this, serial] {
        if (serial != serial_.load() || trackId_.isEmpty()) return;
        const QString id = trackId_;
        trackId_.clear();
        // The playing device counts the play (docs/sync.md); the server does not.
        if (auto api = Session::instance()->api()) {
          Session::async([api, id] {
            try {
              api->scrobble(id.toStdString());
            } catch (const std::exception&) {
              // Offline: the play is not counted. Queuing these for later is still to do.
            }
          });
        }
        emit finished(id);
      });
    });

    impl_->failed = player.MediaFailed(auto_revoke, [this](MediaPlayer const&, MediaPlayerFailedEventArgs const& args) {
      const int serial = serial_.load();
      const QString reason = QString::fromStdWString(std::wstring(args.ErrorMessage()));
      Session::onMain([this, serial, reason] {
        if (serial != serial_.load() || trackId_.isEmpty()) return;
        const QString id = trackId_;
        trackId_.clear();
        emit failed(id, reason.isEmpty() ? QStringLiteral("The track could not be played.") : reason);
      });
    });

    // Media keys and the system flyout. Play and pause act on the player by
    // themselves; next and previous are ours to carry out.
    auto commands = player.CommandManager();
    commands.IsEnabled(true);
    commands.NextBehavior().EnablingRule(MediaCommandEnablingRule::Always);
    commands.PreviousBehavior().EnablingRule(MediaCommandEnablingRule::Always);
    impl_->next = commands.NextReceived(
        auto_revoke, [this](MediaPlaybackCommandManager const&, MediaPlaybackCommandManagerNextReceivedEventArgs const& args) {
          args.Handled(true);
          Session::onMain([this] { emit nextRequested(); });
        });
    impl_->previous = commands.PreviousReceived(
        auto_revoke,
        [this](MediaPlaybackCommandManager const&, MediaPlaybackCommandManagerPreviousReceivedEventArgs const& args) {
          args.Handled(true);
          Session::onMain([this] { emit previousRequested(); });
        });

    available_ = true;
    applyVolume();
  } catch (const hresult_error& e) {
    problem_ = QStringLiteral("Windows audio player could not be created: ") +
               QString::fromStdWString(std::wstring(e.message()));
  }

  pollTimer_ = new QTimer(this);
  pollTimer_->setInterval(200);
  connect(pollTimer_, &QTimer::timeout, this, &Audio::poll);
  if (available_) pollTimer_->start();
}

Audio::~Audio() {
  if (impl_->player) {
    impl_->opened.revoke();
    impl_->ended.revoke();
    impl_->failed.revoke();
    impl_->next.revoke();
    impl_->previous.revoke();
    try {
      impl_->player.Source(nullptr);
          impl_->player.Close();
    } catch (const hresult_error&) {
    }
  }
}

Audio* Audio::instance() {
  static Audio* audio = new Audio(QCoreApplication::instance());
  return audio;
}

Audio* Audio::create(QQmlEngine*, QJSEngine*) {
  QJSEngine::setObjectOwnership(instance(), QJSEngine::CppOwnership);
  return instance();
}

void Audio::poll() {
  if (trackId_.isEmpty()) return;
  try {
    auto session = impl_->player.PlaybackSession();
    const double now = toSeconds(session.Position());
    if (std::abs(now - position_) > 0.05) {
      position_ = now;
      emit positionChanged();
    }
    // Follow pause/resume that came from outside the app.
    const auto state = session.PlaybackState();
    if (state == MediaPlaybackState::Playing || state == MediaPlaybackState::Paused) {
      const int value = static_cast<int>(state);
      if (lastState_ != value) {
        lastState_ = value;
        emit pausedChanged(state == MediaPlaybackState::Paused);
      }
    }
  } catch (const hresult_error&) {
  }
}

void Audio::applyVolume() {
  if (!impl_->player) return;
  // ReplayGain is applied as a volume factor. The player cannot amplify, so a
  // positive gain is capped at full volume.
  const double factor = std::pow(10.0, gainDb_ / 20.0);
  try {
    impl_->player.Volume(std::clamp(volume_ / 100.0 * factor, 0.0, 1.0));
    impl_->player.IsMuted(muted_);
  } catch (const hresult_error&) {
  }
}

void Audio::play(const QString& trackId, double startSeconds, bool paused, const QVariantMap& meta) {
  const auto api = Session::instance()->api();
  if (!available_ || !api || trackId.isEmpty()) return;

  ++serial_;
  trackId_ = trackId;
  pendingStart_ = startSeconds;
  position_ = startSeconds;
  lastState_ = -1;
  gainDb_ = meta.value("gain").toDouble();
  emit positionChanged();

  try {
    const QString url = QString::fromStdString(api->stream_url(trackId.toStdString()));
    MediaPlaybackItem item(MediaSource::CreateFromUri(Uri(hs(url))));

    // What the system shows for the media keys and the volume flyout.
    auto shown = item.GetDisplayProperties();
    shown.Type(winrt::Windows::Media::MediaPlaybackType::Music);
    shown.MusicProperties().Title(hs(meta.value("title").toString()));
    shown.MusicProperties().Artist(hs(meta.value("artist").toString()));
    shown.MusicProperties().AlbumTitle(hs(meta.value("album").toString()));
    const QString cover = meta.value("coverArt").toString();
    if (!cover.isEmpty()) {
      const QString coverUrl = QString::fromStdString(api->cover_art_url(cover.toStdString(), 320));
      shown.Thumbnail(winrt::Windows::Storage::Streams::RandomAccessStreamReference::CreateFromUri(Uri(hs(coverUrl))));
    }
    item.ApplyDisplayProperties(shown);

    applyVolume();
    impl_->player.Source(item);
    if (paused)
      impl_->player.Pause();
    else
      impl_->player.Play();
  } catch (const hresult_error& e) {
    const QString id = trackId_;
    trackId_.clear();
    emit failed(id, QString::fromStdWString(std::wstring(e.message())));
  }
}

void Audio::setPaused(bool paused) {
  if (!impl_->player || trackId_.isEmpty()) return;
  try {
    if (paused)
      impl_->player.Pause();
    else
      impl_->player.Play();
  } catch (const hresult_error&) {
  }
}

void Audio::seek(double seconds) {
  if (!impl_->player || trackId_.isEmpty()) return;
  position_ = seconds;
  emit positionChanged();
  try {
    impl_->player.PlaybackSession().Position(toSpan(seconds));
  } catch (const hresult_error&) {
  }
}

void Audio::stop() {
  ++serial_;
  trackId_.clear();
  if (!impl_->player) return;
  try {
    impl_->player.Pause();
    impl_->player.Source(nullptr);
  } catch (const hresult_error&) {
  }
}

void Audio::setVolume(int percent) {
  volume_ = qBound(0, percent, 100);
  applyVolume();
}

void Audio::setMuted(bool muted) {
  muted_ = muted;
  applyVolume();
}
