#include "winrtbackend.h"

#include <QTimer>

#include <chrono>
#include <cmath>

#include <winrt/Windows.Foundation.Collections.h>
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

// One track as the player wants it: the stream, plus what the system shows for the
// media keys and the volume flyout.
MediaPlaybackItem makeItem(const QString& url, const QVariantMap& meta) {
  MediaPlaybackItem item(MediaSource::CreateFromUri(Uri(hs(url))));

  auto shown = item.GetDisplayProperties();
  shown.Type(winrt::Windows::Media::MediaPlaybackType::Music);
  shown.MusicProperties().Title(hs(meta.value("title").toString()));
  shown.MusicProperties().Artist(hs(meta.value("artist").toString()));
  shown.MusicProperties().AlbumTitle(hs(meta.value("album").toString()));
  const QString cover = meta.value("coverUrl").toString();
  if (!cover.isEmpty())
    shown.Thumbnail(winrt::Windows::Storage::Streams::RandomAccessStreamReference::CreateFromUri(Uri(hs(cover))));
  item.ApplyDisplayProperties(shown);
  return item;
}

}  // namespace

struct WinRtBackend::Impl {
  MediaPlayer player{nullptr};
  MediaPlaybackList list{nullptr};
  MediaPlayer::MediaOpened_revoker opened;
  MediaPlayer::MediaEnded_revoker ended;
  MediaPlayer::MediaFailed_revoker failed;
  MediaPlaybackList::CurrentItemChanged_revoker itemChanged;
  MediaPlaybackCommandManager::NextReceived_revoker next;
  MediaPlaybackCommandManager::PreviousReceived_revoker previous;
};

