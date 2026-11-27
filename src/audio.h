// Audio: what QML plays through. It picks a backend (mpv when there is one, the
// Windows media player otherwise), turns track ids into stream URLs, counts plays
// and keeps Windows' media controls in step.
//
// Stream URLs carry the API key, so they are built here and handed straight to the
// backend; they never reach QML or a log.
#pragma once

#include <QObject>
#include <QString>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

class AudioBackend;
class MediaKeys;
class QJSEngine;
class QQmlEngine;

class Audio : public QObject {
  Q_OBJECT
  QML_ELEMENT
  QML_SINGLETON
  Q_PROPERTY(bool available READ available NOTIFY statusChanged)
  Q_PROPERTY(QString problem READ problem NOTIFY statusChanged)
  // "mpv" or "Windows".
  Q_PROPERTY(QString backend READ backendName NOTIFY statusChanged)
  Q_PROPERTY(double position READ position NOTIFY positionChanged)  // seconds

 public:
  static Audio* instance();
  static Audio* create(QQmlEngine*, QJSEngine*);

  bool available() const;
  QString problem() const;
  QString backendName() const;
  double position() const;

  // Starts `trackId` from `startSeconds`. `paused` loads it without sounding.
  // `meta`: title, artist, album, coverArt (for the system display) and gain (the
  // track's ReplayGain in dB, 0 when it has none).
  Q_INVOKABLE void play(const QString& trackId, double startSeconds, bool paused, const QVariantMap& meta);
  // Names the track to continue with, without a gap, when the current one ends.
  // An empty id means the current track is the last.
  Q_INVOKABLE void setNext(const QString& trackId, const QVariantMap& meta);
  Q_INVOKABLE void setPaused(bool paused);
  Q_INVOKABLE void seek(double seconds);
  Q_INVOKABLE void stop();
  Q_INVOKABLE void setVolume(int percent);  // 0..100
  Q_INVOKABLE void setMuted(bool muted);

 signals:
  void statusChanged();
  void positionChanged();
  // The current track ended and the one given to setNext() is now playing.
  void advanced(const QString& trackId);
  // The last track played to its end (nothing was queued after it).
  void finished(const QString& trackId);
  void failed(const QString& trackId, const QString& reason);
  // Paused or resumed from outside the app (media keys, the system flyout).
  void pausedChanged(bool paused);
  void nextRequested();
  void previousRequested();

 private:
  explicit Audio(QObject* parent = nullptr);
  void useBackend(AudioBackend* backend);
  QVariantMap withCoverUrl(const QVariantMap& meta) const;
  void countPlay(const QString& trackId);
  void showOnMediaKeys();

  AudioBackend* backend_ = nullptr;
  MediaKeys* keys_ = nullptr;  // only with a backend that leaves the media keys to us
  QString trackId_;            // what is playing now
  QString nextId_;             // what the backend will continue with
  QVariantMap meta_, nextMeta_;
  bool paused_ = false;
  int volume_ = 80;
  bool muted_ = false;
};
