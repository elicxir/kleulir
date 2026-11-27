#include "coverprovider.h"

#include <algorithm>

#include "session.h"

CoverProvider::CoverProvider()
    : QQuickImageProvider(QQuickImageProvider::Image, QQmlImageProviderBase::ForceAsynchronousImageLoading) {}

QImage CoverProvider::requestImage(const QString& id, QSize* size, const QSize& requestedSize) {
  QImage image;
  // Copy the pointer: the session may log out while this request is in flight.
  const auto api = Session::instance()->api();
  if (api && !id.isEmpty()) {
    try {
      // Round up to a few fixed sizes so the server's resize cache is reused.
      const int wanted = std::max(requestedSize.width(), requestedSize.height());
      const int px = wanted <= 0 ? 0 : wanted <= 96 ? 96 : wanted <= 320 ? 320 : 640;
      const auto bytes = api->cover_art(id.toStdString(), px);
      image.loadFromData(reinterpret_cast<const uchar*>(bytes.data.data()), static_cast<int>(bytes.data.size()));
    } catch (const std::exception&) {
      // No art, or the server is unreachable: the caller keeps its placeholder.
    }
  }
  if (size) *size = image.size();
  return image;
}
