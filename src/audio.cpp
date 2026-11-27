#include "audio.h"

#include <QCoreApplication>
#include <QJSEngine>

#include "audiobackend.h"
#include "mediakeys.h"
#include "mpvbackend.h"
#include "session.h"
#include "winrtbackend.h"

Audio::Audio(QObject* parent) : QObject(parent) {
  // mpv when there is one (KLEULIR_AUDIO=windows skips it, for comparing the two).
  const QString mpv = qEnvironmentVariable("KLEULIR_AUDIO") == "windows" ? QString() : MpvBackend::findExecutable();
  if (!mpv.isEmpty())
    useBackend(new MpvBackend(mpv, this));
  else
    useBackend(new WinRtBackend(this));
}

Audio* Audio::instance() {
  static Audio* audio = new Audio(QCoreApplication::instance());
  return audio;
}

Audio* Audio::create(QQmlEngine*, QJSEngine*) {
  QJSEngine::setObjectOwnership(instance(), QJSEngine::CppOwnership);
  return instance();
}

void Audio::useBackend(AudioBackend* backend) {
  backend_ = backend;
  backend_->setVolume(volume_);
  backend_->setMuted(muted_);

  connect(backend_, &AudioBackend::positionChanged, this, &Audio::positionChanged);
  connect(backend_, &AudioBackend::advanced, this, [this] {
    if (nextId_.isEmpty()) return;
    const QString ended = trackId_;
    trackId_ = nextId_;
    meta_ = nextMeta_;
    nextId_.clear();
    countPlay(ended);
    showOnMediaKeys();
    emit advanced(trackId_);
  });
  connect(backend_, &AudioBackend::finished, this, [this] {
    if (trackId_.isEmpty()) return;
    const QString id = trackId_;
    trackId_.clear();
    nextId_.clear();
    countPlay(id);
    if (keys_) keys_->setState(MediaKeys::Stopped);
    emit finished(id);
  });
  connect(backend_, &AudioBackend::failed, this, [this](const QString& reason) {
    const QString id = trackId_;
    trackId_.clear();
    nextId_.clear();
    if (keys_) keys_->setState(MediaKeys::Stopped);
    if (!id.isEmpty()) emit failed(id, reason);
  });
  connect(backend_, &AudioBackend::statusChanged, this, [this] {
    // mpv went away while running: carry on with the Windows player.
    if (!backend_->ok() && backend_->name() == "mpv") {
      qWarning("kleulir: %s Falling back to the Windows media player.", qUtf8Printable(backend_->problem()));
      // Stop listening to it first: it is about to be replaced.
      disconnect(backend_, nullptr, this, nullptr);
      backend_->deleteLater();
      delete keys_;
      keys_ = nullptr;
      useBackend(new WinRtBackend(this));
    }
    emit statusChanged();
  });

  if (backend_->ownsMediaKeys()) {
    connect(backend_, &AudioBackend::pausedChanged, this, [this](bool paused) {
      paused_ = paused;
      emit pausedChanged(paused);
    });
    connect(backend_, &AudioBackend::nextRequested, this, &Audio::nextRequested);
    connect(backend_, &AudioBackend::previousRequested, this, &Audio::previousRequested);
  } else {
    keys_ = new MediaKeys(this);
    connect(keys_, &MediaKeys::playRequested, this, [this] {
      if (trackId_.isEmpty()) return;
      setPaused(false);
      emit pausedChanged(false);
    });
    connect(keys_, &MediaKeys::pauseRequested, this, [this] {
      if (trackId_.isEmpty()) return;
      setPaused(true);
      emit pausedChanged(true);
    });
    connect(keys_, &MediaKeys::nextRequested, this, &Audio::nextRequested);
    connect(keys_, &MediaKeys::previousRequested, this, &Audio::previousRequested);
  }
  emit statusChanged();
}

bool Audio::available() const { return backend_->ok(); }
QString Audio::problem() const { return backend_->problem(); }
QString Audio::backendName() const { return backend_->name(); }
double Audio::position() const { return backend_->position(); }

QVariantMap Audio::withCoverUrl(const QVariantMap& meta) const {
  QVariantMap out = meta;
  const QString cover = meta.value("coverArt").toString();
  const auto api = Session::instance()->api();
  if (api && !cover.isEmpty())
    out["coverUrl"] = QString::fromStdString(api->cover_art_url(cover.toStdString(), 320));
  return out;
}

// The playing device counts the play (docs/sync.md); the server does not.
void Audio::countPlay(const QString& trackId) {
  // A screenshot run is a test: it must not add to the play counts.
  if (trackId.isEmpty() || qEnvironmentVariableIsSet("KLEULIR_SCREENSHOT")) return;
  if (auto api = Session::instance()->api()) {
    Session::async([api, trackId] {
      try {
        api->scrobble(trackId.toStdString());
      } catch (const std::exception&) {
        // Offline: the play is not counted. Queuing these for later is still to do.
      }
    });
  }
}

void Audio::showOnMediaKeys() {
  if (!keys_) return;
  keys_->setTrack(meta_);
  keys_->setState(paused_ ? MediaKeys::Paused : MediaKeys::Playing);
}

void Audio::play(const QString& trackId, double startSeconds, bool paused, const QVariantMap& meta) {
  const auto api = Session::instance()->api();
  if (!backend_->ok() || !api || trackId.isEmpty()) return;

  trackId_ = trackId;
  nextId_.clear();
  meta_ = withCoverUrl(meta);
  paused_ = paused;
  backend_->play(QString::fromStdString(api->stream_url(trackId.toStdString())), startSeconds, paused, meta_);
  showOnMediaKeys();
}

void Audio::setNext(const QString& trackId, const QVariantMap& meta) {
  const auto api = Session::instance()->api();
  if (trackId_.isEmpty() || trackId == nextId_) return;

  if (trackId.isEmpty() || !api) {
    nextId_.clear();
    backend_->setNext({}, {});
    return;
  }
  nextId_ = trackId;
  nextMeta_ = withCoverUrl(meta);
  backend_->setNext(QString::fromStdString(api->stream_url(trackId.toStdString())), nextMeta_);
}

void Audio::setPaused(bool paused) {
  if (trackId_.isEmpty()) return;
  paused_ = paused;
  backend_->setPaused(paused);
  if (keys_) keys_->setState(paused ? MediaKeys::Paused : MediaKeys::Playing);
}

void Audio::seek(double seconds) {
  if (!trackId_.isEmpty()) backend_->seek(seconds);
}

void Audio::stop() {
  trackId_.clear();
  nextId_.clear();
  backend_->stop();
  if (keys_) keys_->setState(MediaKeys::Stopped);
}

void Audio::setVolume(int percent) {
  volume_ = qBound(0, percent, 100);
  backend_->setVolume(volume_);
}

void Audio::setMuted(bool muted) {
  muted_ = muted;
  backend_->setMuted(muted);
}
