// Library: what the browsing screens show. Loads from the server on worker threads
// and hands QML plain lists and maps.
#pragma once

#include <QHash>
#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

class QQmlEngine;
class QJSEngine;

class Library : public QObject {
  Q_OBJECT
  QML_ELEMENT
  QML_SINGLETON
  // Each album: id, title, artist, year, kind ("physical" | "virtual"), coverArt, songCount.
  Q_PROPERTY(QVariantList albums READ albums NOTIFY albumsChanged)
  Q_PROPERTY(bool loading READ loading NOTIFY statusChanged)
  Q_PROPERTY(QString error READ error NOTIFY statusChanged)

 public:
  static Library* instance();
  static Library* create(QQmlEngine*, QJSEngine*);

  QVariantList albums() const { return albums_; }
  bool loading() const { return loading_; }
  QString error() const { return error_; }

  Q_INVOKABLE void refresh();
  // Answers with albumLoaded: the album's fields plus `tracks`, each with id, title,
  // artist, duration, coverArt, work (the title it belongs to, or "") and estimated.
  Q_INVOKABLE void loadAlbum(const QString& id);

 signals:
  void albumsChanged();   // the list itself changed
  void statusChanged();   // loading or error changed
  void albumLoaded(const QString& id, const QVariantMap& album);
  void albumFailed(const QString& id, const QString& message);

 private:
  explicit Library(QObject* parent = nullptr);

  void loadCachedAlbums();

  QVariantList albums_;
  QHash<QString, QVariantMap> details_;  // albums already fetched this run
  bool loading_ = false;
  bool fresh_ = false;  // the list came from the server this run, not from the cache
  QString error_;
  int generation_ = 0;  // drops answers that arrive after a logout or a newer refresh
};
