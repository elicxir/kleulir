#include "mpvbackend.h"

#include <QCoreApplication>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocalSocket>
#include <QProcess>
#include <QStandardPaths>
#include <QTimer>

#include <windows.h>

namespace {

const int kTimePosRequest = 1;

void trace(const QString& text) {
  static const bool on = qEnvironmentVariableIsSet("KLEULIR_TRACE_AUDIO");
  if (on) qInfo().noquote() << "mpv  " << text;
}

// A job that ends its processes when kleulir goes away, however that happens:
// mpv must not keep running (and holding the audio device) after a crash.
void endWithKleulir(qint64 pid) {
  static const HANDLE job = [] {
    const HANDLE handle = CreateJobObjectW(nullptr, nullptr);
    if (!handle) return handle;
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};
    limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    SetInformationJobObject(handle, JobObjectExtendedLimitInformation, &limits, sizeof(limits));
    return handle;  // Kept open for the life of kleulir; Windows closes it at exit.
  }();
  if (!job || pid <= 0) return;
  if (const HANDLE process = OpenProcess(PROCESS_SET_QUOTA | PROCESS_TERMINATE, FALSE, DWORD(pid))) {
    AssignProcessToJobObject(job, process);
    CloseHandle(process);
  }
}

}  // namespace

QString MpvBackend::findExecutable() {
  const QString fromEnv = qEnvironmentVariable("KLEULIR_MPV");
  if (!fromEnv.isEmpty() && QFileInfo::exists(fromEnv)) return fromEnv;

  // Bundled with kleulir.
  const QString appDir = QCoreApplication::applicationDirPath();
  for (const QString& candidate : {appDir + "/mpv.exe", appDir + "/mpv/mpv.exe"}) {
    if (QFileInfo::exists(candidate)) return candidate;
  }

  const QString onPath = QStandardPaths::findExecutable("mpv.exe");
  if (!onPath.isEmpty()) return onPath;

  QStringList folders;
  for (const char* var : {"ProgramFiles", "ProgramFiles(x86)", "LOCALAPPDATA"}) {
    const QString base = qEnvironmentVariable(var);
    if (base.isEmpty()) continue;
    folders << base + "/MPV Player" << base + "/mpv" << base + "/Programs/mpv";
  }
  return QStandardPaths::findExecutable("mpv.exe", folders);
}

MpvBackend::MpvBackend(const QString& executable, QObject* parent) : AudioBackend(parent) {
  pipe_ = QStringLiteral("\\\\.\\pipe\\kleulir-mpv-%1").arg(QCoreApplication::applicationPid());

  process_ = new QProcess(this);
  process_->setProgram(executable);
  process_->setArguments({
      "--idle=yes",
      "--no-video",
      "--no-terminal",
      "--no-config",
      "--load-scripts=no",
      "--audio-display=no",
      "--input-ipc-server=" + pipe_,
      "--msg-level=all=warn",
      "--audio-client-name=kleulir",
      "--demuxer-max-bytes=64MiB",
      // Gapless: open the next playlist entry ahead of time and keep the audio
      // device running across the change.
      "--gapless-audio=weak",
      "--prefetch-playlist=yes",
      // Untranscoded files carry their ReplayGain tags; mpv applies them and
      // lowers the gain where the peak would clip.
      "--replaygain=track",
      QStringLiteral("--volume=%1").arg(volume_),
  });
  process_->setStandardOutputFile(QProcess::nullDevice());
  process_->setStandardErrorFile(QProcess::nullDevice());
  connect(process_, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
    if (error == QProcess::FailedToStart) fail(QStringLiteral("mpv could not be started: ") + process_->errorString());
  });
  connect(process_, &QProcess::finished, this, [this] {
    // Not expected while kleulir runs: mpv idles between tracks.
    fail(QStringLiteral("mpv exited."));
  });
  process_->start();
  endWithKleulir(process_->processId());

  socket_ = new QLocalSocket(this);
  connect(socket_, &QLocalSocket::connected, this, [this] {
    connectTimer_->stop();
    connected_ = true;
    trace(QStringLiteral("connected"));
    // kleulir feeds the system's media display itself; mpv must not add its own.
    // (Older mpv has no such option; the error reply is ignored.)
    send({"set_property", "media-controls", false});
    send({"observe_property", 1, "playlist-pos"});
    send({"observe_property", 2, "audio-device-list"});
    for (const QByteArray& line : std::as_const(waiting_)) socket_->write(line);
    waiting_.clear();
  });
  connect(socket_, &QLocalSocket::readyRead, this, [this] {
    buffer_ += socket_->readAll();
    for (qsizetype end; (end = buffer_.indexOf('\n')) >= 0;) {
      const QByteArray line = buffer_.left(end);
      buffer_.remove(0, end + 1);
      if (!line.trimmed().isEmpty()) onLine(line);
    }
  });

  // mpv creates the pipe a moment after it starts.
  connectTimer_ = new QTimer(this);
  connectTimer_->setInterval(100);
  connect(connectTimer_, &QTimer::timeout, this, &MpvBackend::tryConnect);
  connectTimer_->start();

  // The position is asked for rather than observed: observing `time-pos` floods
  // the pipe with an event per audio frame.
  pollTimer_ = new QTimer(this);
  pollTimer_->setInterval(200);
  connect(pollTimer_, &QTimer::timeout, this, [this] {
    if (loaded_ && connected_) send({"get_property", "time-pos"}, kTimePosRequest);
  });
  pollTimer_->start();
}

MpvBackend::~MpvBackend() {
  if (process_->state() == QProcess::NotRunning) return;
  disconnect(process_, nullptr, this, nullptr);
  send({"quit"});
  if (socket_) socket_->flush();
  if (!process_->waitForFinished(1500)) process_->kill();
}