WinRtBackend::WinRtBackend(QObject* parent) : AudioBackend(parent), impl_(std::make_unique<Impl>()) {
  // Qt has already initialised COM on this thread; the player's events arrive on
  // other threads and are passed back to the main thread before touching state.
  try {
    impl_->player = MediaPlayer();
    MediaPlayer& player = impl_->player;
    player.AutoPlay(false);
    player.AudioCategory(MediaPlayerAudioCategory::Media);

    impl_->opened = player.MediaOpened(auto_revoke, [this](MediaPlayer const& p, IInspectable const&) {
      // A start position only sticks once the media is open.
      const double start = pendingStart_.exchange(0);
      if (start > 0.5) p.PlaybackSession().Position(toSpan(start));
    });

    // The whole list has played: the current track was the last.
    impl_->ended = player.MediaEnded(auto_revoke, [this](MediaPlayer const&, IInspectable const&) {
      const int serial = serial_.load();
      Session::onMain([this, serial] {
        if (serial != serial_.load() || !loaded_) return;
        loaded_ = false;
        hasNext_ = false;
        emit finished();
      });
    });

    impl_->failed = player.MediaFailed(auto_revoke, [this](MediaPlayer const&, MediaPlayerFailedEventArgs const& args) {
      const int serial = serial_.load();
      const QString reason = QString::fromStdWString(std::wstring(args.ErrorMessage()));
      Session::onMain([this, serial, reason] {
        if (serial != serial_.load() || !loaded_) return;
        loaded_ = false;
        hasNext_ = false;
        emit failed(reason.isEmpty() ? QStringLiteral("The track could not be played.") : reason);
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

    ok_ = true;
    applyVolume();
  } catch (const hresult_error& e) {
    problem_ = QStringLiteral("Windows audio player could not be created: ") +
               QString::fromStdWString(std::wstring(e.message()));
  }

  pollTimer_ = new QTimer(this);
  pollTimer_->setInterval(200);
  connect(pollTimer_, &QTimer::timeout, this, &WinRtBackend::poll);
  if (ok_) pollTimer_->start();
}

WinRtBackend::~WinRtBackend() {
  if (impl_->player) {
    impl_->opened.revoke();
    impl_->ended.revoke();
    impl_->failed.revoke();
    impl_->itemChanged.revoke();
    impl_->next.revoke();
    impl_->previous.revoke();
    try {
      impl_->player.Source(nullptr);
      impl_->player.Close();
    } catch (const hresult_error&) {
    }
  }
}

void WinRtBackend::poll() {
  if (!loaded_) return;
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

void WinRtBackend::applyVolume() {
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

void WinRtBackend::play(const QString& url, double startSeconds, bool paused, const QVariantMap& meta) {
  if (!ok_) return;

  const int serial = ++serial_;
  loaded_ = true;
  hasNext_ = false;
  pendingStart_ = startSeconds;
  position_ = startSeconds;
  lastState_ = -1;
  gainDb_ = meta.value("gain").toDouble();
  emit positionChanged();

  try {
    impl_->itemChanged.revoke();
    impl_->list = MediaPlaybackList();
    impl_->list.AutoRepeatEnabled(false);
    impl_->list.Items().Append(makeItem(url, meta));

    // The player moved on to the next item of the list.
    impl_->itemChanged = impl_->list.CurrentItemChanged(
        auto_revoke, [this, serial](MediaPlaybackList const&, CurrentMediaPlaybackItemChangedEventArgs const& args) {
          if (args.Reason() != MediaPlaybackItemChangedReason::EndOfStream || !args.NewItem()) return;
          Session::onMain([this, serial] {
            if (serial != serial_.load() || !hasNext_) return;
            hasNext_ = false;
            gainDb_ = nextGainDb_;
            position_ = 0;
            applyVolume();
            emit positionChanged();
            emit advanced();
          });
        });

    applyVolume();
    impl_->player.Source(impl_->list);
    if (paused)
      impl_->player.Pause();
    else
      impl_->player.Play();
  } catch (const hresult_error& e) {
    loaded_ = false;
    emit failed(QString::fromStdWString(std::wstring(e.message())));
  }
}

void WinRtBackend::setNext(const QString& url, const QVariantMap& meta) {
  if (!impl_->list || !loaded_) return;

  try {
    auto items = impl_->list.Items();
    // Keep what is playing (and anything before it); replace what follows.
    // Right after play() the list has not started yet and reports no current
    // index (UINT32_MAX): the one item in it is the current track.
    const uint32_t index = impl_->list.CurrentItemIndex();
    const uint32_t keep = index == UINT32_MAX ? 1 : index + 1;
    while (items.Size() > keep) items.RemoveAtEnd();
    hasNext_ = false;
    if (!url.isEmpty()) {
      items.Append(makeItem(url, meta));
      hasNext_ = true;
      nextGainDb_ = meta.value("gain").toDouble();
    }
  } catch (const hresult_error&) {
    hasNext_ = false;  // the current track simply ends; finished() follows
  }
}

void WinRtBackend::setPaused(bool paused) {
  if (!impl_->player || !loaded_) return;
  try {
    if (paused)
      impl_->player.Pause();
    else
      impl_->player.Play();
  } catch (const hresult_error&) {
  }
}

void WinRtBackend::seek(double seconds) {
  if (!impl_->player || !loaded_) return;
  position_ = seconds;
  emit positionChanged();
  try {
    impl_->player.PlaybackSession().Position(toSpan(seconds));
  } catch (const hresult_error&) {
  }
}

void WinRtBackend::stop() {
  ++serial_;
  loaded_ = false;
  hasNext_ = false;
  if (!impl_->player) return;
  try {
    impl_->itemChanged.revoke();
    impl_->player.Pause();
    impl_->player.Source(nullptr);
    impl_->list = nullptr;
  } catch (const hresult_error&) {
  }
}

void WinRtBackend::setVolume(int percent) {
  volume_ = qBound(0, percent, 100);
  applyVolume();
}

void WinRtBackend::setMuted(bool muted) {
  muted_ = muted;
  applyVolume();
}
