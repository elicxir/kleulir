// MediaKeys: kleulir's entry in Windows' media controls (the keyboard's media keys,
// the volume flyout, the lock screen) for when the audio backend does not provide
// one itself — that is, with mpv.
#pragma once

#include <QObject>
#include <QVariantMap>

#include <memory>

class MediaKeys : public QObject {
  Q_OBJECT

 public:
  enum State { Stopped, Playing, Paused };

  explicit MediaKeys(QObject* parent = nullptr);
  ~MediaKeys() override;

  // `meta`: title, artist, album, coverUrl.
  void setTrack(const QVariantMap& meta);
  void setState(State state);

 signals:
  void playRequested();
  void pauseRequested();
  void nextRequested();
  void previousRequested();

 private:
  // The controls belong to a window, so they can only be set up once one exists.
  bool ready();

  struct Impl;
  std::unique_ptr<Impl> impl_;
  QVariantMap pendingTrack_;
  State state_ = Stopped;
};
