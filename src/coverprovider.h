// image://cover/<coverArtId> — cover art fetched through the Api, on Qt's image
// loading threads. The requested size is what the server scales to.
#pragma once

#include <QQuickImageProvider>

class CoverProvider : public QQuickImageProvider {
 public:
  CoverProvider();
  QImage requestImage(const QString& id, QSize* size, const QSize& requestedSize) override;
};