void MpvBackend::fail(const QString& text) {
  if (problem_ == text) return;
  problem_ = text;
  connected_ = false;
  if (connectTimer_) connectTimer_->stop();
  const bool wasPlaying = loaded_;
  loaded_ = false;
  hasNext_ = false;
  emit statusChanged();
  if (wasPlaying) emit failed(text);
}

void MpvBackend::tryConnect() {
  if (socket_->state() != QLocalSocket::UnconnectedState) return;
  if (++connectTries_ > 100) {
    fail(QStringLiteral("mpv did not open its control pipe."));
    return;
  }
  socket_->connectToServer(pipe_);
}

void MpvBackend::send(const QJsonArray& command, int requestId) {
  QJsonObject message{{"command", command}};
  if (requestId != 0) message["request_id"] = requestId;
  const QByteArray line = QJsonDocument(message).toJson(QJsonDocument::Compact) + '\n';
  if (connected_)
    socket_->write(line);
  else if (problem_.isEmpty())
    waiting_.append(line);  // sent once the pipe is open
}

void MpvBackend::onLine(const QByteArray& line) {
  const QJsonObject msg = QJsonDocument::fromJson(line).object();

  if (msg.value("request_id").toInt() == kTimePosRequest) {
    if (loaded_ && msg.value("data").isDouble()) {
      const double now = msg.value("data").toDouble();
      if (qAbs(now - position_) > 0.05) {
        position_ = now;
        emit positionChanged();
      }
    }
    return;
  }

  const QString event = msg.value("event").toString();
  if (event.isEmpty()) return;

  if (event == "property-change" && msg.value("name").toString() == "audio-device-list") {
    // mpv also lists "auto" and other audio systems; only the Windows devices
    // are offered.
    QVariantList devices;
    for (const QJsonValue& value : msg.value("data").toArray()) {
      const QString id = value["name"].toString();
      if (!id.startsWith("wasapi/")) continue;
      const QString name = value["description"].toString();
      devices.append(QVariantMap{{"id", id}, {"name", name.isEmpty() ? id : name}});
    }
    if (devices != devices_) {
      devices_ = devices;
      emit outputDevicesChanged();
    }
  } else if (event == "property-change" && msg.value("name").toString() == "playlist-pos") {
    // mpv went on to the second entry by itself: that is the gapless change.
    // Drop the played entry, so the current track is entry 0 again.
    if (msg.value("data").toInt(-1) == 1 && hasNext_) {
      trace(QStringLiteral("advanced to the next entry"));
      hasNext_ = false;
      position_ = 0;
      send({"playlist-remove", 0});
      emit positionChanged();
      emit advanced();
    }
  } else if (event == "end-file") {
    // eof: played through. error: could not be played. stop / redirect / quit: ours.
    const QString reason = msg.value("reason").toString();
    trace(QStringLiteral("end-file %1 (next queued: %2)").arg(reason).arg(hasNext_));
    if (reason == "eof" && !hasNext_ && loaded_) {
      loaded_ = false;
      emit finished();
    } else if (reason == "error" && loaded_) {
      const QString detail = msg.value("file_error").toString();
      loaded_ = false;
      hasNext_ = false;
      send({"stop"});
      emit failed(detail.isEmpty() ? QStringLiteral("The track could not be played.") : detail);
    }
  }
}

void MpvBackend::play(const QString& url, double startSeconds, bool paused, const QVariantMap&) {
  if (!ok()) return;
  trace(QStringLiteral("play start=%1 paused=%2").arg(startSeconds).arg(paused));
  loaded_ = true;
  hasNext_ = false;
  position_ = startSeconds;
  emit positionChanged();

  send({"set_property", "pause", paused});
  if (startSeconds > 0.5) {
    // A per-file option: it must not carry over to the track queued after it.
    send({"loadfile", url, "replace", -1, QJsonObject{{"start", QString::number(startSeconds, 'f', 2)}}});
  } else {
    send({"loadfile", url, "replace"});
  }
}

void MpvBackend::setNext(const QString& url, const QVariantMap&) {
  if (!ok() || !loaded_) return;
  if (hasNext_) {
    send({"playlist-remove", 1});
    hasNext_ = false;
  }
  if (!url.isEmpty()) {
    trace(QStringLiteral("next queued"));
    send({"loadfile", url, "append"});
    hasNext_ = true;
  }
}

void MpvBackend::setPaused(bool paused) {
  if (loaded_) send({"set_property", "pause", paused});
}

void MpvBackend::seek(double seconds) {
  if (!loaded_) return;
  trace(QStringLiteral("seek %1").arg(seconds));
  position_ = seconds;
  emit positionChanged();
  send({"seek", seconds, "absolute"});
}

void MpvBackend::stop() {
  loaded_ = false;
  hasNext_ = false;
  send({"stop"});
}

void MpvBackend::setVolume(int percent) {
  volume_ = qBound(0, percent, 100);
  send({"set_property", "volume", volume_});
}

void MpvBackend::setMuted(bool muted) {
  muted_ = muted;
  send({"set_property", "mute", muted});
}

void MpvBackend::setReplayGain(const QString& mode, double preampDb) {
  // mpv reads the gain from the file's tags and limits it where the peak would clip.
  send({"set_property", "replaygain", mode == "off" ? QStringLiteral("no") : mode});
  send({"set_property", "replaygain-preamp", preampDb});
}

void MpvBackend::setOutputDevice(const QString& id) {
  trace(QStringLiteral("output device: %1").arg(id == "auto" ? id : QStringLiteral("chosen")));
  send({"set_property", "audio-device", id});
}
