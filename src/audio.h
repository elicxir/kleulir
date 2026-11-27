// Audio: plays one track at a time with Windows' own player
// (Windows.Media.Playback.MediaPlayer). No external program is needed, and the
// media keys and the system "now playing" display come with it.
//
// Stream URLs carry the API key, so they are built here and handed straight to the
// player; they never reach QML or a log.
#pragma once

#include <QObject>
#include <QString>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

#include <atomic>
#include <memory>

class QJSEngine;
class QQmlEngine;
class QTimer;

class Audio : public QObject {
  Q_OBJECT
  QML_ELEMENT
  QML_SINGLETON
  Q_PROPERTY(bool available READ available NOTIFY availableChanged)
  Q_PROPERTY(QString problem READ problem NOTIFY availableChanged)
  Q_PROPERTY(double position READ position NOTIFY positionChanged)  // seconds

 public:
  static Audio* instance();
  static Audio* create(QQmlEngine*, QJSEngine*);

  bool available() const { return available_; }
  QString problem() const { return problem_; }
  double position() const { return position_; }

  // Starts `trackId` from `startSeconds`. `paused` loads it without sounding.
  // `meta`: title, artist, album, coverArt (for the system display) and gain (the
  // track's ReplayGain in dB, 0 when it has none).
  Q_INVOKABLE void play(const QString& trackId, double startSeconds, bool paused, const QVariantMap& meta);
  Q_INVOKABLE void setPaused(bool paused);
  Q_INVOKABLE void seek(double seconds);
  Q_INVOKABLE void stop();
  Q_INVOKABLE void setVolume(int percent);  // 0..100
  Q_INVOKABLE void setMuted(bool muted);

 signals:
  void availableChanged();
  void positionChanged();
  // The track played to its end (not stopped, not replaced).
  void finished(const QString& trackId);
  void failed(const QString& trackId, const QString& reason);
  // Paused or resumed from outside the app (media keys, the system flyout).
  void pausedChanged(bool paused);
  void nextRequested();
  void previousRequested();

 private:
  explicit Audio(QObject* parent = nullptr);
  ~Audio() override;
  void applyVolume();
  void poll();

  struct Impl;
  std::unique_ptr<Impl> impl_;
  QTimer* pollTimer_ = nullptr;
  bool available_ = false;
  QString problem_;
  QString trackId_;              // what is loaded now
  std::atomic<int> serial_{0};   // bumped per play(); drops events of a replaced track
  double position_ = 0;
  double pendingStart_ = 0;
  int volume_ = 80;
  bool muted_ = false;
  double gainDb_ = 0;
  int lastState_ = -1;
};
