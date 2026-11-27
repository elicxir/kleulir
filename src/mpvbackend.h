// MpvBackend: playback through an mpv child process, driven over its JSON IPC (a
// named pipe on Windows) — the same arrangement as the other eos clients.
//
// mpv's playlist holds at most two entries, the current track and the next one;
// mpv moves between them itself (gapless), and the played entry is then dropped.
// Stream URLs carry the API key, so they go over the pipe, never on the command line.
#pragma once

#include <QByteArray>
#include <QJsonArray>
#include <QList>

#include "audiobackend.h"

class QLocalSocket;
class QProcess;
class QTimer;

class MpvBackend : public AudioBackend {
  Q_OBJECT

 public:
  // Where mpv.exe is: KLEULIR_MPV, next to kleulir (bundled), PATH, or the usual
  // install folders. Empty when there is none.
  static QString findExecutable();

  explicit MpvBackend(const QString& executable, QObject* parent = nullptr);
  ~MpvBackend() override;

  QString name() const override { return QStringLiteral("mpv"); }
  bool ok() const override { return problem_.isEmpty(); }
  QString problem() const override { return problem_; }
  bool ownsMediaKeys() const override { return false; }
  double position() const override { return position_; }

  void play(const QString& url, double startSeconds, bool paused, const QVariantMap& meta) override;
  void setNext(const QString& url, const QVariantMap& meta) override;
  void setPaused(bool paused) override;
  void seek(double seconds) override;
  void stop() override;
  void setVolume(int percent) override;
  void setMuted(bool muted) override;

 private:
  void tryConnect();
  void send(const QJsonArray& command, int requestId = 0);
  void onLine(const QByteArray& line);
  void fail(const QString& text);

  QProcess* process_ = nullptr;
  QLocalSocket* socket_ = nullptr;
  QTimer* connectTimer_ = nullptr;
  QTimer* pollTimer_ = nullptr;
  QString pipe_;
  QString problem_;
  QByteArray buffer_;
  QList<QByteArray> waiting_;  // commands sent before the pipe was open
  bool connected_ = false;
  bool loaded_ = false;   // a track is loaded
  bool hasNext_ = false;  // a second playlist entry is queued
  double position_ = 0;
  int connectTries_ = 0;
  int volume_ = 80;
  bool muted_ = false;
};
