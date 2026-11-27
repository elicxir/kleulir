#include "audio.h"

#include <QCoreApplication>
#include <QJSEngine>
#include <QDateTime>
#include <QSettings>
#include <QTimer>

#include "audiobackend.h"
#include "mediakeys.h"
#include "mpvbackend.h"
#include "session.h"
#include "winrtbackend.h"

Audio::Audio(QObject* parent) : QObject(parent) {
  const QSettings settings;
  const QString mode = settings.value("audio/replayGain", replayGain_).toString();
  if (mode == "track" || mode == "album" || mode == "off") replayGain_ = mode;
  preamp_ = qBound(-15.0, settings.value("audio/preamp", 0.0).toDouble(), 15.0);
  device_ = settings.value("audio/device", device_).toString();
  // Track ids only mean something to the server they came from.
  if (settings.value("plays/server").toString() == Session::instance()->serverUrl())
    plays_ = settings.value("plays/pending").toStringList();
  connect(Session::instance(), &Session::changed, this, [this] {
    if (Session::instance()->state() != Session::Ready) return;
    if (QSettings().value("plays/server").toString() != Session::instance()->serverUrl()) {
      plays_.clear();
      savePlays();
    }
    sendPlays();
  });

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
  backend_->setReplayGain(replayGain_, preamp_);
  applyOutputDevice();
  connect(backend_, &AudioBackend::outputDevicesChanged, this, [this] {
    applyOutputDevice();
    emit outputDevicesChanged();
  });
  emit outputDevicesChanged();

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
  connect(backend_, &AudioBackend::failed, this, &Audio::onBackendFailed);
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
      emit statusChanged();
      if (backendLost_) {
        backendLost_ = false;
        emit recovered();
      }
      return;
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

QVariantList Audio::outputDevices() const { return backend_->outputDevices(); }

void Audio::setReplayGain(const QString& mode) {
  if (mode == replayGain_ || (mode != "track" && mode != "album" && mode != "off")) return;
  replayGain_ = mode;
  QSettings().setValue("audio/replayGain", mode);
  backend_->setReplayGain(replayGain_, preamp_);
  emit settingsChanged();
}

void Audio::setPreamp(double db) {
  db = qBound(-15.0, db, 15.0);
  if (qFuzzyCompare(db + 100, preamp_ + 100)) return;
  preamp_ = db;
  QSettings().setValue("audio/preamp", db);
  backend_->setReplayGain(replayGain_, preamp_);
  emit settingsChanged();
}

void Audio::setOutputDevice(const QString& id) {
  if (id == device_ || id.isEmpty()) return;
  device_ = id;
  QSettings().setValue("audio/device", id);
  applyOutputDevice();
  emit settingsChanged();
}

// The chosen device when it is there, the system default while it is not: asking
// the backend for a device that is gone would leave playback silent.
void Audio::applyOutputDevice() {
  const QVariantList devices = backend_->outputDevices();
  bool present = device_ == "auto";
  for (const QVariant& device : devices) present = present || device.toMap().value("id") == device_;
  if (present)
    backend_->setOutputDevice(device_);
  else if (!devices.isEmpty())
    backend_->setOutputDevice(QStringLiteral("auto"));
}

QVariantMap Audio::withCoverUrl(const QVariantMap& meta) const {
  QVariantMap out = meta;
  // mpv takes the gain from the file's tags itself (track or album, with its own
  // clipping guard) and ignores this. The Windows player, the fallback, cannot read
  // tags: it is given the track's gain as a number.
  out["gain"] = replayGain_ == "off" ? 0.0 : meta.value("gain").toDouble() + preamp_;
  const QString cover = meta.value("coverArt").toString();
  const auto api = Session::instance()->api();
  if (api && !cover.isEmpty())
    out["coverUrl"] = QString::fromStdString(api->cover_art_url(cover.toStdString(), 320));
  return out;
}

// Whether a track that stopped is at fault, or the way to it: only the first is
// a reason to go on to the next track.
void Audio::onBackendFailed(const QString& reason) {
  const QString id = trackId_;
  trackId_.clear();
  nextId_.clear();
  if (keys_) keys_->setState(MediaKeys::Stopped);
  if (id.isEmpty()) return;

  if (!backend_->ok()) {  // the backend went away; statusChanged replaces it
    backendLost_ = true;
    emit interrupted(id);
    return;
  }
  const auto api = Session::instance()->api();
  if (!api) {
    emit interrupted(id);
    return;  // Player resumes when the session is ready again
  }
  const int wait = ++waiting_;
  Session::async([this, api, id, reason, wait] {
    bool offline = false;
    try {
      api->ping();
    } catch (const eos::client::Error& e) {
      offline = e.offline();
    } catch (const std::exception&) {
    }
    Session::onMain([this, id, reason, offline, wait] {
      if (wait != waiting_) return;  // something else was started meanwhile
      if (!offline) {
        emit failed(id, reason);
        return;
      }
      emit interrupted(id);
      waitForServer(1000);
    });
  });
}

// Asks the server again after 1, 2, 4 ... at most 30 seconds, until it answers.
void Audio::waitForServer(int delayMs) {
  const int wait = waiting_;
  QTimer::singleShot(delayMs, this, [this, delayMs, wait] {
    const auto api = Session::instance()->api();
    if (wait != waiting_ || !api) return;
    Session::async([this, api, delayMs, wait] {
      bool reached = true;
      try {
        api->ping();
      } catch (const eos::client::Error& e) {
        reached = !e.offline();
      } catch (const std::exception&) {
      }
      Session::onMain([this, reached, delayMs, wait] {
        if (wait != waiting_) return;
        if (!reached) {
          waitForServer(qMin(delayMs * 2, 30000));
          return;
        }
        sendPlays();
        emit recovered();
      });
    });
  });
}

// The playing device counts the play (docs/sync.md); the server does not. A play
// made while the server cannot be reached is kept and sent later with its time.
void Audio::countPlay(const QString& trackId) {
  // A screenshot run is a test: it must not add to the play counts.
  if (trackId.isEmpty() || qEnvironmentVariableIsSet("KLEULIR_SCREENSHOT")) return;
  plays_.append(QString::number(QDateTime::currentMSecsSinceEpoch()) + QLatin1Char(' ') + trackId);
  while (plays_.size() > 5000) plays_.removeFirst();
  savePlays();
  sendPlays();
}

void Audio::savePlays() const {
  QSettings settings;
  settings.setValue("plays/server", Session::instance()->serverUrl());
  settings.setValue("plays/pending", plays_);
}

void Audio::sendPlays() {
  const auto api = Session::instance()->api();
  if (sendingPlays_ || plays_.isEmpty() || !api) return;
  sendingPlays_ = true;
  const QStringList plays = plays_;
  Session::async([this, api, plays] {
    int sent = 0;
    for (const QString& play : plays) {
      const qsizetype space = play.indexOf(QLatin1Char(' '));
      try {
        api->scrobble(play.mid(space + 1).toStdString(), play.left(space).toLongLong());
      } catch (const eos::client::Error& e) {
        if (e.offline()) break;  // keep it, and what follows, for later
        // Refused (the track is gone, say): asking again would not help.
      } catch (const std::exception&) {
        break;
      }
      ++sent;
    }
    Session::onMain([this, api, sent] {
      sendingPlays_ = false;
      if (Session::instance()->api() != api) return;
      plays_ = plays_.mid(sent);
      savePlays();
      // Plays counted while these were on their way.
      if (sent > 0) sendPlays();
    });
  });
}

void Audio::showOnMediaKeys() {
  if (!keys_) return;
  keys_->setTrack(meta_);
  keys_->setState(paused_ ? MediaKeys::Paused : MediaKeys::Playing);
}

bool Audio::play(const QString& trackId, double startSeconds, bool paused, const QVariantMap& meta) {
  const auto api = Session::instance()->api();
  if (!backend_->ok() || !api || trackId.isEmpty()) return false;

  ++waiting_;  // a wait for the server, if one is on, is no longer what decides
  trackId_ = trackId;
  nextId_.clear();
  meta_ = withCoverUrl(meta);
  paused_ = paused;
  backend_->play(QString::fromStdString(api->stream_url(trackId.toStdString())), startSeconds, paused, meta_);
  showOnMediaKeys();
  return true;
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
  ++waiting_;
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
