// Library: what the browsing screens show. Loads from the server on worker threads
// and hands QML plain lists and maps.
#pragma once

#include <QHash>
#include <QSet>
#include <QObject>
#include <QString>
#include <QStringList>
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
  // Bumped whenever a star changes; bindings that call isStarred() read it to re-run.
  Q_PROPERTY(int starRevision READ starRevision NOTIFY starsChanged)

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

  int starRevision() const { return starRevision_; }
  Q_INVOKABLE bool isStarred(const QString& id) const { return starred_.contains(id); }
  // Songs or albums. Shown at once; put back if the server refuses.
  Q_INVOKABLE void setStarred(const QStringList& ids, bool starred);

  // Answers with searchLoaded: albums and songs (shaped like the lists above; a
  // song also carries album and albumId).
  Q_INVOKABLE void search(const QString& query);

 signals:
  void albumsChanged();   // the list itself changed
  void statusChanged();   // loading or error changed
  void albumLoaded(const QString& id, const QVariantMap& album);
  void albumFailed(const QString& id, const QString& message);
  void starsChanged();
  void searchLoaded(const QString& query, const QVariantMap& result);

 private:
  explicit Library(QObject* parent = nullptr);

  void loadCachedAlbums();
  // Takes the `starred` flags of freshly loaded albums or songs into starred_.
  void absorbStars(const QVariantList& items);

  QVariantList albums_;
  QHash<QString, QVariantMap> details_;  // albums already fetched this run
  QSet<QString> starred_;
  int starRevision_ = 0;
  QStringList waiting_;                  // albums asked for before the session was ready
  bool loading_ = false;
  bool fresh_ = false;  // the list came from the server this run, not from the cache
  QString error_;
  int generation_ = 0;  // drops answers that arrive after a logout or a newer refresh
};
