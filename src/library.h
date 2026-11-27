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

#include <exception>
#include <functional>
#include <memory>

namespace eos::client {
class Api;
}

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
  // Album artists, in index order: id, name, albumCount, index ("A", "カ", "#"...).
  Q_PROPERTY(QVariantList artists READ artists NOTIFY artistsChanged)
  // The user's playlists: id, name, songCount, duration, owner.
  Q_PROPERTY(QVariantList playlists READ playlists NOTIFY playlistsChanged)

 public:
  static Library* instance();
  static Library* create(QQmlEngine*, QJSEngine*);

  QVariantList albums() const { return albums_; }
  bool loading() const { return loading_; }
  QString error() const { return error_; }

  Q_INVOKABLE void refresh();
  // Albums, artists and playlists. Also runs by itself every 15 minutes.
  Q_INVOKABLE void refreshAll();
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

  QVariantList artists() const { return artists_; }
  QVariantList playlists() const { return playlists_; }

  // Answers with starredLoaded: albums and songs.
  Q_INVOKABLE void loadStarred();
  // Answers with artistLoaded: id, name, albums.
  Q_INVOKABLE void loadArtist(const QString& id);
  Q_INVOKABLE void refreshArtists();

  Q_INVOKABLE void refreshPlaylists();
  // Answers with playlistLoaded: the playlist's fields plus tracks.
  Q_INVOKABLE void loadPlaylist(const QString& id);
  // Answers with playlistCreated once the server has it.
  Q_INVOKABLE void createPlaylist(const QString& name, const QStringList& songIds);
  Q_INVOKABLE void addToPlaylist(const QString& id, const QStringList& songIds);
  // `indexes` are positions in the playlist as last loaded.
  Q_INVOKABLE void removeFromPlaylist(const QString& id, const QVariantList& indexes);
  Q_INVOKABLE void renamePlaylist(const QString& id, const QString& name);
  Q_INVOKABLE void deletePlaylist(const QString& id);

  // ---- eos only (Session.eosFeatures) ----
  // Works are what the server calls titles: the game, film or show music belongs
  // to. Answers with worksLoaded: id, name, kind, year, songCount.
  Q_INVOKABLE void loadWorks();
  // Answers with workLoaded: id, name, kind, year, albums, songs.
  Q_INVOKABLE void loadWork(const QString& id);
  // Answers with compositionsLoaded: id, name, composers.
  Q_INVOKABLE void loadCompositions();
  // Answers with compositionLoaded: id, name, composers and songs, each song's
  // `work` naming its arrangement (the list's section).
  Q_INVOKABLE void loadComposition(const QString& id);
  // The other recordings of what `songId` is. Answers with versionsLoaded:
  // compositionId, compositionName, composers, songs (sectioned like above) and
  // compositions (related ones: id, name, relation).
  Q_INVOKABLE void loadVersions(const QString& songId);
  // Answers with foldersLoaded: every folder, flat: id, name, parentId,
  // albumCount, childCount.
  Q_INVOKABLE void loadFolders();
  // Answers with folderLoaded: id, name, albums.
  Q_INVOKABLE void loadFolder(const QString& id);
  // The graph around `seed` ("song:<id>", "composition:<id>", ...; a node's id can be
  // passed back). mode "related": compositions, relations and works, two steps;
  // "similar": the songs that sound most alike (Session.hasFeature("similarity")).
  // Answers with graphLoaded: nodes (id, type, label, subtitle, distance, degree,
  // expanded, track for songs, itemId), edges (from, to, type, label, score, estimated),
  // truncated, and error when the server refused.
  Q_INVOKABLE void loadGraph(const QString& seed, const QString& mode);

 signals:
  void albumsChanged();   // the list itself changed
  void statusChanged();   // loading or error changed
  // A call to the server failed; `message` is for the user.
  void problem(const QString& message);
  void albumLoaded(const QString& id, const QVariantMap& album);
  void albumFailed(const QString& id, const QString& message);
  void starsChanged();
  void searchLoaded(const QString& query, const QVariantMap& result);
  void artistsChanged();
  void playlistsChanged();
  void starredLoaded(const QVariantMap& result);
  void artistLoaded(const QString& id, const QVariantMap& artist);
  void playlistLoaded(const QString& id, const QVariantMap& playlist);
  // A playlist's contents or name changed on the server.
  void playlistChanged(const QString& id);
  void playlistCreated(const QString& id, const QString& name);
  void playlistDeleted(const QString& id);
  void worksLoaded(const QVariantList& works);
  void workLoaded(const QString& id, const QVariantMap& work);
  void compositionsLoaded(const QVariantList& compositions);
  void compositionLoaded(const QString& id, const QVariantMap& composition);
  void versionsLoaded(const QString& songId, const QVariantMap& versions);
  void foldersLoaded(const QVariantList& folders);
  void folderLoaded(const QString& id, const QVariantMap& folder);
  void graphLoaded(const QString& seed, const QString& mode, const QVariantMap& graph);

 private:
  explicit Library(QObject* parent = nullptr);

  void loadCachedAlbums();
  void reset();
  void deliver(const std::shared_ptr<eos::client::Api>& api, std::function<void()> done);
  void report(const std::exception& e);
  // Runs `call` once the session is ready (now, if it already is). For loads asked
  // for while the app is still reconnecting at start-up.
  void whenReady(std::function<void()> call);
  // Takes the `starred` flags of freshly loaded albums or songs into starred_.
  void absorbStars(const QVariantList& items);

  QVariantList albums_;
  QVariantList artists_;
  QVariantList playlists_;
  QHash<QString, QVariantMap> details_;  // albums already fetched this run
  QSet<QString> starred_;
  int starRevision_ = 0;
  QList<std::function<void()>> deferred_;
  QStringList waiting_;                  // albums asked for before the session was ready
  bool loading_ = false;
  bool fresh_ = false;  // the list came from the server this run, not from the cache
  QString error_;
  QString server_;      // the server what is held here came from
  int generation_ = 0;  // drops answers that arrive after a logout or a newer refresh
};
