// AudioBackend: what Audio needs from something that can play a stream. There are
// two: mpv (preferred: exact seeking, real gapless, ReplayGain from the tags) and the
// Windows media player (used when no mpv is found).
//
// A backend plays "the current track" and can be told which one follows, so the
// change happens inside it without a gap. It knows nothing of ids or the server;
// Audio gives it ready URLs.
#pragma once

#include <QObject>
#include <QString>
#include <QVariantMap>

class AudioBackend : public QObject {
  Q_OBJECT

 public:
  using QObject::QObject;

  virtual QString name() const = 0;
  // false when it could not be set up; problem() says why.
  virtual bool ok() const = 0;
  virtual QString problem() const = 0;
  // true when the backend itself answers the media keys and feeds the system's
  // "now playing" display; false when Audio has to (see MediaKeys).
  virtual bool ownsMediaKeys() const = 0;

  virtual double position() const = 0;  // seconds

  // `meta`: title, artist, album, coverUrl, gain (ReplayGain in dB, 0 when none).
  virtual void play(const QString& url, double startSeconds, bool paused, const QVariantMap& meta) = 0;
  // An empty url means the current track is the last.
  virtual void setNext(const QString& url, const QVariantMap& meta) = 0;
  virtual void setPaused(bool paused) = 0;
  virtual void seek(double seconds) = 0;
  virtual void stop() = 0;
  virtual void setVolume(int percent) = 0;  // 0..100
  virtual void setMuted(bool muted) = 0;

 signals:
  void positionChanged();
  // The current track ended and the one given to setNext() is now playing.
  void advanced();
  // The current track ended and nothing followed it.
  void finished();
  void failed(const QString& reason);
  void statusChanged();  // ok() or problem() changed
  // Only from backends that own the media keys.
  void pausedChanged(bool paused);
  void nextRequested();
  void previousRequested();
};
