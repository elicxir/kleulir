// image://cover/<coverArtId> — cover art fetched through the Api. The requested size
// is what the server scales to.
//
// Each request runs on a small pool of its own: a page of covers loads several at a
// time, and one that the server is slow to answer does not hold the others up.
#pragma once

#include <QQuickAsyncImageProvider>

class CoverProvider : public QQuickAsyncImageProvider {
 public:
  CoverProvider();
  QQuickImageResponse* requestImageResponse(const QString& id, const QSize& requestedSize) override;
};
