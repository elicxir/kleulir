// WinRtBackend: playback with Windows' own player (Windows.Media.Playback). Used when
// no mpv is found: nothing extra to install, and the media keys come with it.
//
// Known limits, which are why mpv is preferred: seeking in a FLAC without a SEEKTABLE
// lands seconds off (the player seeks by byte ratio), the position then runs past the
// track's end, and ReplayGain can only lower the volume.
#pragma once

#include <atomic>
#include <memory>

#include "audiobackend.h"

class QTimer;

class WinRtBackend : public AudioBackend {
  Q_OBJECT

 public:
  explicit WinRtBackend(QObject* parent = nullptr);
  ~WinRtBackend() override;

  QString name() const override { return QStringLiteral("Windows"); }
  bool ok() const override { return ok_; }
  QString problem() const override { return problem_; }
  bool ownsMediaKeys() const override { return true; }
  double position() const override { return position_; }

  void play(const QString& url, double startSeconds, bool paused, const QVariantMap& meta) override;
  void setNext(const QString& url, const QVariantMap& meta) override;
  void setPaused(bool paused) override;
  void seek(double seconds) override;
  void stop() override;
  void setVolume(int percent) override;
  void setMuted(bool muted) override;

 private:
  void applyVolume();
  void poll();

  struct Impl;
  std::unique_ptr<Impl> impl_;
  QTimer* pollTimer_ = nullptr;
  bool ok_ = false;
  QString problem_;
  bool loaded_ = false;
  bool hasNext_ = false;
  std::atomic<int> serial_{0};  // bumped per play(); drops events of a replaced list
  double position_ = 0;
  std::atomic<double> pendingStart_{0};  // read by MediaOpened, on the player's thread
  int volume_ = 80;
  bool muted_ = false;
  double gainDb_ = 0;
  double nextGainDb_ = 0;
  int lastState_ = -1;
};
