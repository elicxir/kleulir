#include "coverprovider.h"

#include <QRegularExpression>

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

}  // namespace

CoverProvider::CoverProvider()
    : QQuickImageProvider(QQuickImageProvider::Image, QQmlImageProviderBase::ForceAsynchronousImageLoading) {
  // Keep the cover cache bounded.
  const QString folder = cache::folder(Session::instance()->serverUrl());
  if (!folder.isEmpty()) Session::async([folder] { cache::prune(folder + "/covers", 300ll * 1024 * 1024); });
}

QImage CoverProvider::requestImage(const QString& id, QSize* size, const QSize& requestedSize) {
  QImage image;
  if (!id.isEmpty()) {
    // A few fixed sizes, so the same file serves every place a cover is shown at
    // about that size, and the server's own resize cache is reused.
    const int wanted = std::max(requestedSize.width(), requestedSize.height());
    const int px = wanted <= 0 ? 640 : wanted <= 96 ? 96 : wanted <= 320 ? 320 : 640;

    const QString path = cachePath(Session::instance()->serverUrl(), id, px);
    if (!path.isEmpty()) image.loadFromData(cache::read(path));

    if (image.isNull()) {
      // Copy the pointer: the session may log out while this request is in flight.
      if (const auto api = Session::instance()->api()) {
        try {
          const auto bytes = api->cover_art(id.toStdString(), px);
          const QByteArray data(bytes.data.data(), static_cast<qsizetype>(bytes.data.size()));
          if (image.loadFromData(data) && !path.isEmpty()) cache::write(path, data);
        } catch (const std::exception&) {
          // No art, or the server is unreachable: the caller keeps its placeholder.
        }
      }
    }
  }
  if (size) *size = image.size();
  return image;
}
