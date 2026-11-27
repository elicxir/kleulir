#include "coverprovider.h"

#include <QImage>
#include <QQuickTextureFactory>
#include <QRegularExpression>
#include <QRunnable>
#include <QThreadPool>

#include <algorithm>

#include "cache.h"
#include "session.h"

namespace {

// Cover ids carry the art's update time (al-<id>_<time>), so a cached file never
// goes stale: changed art arrives under a new id.
QString cachePath(const QString& serverUrl, const QString& id, int px) {
  const QString folder = cache::folder(serverUrl);
  if (folder.isEmpty()) return {};
  QString safe = id;
  safe.replace(QRegularExpression("[^A-Za-z0-9_-]"), "_");
  return QStringLiteral("%1/covers/%2_%3").arg(folder, safe).arg(px);
}

// Never deleted, like Session's workers: a request still waiting for the server
// must not hold the exit up.
QThreadPool* pool() {
  static QThreadPool* const p = [] {
    auto* created = new QThreadPool;
    created->setMaxThreadCount(6);
    return created;
  }();
  return p;
}

QImage load(const QString& id, const QSize& requestedSize) {
  QImage image;
  if (id.isEmpty()) return image;

  // A few fixed sizes, so the same file serves every place a cover is shown at
  // about that size, and the server's own resize cache is reused.
  const int wanted = std::max(requestedSize.width(), requestedSize.height());
  const int px = wanted <= 0 ? 640 : wanted <= 96 ? 96 : wanted <= 320 ? 320 : 640;

  const QString path = cachePath(Session::instance()->serverUrl(), id, px);
  if (!path.isEmpty()) image.loadFromData(cache::read(path));
  if (!image.isNull()) return image;

  // The session hands out its own copy of the pointer: it may log out while this
  // request is in flight.
  if (const auto api = Session::instance()->api()) {
    try {
      const auto bytes = api->cover_art(id.toStdString(), px);
      const QByteArray data(bytes.data.data(), static_cast<qsizetype>(bytes.data.size()));
      if (image.loadFromData(data) && !path.isEmpty()) cache::write(path, data);
    } catch (const std::exception&) {
      // No art, or the server is unreachable: the caller keeps its placeholder.
    }
  }
  return image;
}

class CoverResponse : public QQuickImageResponse, public QRunnable {
 public:
  CoverResponse(const QString& id, const QSize& requestedSize) : id_(id), requestedSize_(requestedSize) {
    // Qt deletes the response (deleteLater) once it has the image; the pool must not.
    setAutoDelete(false);
  }

  void run() override {
    image_ = load(id_, requestedSize_);
    emit finished();
  }

  QQuickTextureFactory* textureFactory() const override { return QQuickTextureFactory::textureFactoryForImage(image_); }

 private:
  QString id_;
  QSize requestedSize_;
  QImage image_;
};

}  // namespace

CoverProvider::CoverProvider() {
  // Keep the cover cache bounded.
  const QString folder = cache::folder(Session::instance()->serverUrl());
  if (!folder.isEmpty()) Session::async([folder] { cache::prune(folder + "/covers", 300ll * 1024 * 1024); });
}

QQuickImageResponse* CoverProvider::requestImageResponse(const QString& id, const QSize& requestedSize) {
  auto* response = new CoverResponse(id, requestedSize);
  pool()->start(response);
  return response;
}
