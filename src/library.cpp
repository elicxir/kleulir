#include "library.h"

#include <QCoreApplication>
#include <QHash>
#include <QJSEngine>
#include <QJsonArray>
#include <QJsonDocument>
#include <QTimer>

#include "cache.h"

#include "session.h"

using namespace eos::client;

namespace {

QString qs(const std::string& s) { return QString::fromStdString(s); }

QVariantMap albumMap(const Album& a) {
  return {
      {"id", qs(a.id)},
      {"title", qs(a.name)},
      {"artist", qs(a.display_artist.empty() ? a.artist : a.display_artist)},
      {"year", a.year.value_or(0)},
      {"kind", a.kind.empty() ? QStringLiteral("physical") : qs(a.kind)},
      {"coverArt", qs(a.cover_art)},
      {"songCount", a.song_count},
      {"duration", a.duration},
      {"starred", a.starred.has_value()},
      {"created", qs(a.created)},
      {"artistId", qs(a.artist_id)},
  };
}

QVariantMap trackMap(const Song& s, const QString& work) {
  const std::string provenance = s.arrangement_provenance.value_or("");
  return {
      {"id", qs(s.id)},
      {"title", qs(s.title)},
      {"artist", qs(s.display_artist.empty() ? s.artist : s.display_artist)},
      {"duration", s.duration},
      {"coverArt", qs(s.cover_art)},
      {"work", work},
      {"album", qs(s.album)},
      {"albumId", qs(s.album_id)},
      {"starred", s.starred.has_value()},
      {"estimated", provenance == "rule" || provenance == "llm"},
      // ReplayGain of the track in dB; 0 when the file has none.
      {"gain", s.replay_gain ? s.replay_gain->track_gain.value_or(0.0) : 0.0},
  };
}

QString describe(const Error& e) {
  return e.offline() ? QStringLiteral("Cannot reach the server.") : qs(e.what());
}

QString describe(const std::exception& e) {
  if (const auto* error = dynamic_cast<const Error*>(&e)) return describe(*error);
  return QString::fromUtf8(e.what());
}

}  // namespace

Library::Library(QObject* parent) : QObject(parent) {
  // Show last run's album list at once; the server's answer replaces it.
  server_ = Session::instance()->serverUrl();
  loadCachedAlbums();
  if (Session::instance()->state() == Session::Ready) refreshAll();

  connect(Session::instance(), &Session::changed, this, [this] {
    const Session* session = Session::instance();
    // Another server, or nobody logged in: nothing of the last one may stay.
    if (session->state() == Session::LoggedOut || session->serverUrl() != server_) {
      const bool otherServer = session->serverUrl() != server_;
      server_ = session->serverUrl();
      reset();
      if (otherServer && session->state() != Session::LoggedOut) {
        loadCachedAlbums();
        if (!albums_.isEmpty()) emit albumsChanged();
      }
    }
    if (session->state() != Session::Ready) return;

    if (artists_.isEmpty()) refreshArtists();
    if (playlists_.isEmpty()) refreshPlaylists();
    if (!deferred_.isEmpty()) {
      const auto calls = deferred_;
      deferred_.clear();
      for (const auto& call : calls) call();
    }
    if (!waiting_.isEmpty()) {
      const QStringList ids = waiting_;
      waiting_.clear();
      for (const QString& id : ids) loadAlbum(id);
    }
    if (!fresh_ && !loading_) refresh();
  });

  // kleulir stays in the tray for days: pick up what was added to the server meanwhile.
  auto* timer = new QTimer(this);
  timer->setInterval(15 * 60 * 1000);
  connect(timer, &QTimer::timeout, this, [this] {
    if (Session::instance()->state() == Session::Ready && !loading_) refreshAll();
  });
  timer->start();
}

void Library::refreshAll() {
  refresh();
  refreshArtists();
  refreshPlaylists();
}

// Forgets everything that came from a server.
void Library::reset() {
  ++generation_;
  waiting_.clear();
  deferred_.clear();
  details_.clear();
  fresh_ = false;
  if (!albums_.isEmpty()) {
    albums_.clear();
    emit albumsChanged();
  }
  if (!artists_.isEmpty()) {
    artists_.clear();
    emit artistsChanged();
  }
  if (!playlists_.isEmpty()) {
    playlists_.clear();
    emit playlistsChanged();
  }
  if (!starred_.isEmpty()) {
    starred_.clear();
    ++starRevision_;
    emit starsChanged();
  }
  if (loading_ || !error_.isEmpty()) {
    loading_ = false;
    error_.clear();
    emit statusChanged();
  }
}

// Hands an answer to the main thread, unless the session it was asked in is over
// (logged out, or logged in again): it would put one server's data into another's.
void Library::deliver(const std::shared_ptr<eos::client::Api>& api, std::function<void()> done) {
  Session::onMain([api, done = std::move(done)] {
    if (Session::instance()->api() == api) done();
  });
}

// For a failed call, from the worker thread: the UI says so instead of showing nothing.
void Library::report(const std::exception& e) {
  const QString text = describe(e);
  Session::onMain([this, text] { emit problem(text); });
}

Library* Library::instance() {
  static Library* library = new Library(QCoreApplication::instance());
  return library;
}

Library* Library::create(QQmlEngine*, QJSEngine*) {
  QJSEngine::setObjectOwnership(instance(), QJSEngine::CppOwnership);
  return instance();
}

void Library::refresh() {
  auto api = Session::instance()->api();
  if (!api) return;
  const bool eos = Session::instance()->eosFeatures();
  const int generation = ++generation_;
  loading_ = true;
  error_.clear();
  details_.clear();
  emit statusChanged();
  const QString cacheFile = cache::folder(Session::instance()->serverUrl()) + "/albums.json";

  Session::async([this, api, eos, generation, cacheFile] {
    QVariantList list;
    QString error;
    try {
      const int step = 500;
      if (eos) {
        // /ext lists physical and virtual albums together, in reading order.
        for (int offset = 0;; offset += step) {
          const auto page = api->ext_albums("all", {.limit = step, .offset = offset});
          for (const Album& a : page.items) list.append(albumMap(a));
          if (page.items.empty() || offset + step >= page.total) break;
        }
      } else {
        for (int offset = 0;; offset += step) {
          const auto page = api->album_list({.type = "alphabeticalByName", .size = step, .offset = offset});
          for (const Album& a : page) list.append(albumMap(a));
          if (static_cast<int>(page.size()) < step) break;
        }
      }
    } catch (const Error& e) {
      error = describe(e);
    } catch (const std::exception& e) {
      error = QString::fromUtf8(e.what());
    }
    if (error.isEmpty())
      cache::write(cacheFile, QJsonDocument(QJsonArray::fromVariantList(list)).toJson(QJsonDocument::Compact));
    deliver(api, [this, list, error, generation] {
      if (generation != generation_) return;
      loading_ = false;
      error_ = error;
      if (error.isEmpty()) {
        fresh_ = true;
        // Leave the list alone when nothing changed, so the grid is not rebuilt.
        absorbStars(list);
        if (albums_ != list) {
          albums_ = list;
          emit albumsChanged();
        }
      }
      emit statusChanged();
    });
  });
}

void Library::loadCachedAlbums() {
  const QString folder = cache::folder(Session::instance()->serverUrl());
  if (folder.isEmpty()) return;
  const QJsonDocument doc = QJsonDocument::fromJson(cache::read(folder + "/albums.json"));
  if (doc.isArray()) albums_ = doc.array().toVariantList();
}

void Library::loadAlbum(const QString& id) {
  // Opening an album again is instant; refresh() drops these.
  if (const auto found = details_.constFind(id); found != details_.constEnd()) {
    const QVariantMap album = *found;
    Session::onMain([this, id, album] { emit albumLoaded(id, album); });
    return;
  }
  auto api = Session::instance()->api();
  if (!api) {
    // Still reconnecting (the list on screen came from the cache): load it once
    // the session is ready.
    if (!waiting_.contains(id)) waiting_.append(id);
    return;
  }
  const bool eos = Session::instance()->eosFeatures();

  Session::async([this, api, eos, id] {
    try {
      QVariantMap album;
      QVariantList tracks;
      if (eos) {
        const auto detail = api->ext_album(id.toStdString());
        album = albumMap(detail.album);
        // In the album's own order; each song is labelled with its works, so the page can
        // head runs of songs from one work without moving any song.
        QHash<QString, QStringList> works;
        for (const TitleGroup& group : api->album_titles(id.toStdString()))
          if (group.title)
            for (const Song& s : group.songs) works[qs(s.id)].append(qs(group.title->name));
        for (const Song& s : detail.album.songs) tracks.append(trackMap(s, works.value(qs(s.id)).join(" / ")));
      } else {
        const auto full = api->album(id.toStdString());
        album = albumMap(full);
        for (const Song& s : full.songs) tracks.append(trackMap(s, {}));
      }
      album["tracks"] = tracks;
      deliver(api, [this, id, album] {
        details_.insert(id, album);
        absorbStars(album.value("tracks").toList());
        emit albumLoaded(id, album);
      });
    } catch (const Error& e) {
      const QString text = describe(e);
      deliver(api, [this, id, text] { emit albumFailed(id, text); });
    } catch (const std::exception& e) {
      const QString text = QString::fromUtf8(e.what());
      deliver(api, [this, id, text] { emit albumFailed(id, text); });
    }
  });
}

void Library::absorbStars(const QVariantList& items) {
  bool changed = false;
  for (const QVariant& item : items) {
    const QVariantMap map = item.toMap();
    const QString id = map.value("id").toString();
    if (id.isEmpty()) continue;
    const bool on = map.value("starred").toBool();
    if (on != starred_.contains(id)) {
      changed = true;
      if (on)
        starred_.insert(id);
      else
        starred_.remove(id);
    }
  }
  if (changed) {
    ++starRevision_;
    emit starsChanged();
  }
}

void Library::setStarred(const QStringList& ids, bool starred) {
  auto api = Session::instance()->api();
  if (!api || ids.isEmpty()) return;

  const auto apply = [this](const QStringList& which, bool on) {
    for (const QString& id : which) {
      if (on)
        starred_.insert(id);
      else
        starred_.remove(id);
    }
    ++starRevision_;
    emit starsChanged();
  };
  apply(ids, starred);
  details_.clear();  // their `starred` flags are now out of date

  Session::async([this, api, ids, starred, apply] {
    std::vector<std::string> list;
    for (const QString& id : ids) list.push_back(id.toStdString());
    try {
      if (starred)
        api->star(list);
      else
        api->unstar(list);
    } catch (const std::exception& e) {
      report(e);
      deliver(api, [ids, starred, apply] { apply(ids, !starred); });
    }
  });
}

void Library::search(const QString& query) {
  auto api = Session::instance()->api();
  const QString text = query.trimmed();
  if (text.isEmpty()) {
    emit searchLoaded(query, {});
    return;
  }
  if (!api) {
    whenReady([this, query] { search(query); });
    return;
  }
  const bool eos = Session::instance()->eosFeatures();

  Session::async([this, api, eos, query, text] {
    QVariantList albums, songs;
    try {
      if (eos) {
        // /ext groups hits by composition; the songs of those groups come first.
        const auto found = api->ext_search(text.toStdString(), 30);
        QSet<QString> seen;
        const auto add = [&](const Song& s) {
          const QString id = qs(s.id);
          if (seen.contains(id)) return;
          seen.insert(id);
          songs.append(trackMap(s, {}));
        };
        for (const auto& hit : found.compositions)
          for (const Song& s : hit.songs) add(s);
        for (const Song& s : found.songs) add(s);
        for (const Album& a : found.albums) albums.append(albumMap(a));
      } else {
        const auto found = api->search({.query = text.toStdString(), .album_count = 30, .song_count = 50});
        for (const Song& s : found.songs) songs.append(trackMap(s, {}));
        for (const Album& a : found.albums) albums.append(albumMap(a));
      }
    } catch (const std::exception& e) {
      report(e);
      // Leave the lists empty; the page shows "no results".
    }
    deliver(api, [this, query, albums, songs] {
      absorbStars(albums);
      absorbStars(songs);
      emit searchLoaded(query, {{"albums", albums}, {"songs", songs}});
    });
  });
}

// ---- starred -------------------------------------------------------------------

void Library::whenReady(std::function<void()> call) {
  if (Session::instance()->api())
    call();
  else
    deferred_.append(std::move(call));
}

void Library::loadStarred() {
  auto api = Session::instance()->api();
  if (!api) {
    whenReady([this] { loadStarred(); });
    return;
  }
  Session::async([this, api] {
    QVariantList albums, songs;
    try {
      const auto found = api->starred();
      for (const Album& a : found.albums) albums.append(albumMap(a));
      for (const Song& s : found.songs) songs.append(trackMap(s, {}));
    } catch (const std::exception& e) {
      report(e);
      // Leave the lists empty.
    }
    deliver(api, [this, albums, songs] {
      absorbStars(albums);
      absorbStars(songs);
      emit starredLoaded({{"albums", albums}, {"songs", songs}});
    });
  });
}

// ---- artists -------------------------------------------------------------------

void Library::refreshArtists() {
  auto api = Session::instance()->api();
  if (!api) return;
  Session::async([this, api] {
    QVariantList list;
    try {
      const auto all = api->artists();
      for (const ArtistIndex& group : all.index) {
        for (const Artist& a : group.artists) {
          list.append(QVariantMap{
              {"id", qs(a.id)},
              {"name", qs(a.name)},
              {"albumCount", a.album_count},
              {"index", qs(group.name)},
          });
        }
      }
    } catch (const std::exception& e) {
      report(e);
      return;  // keep what we have
    }
    deliver(api, [this, list] {
      if (artists_ == list) return;
      artists_ = list;
      emit artistsChanged();
    });
  });
}

void Library::loadArtist(const QString& id) {
  auto api = Session::instance()->api();
  if (!api) {
    whenReady([this, id] { loadArtist(id); });
    return;
  }
  Session::async([this, api, id] {
    try {
      const auto artist = api->artist(id.toStdString());
      QVariantList albums;
      for (const Album& a : artist.albums) albums.append(albumMap(a));
      const QVariantMap map{{"id", id}, {"name", qs(artist.name)}, {"albums", albums}};
      deliver(api, [this, id, map, albums] {
        absorbStars(albums);
        emit artistLoaded(id, map);
      });
    } catch (const std::exception& e) {
      report(e);
      deliver(api, [this, id] { emit artistLoaded(id, {{"id", id}, {"name", QString()}, {"albums", QVariantList()}}); });
    }
  });
}

// ---- playlists -----------------------------------------------------------------

namespace {

QVariantMap playlistMap(const Playlist& p) {
  return {
      {"id", qs(p.id)},       {"name", qs(p.name)},   {"songCount", p.song_count},
      {"duration", p.duration}, {"owner", qs(p.owner)}, {"comment", qs(p.comment)},
  };
}

std::vector<std::string> toStd(const QStringList& ids) {
  std::vector<std::string> out;
  for (const QString& id : ids) out.push_back(id.toStdString());
  return out;
}

}  // namespace

void Library::refreshPlaylists() {
  auto api = Session::instance()->api();
  if (!api) return;
  Session::async([this, api] {
    QVariantList list;
    try {
      for (const Playlist& p : api->playlists()) list.append(playlistMap(p));
    } catch (const std::exception& e) {
      report(e);
      return;
    }
    deliver(api, [this, list] {
      if (playlists_ == list) return;
      playlists_ = list;
      emit playlistsChanged();
    });
  });
}

void Library::loadPlaylist(const QString& id) {
  auto api = Session::instance()->api();
  if (!api) {
    whenReady([this, id] { loadPlaylist(id); });
    return;
  }
  Session::async([this, api, id] {
    try {
      const auto p = api->playlist(id.toStdString());
      QVariantMap map = playlistMap(p);
      QVariantList tracks;
      for (const Song& s : p.songs) tracks.append(trackMap(s, {}));
      map["tracks"] = tracks;
      deliver(api, [this, id, map, tracks] {
        absorbStars(tracks);
        emit playlistLoaded(id, map);
      });
    } catch (const std::exception& e) {
      report(e);
      // The page keeps what it shows.
    }
  });
}

void Library::createPlaylist(const QString& name, const QStringList& songIds) {
  auto api = Session::instance()->api();
  if (!api || name.trimmed().isEmpty()) return;
  Session::async([this, api, name, songIds] {
    try {
      const auto created = api->create_playlist(name.trimmed().toStdString(), toStd(songIds));
      const QString id = qs(created.id);
      deliver(api, [this, id, name] {
        refreshPlaylists();
        emit playlistCreated(id, name.trimmed());
      });
    } catch (const std::exception& e) {
      report(e);
    }
  });
}

void Library::addToPlaylist(const QString& id, const QStringList& songIds) {
  auto api = Session::instance()->api();
  if (!api || songIds.isEmpty()) return;
  Session::async([this, api, id, songIds] {
    try {
      PlaylistUpdate update;
      update.add_song_ids = toStd(songIds);
      api->update_playlist(id.toStdString(), update);
      deliver(api, [this, id] {
        refreshPlaylists();
        emit playlistChanged(id);
      });
    } catch (const std::exception& e) {
      report(e);
    }
  });
}

void Library::removeFromPlaylist(const QString& id, const QVariantList& indexes) {
  auto api = Session::instance()->api();
  if (!api || indexes.isEmpty()) return;
  Session::async([this, api, id, indexes] {
    try {
      PlaylistUpdate update;
      for (const QVariant& index : indexes) update.remove_indexes.push_back(index.toInt());
      api->update_playlist(id.toStdString(), update);
      deliver(api, [this, id] {
        refreshPlaylists();
        emit playlistChanged(id);
      });
    } catch (const std::exception& e) {
      report(e);
    }
  });
}

void Library::renamePlaylist(const QString& id, const QString& name) {
  auto api = Session::instance()->api();
  if (!api || name.trimmed().isEmpty()) return;
  Session::async([this, api, id, name] {
    try {
      PlaylistUpdate update;
      update.name = name.trimmed().toStdString();
      api->update_playlist(id.toStdString(), update);
      deliver(api, [this, id] {
        refreshPlaylists();
        emit playlistChanged(id);
      });
    } catch (const std::exception& e) {
      report(e);
    }
  });
}

void Library::deletePlaylist(const QString& id) {
  auto api = Session::instance()->api();
  if (!api) return;
  Session::async([this, api, id] {
    try {
      api->delete_playlist(id.toStdString());
      deliver(api, [this, id] {
        refreshPlaylists();
        emit playlistDeleted(id);
      });
    } catch (const std::exception& e) {
      report(e);
    }
  });
}

// ---- eos: works, compositions, versions, folders --------------------------------

namespace {

QString names(const std::vector<ArtistRef>& artists) {
  QStringList out;
  for (const ArtistRef& a : artists) out << qs(a.name);
  return out.join(QStringLiteral(", "));
}

// What an arrangement is called in a list: its name, else its kind, and
// "Original" for the one a composition has without anybody arranging it.
QString arrangementLabel(const Arrangement& a) {
  if (a.name && !a.name->empty()) return qs(*a.name);
  if (a.is_implicit) return QStringLiteral("Original");
  if (!a.kind.empty()) return qs(a.kind).left(1).toUpper() + qs(a.kind).mid(1);
  return QStringLiteral("Arrangement");
}

QString relationLabel(const Relation& r) {
  const bool out = r.direction != "in";
  if (r.type == "medley") return out ? QStringLiteral("Contains") : QStringLiteral("Part of a medley");
  if (r.type == "quote") return out ? QStringLiteral("Quotes") : QStringLiteral("Quoted by");
  if (r.type == "derivative") return out ? QStringLiteral("Based on") : QStringLiteral("Derived versions");
  if (r.type == "cover") return out ? QStringLiteral("Cover of") : QStringLiteral("Covered by");
  return QStringLiteral("Related");
}

QVariantMap workMap(const Title& t) {
  return {
      {"id", qs(t.id)},
      {"name", qs(t.name)},
      {"kind", qs(t.kind.value_or(""))},
      {"year", t.year.value_or(0)},
      {"songCount", t.song_count.value_or(0)},
  };
}

}  // namespace

void Library::loadWorks() {
  auto api = Session::instance()->api();
  if (!api) {
    whenReady([this] { loadWorks(); });
    return;
  }
  Session::async([this, api] {
    QVariantList list;
    try {
      const int step = 500;
      for (int offset = 0;; offset += step) {
        const auto page = api->titles({}, {.limit = step, .offset = offset});
        for (const Title& t : page.items) list.append(workMap(t));
        if (page.items.empty() || offset + step >= page.total) break;
      }
    } catch (const std::exception& e) {
      report(e);
      // Leave what was read; the page shows it, or that there is nothing.
    }
    deliver(api, [this, list] { emit worksLoaded(list); });
  });
}

void Library::loadWork(const QString& id) {
  auto api = Session::instance()->api();
  if (!api) {
    whenReady([this, id] { loadWork(id); });
    return;
  }
  Session::async([this, api, id] {
    QVariantMap map{{"id", id}};
    QVariantList albums, songs;
    try {
      const auto detail = api->title(id.toStdString());
      map = workMap(detail.title);
      for (const Album& a : detail.albums) albums.append(albumMap(a));
      for (const Song& s : detail.songs) songs.append(trackMap(s, {}));
    } catch (const std::exception& e) {
      report(e);
    }
    map["albums"] = albums;
    map["songs"] = songs;
    deliver(api, [this, id, map, albums, songs] {
      absorbStars(albums);
      absorbStars(songs);
      emit workLoaded(id, map);
    });
  });
}

void Library::loadCompositions() {
  auto api = Session::instance()->api();
  if (!api) {
    whenReady([this] { loadCompositions(); });
    return;
  }
  Session::async([this, api] {
    QVariantList list;
    try {
      const int step = 500;
      for (int offset = 0;; offset += step) {
        const auto page = api->compositions({}, {.limit = step, .offset = offset});
        for (const Composition& c : page.items)
          list.append(QVariantMap{{"id", qs(c.id)}, {"name", qs(c.name)}, {"composers", names(c.composers)}});
        if (page.items.empty() || offset + step >= page.total) break;
      }
    } catch (const std::exception& e) {
      report(e);
    }
    deliver(api, [this, list] { emit compositionsLoaded(list); });
  });
}

void Library::loadComposition(const QString& id) {
  auto api = Session::instance()->api();
  if (!api) {
    whenReady([this, id] { loadComposition(id); });
    return;
  }
  Session::async([this, api, id] {
    QVariantMap map{{"id", id}};
    QVariantList songs;
    try {
      const auto detail = api->composition(id.toStdString());
      map["name"] = qs(detail.composition.name);
      map["composers"] = names(detail.composition.composers);
      for (const ArrangementSongs& group : detail.arrangements)
        for (const Song& s : group.songs) songs.append(trackMap(s, arrangementLabel(group.arrangement)));
    } catch (const std::exception& e) {
      report(e);
    }
    map["songs"] = songs;
    deliver(api, [this, id, map, songs] {
      absorbStars(songs);
      emit compositionLoaded(id, map);
    });
  });
}

void Library::loadVersions(const QString& songId) {
  auto api = Session::instance()->api();
  if (!api) {
    whenReady([this, songId] { loadVersions(songId); });
    return;
  }
  Session::async([this, api, songId] {
    QVariantMap map;
    QVariantList songs, compositions;
    try {
      const auto v = api->song_versions(songId.toStdString());
      if (v.composition) {
        map["compositionId"] = qs(v.composition->id);
        map["compositionName"] = qs(v.composition->name);
        map["composers"] = names(v.composition->composers);
      }
      for (const Song& s : v.performances) songs.append(trackMap(s, QStringLiteral("Same arrangement")));
      for (const ArrangementSongs& group : v.arrangements)
        for (const Song& s : group.songs) songs.append(trackMap(s, arrangementLabel(group.arrangement)));
      for (const RelatedItem& item : v.related) {
        if (item.song) {
          songs.append(trackMap(*item.song, relationLabel(item.relation)));
        } else if (item.composition) {
          compositions.append(QVariantMap{{"id", qs(item.composition->id)},
                                          {"name", qs(item.composition->name)},
                                          {"relation", relationLabel(item.relation)}});
        }
      }
    } catch (const std::exception& e) {
      report(e);
    }
    map["songs"] = songs;
    map["compositions"] = compositions;
    deliver(api, [this, songId, map, songs] {
      absorbStars(songs);
      emit versionsLoaded(songId, map);
    });
  });
}

void Library::loadFolders() {
  auto api = Session::instance()->api();
  if (!api) {
    whenReady([this] { loadFolders(); });
    return;
  }
  Session::async([this, api] {
    QVariantList list;
    try {
      for (const Folder& f : api->folders()) {
        list.append(QVariantMap{
            {"id", qs(f.id)},
            {"name", qs(f.name)},
            {"parentId", qs(f.parent_id.value_or(""))},
            {"sortOrder", f.sort_order.value_or(0)},
            {"albumCount", f.album_count},
            {"childCount", f.child_count},
        });
      }
    } catch (const std::exception& e) {
      report(e);
    }
    deliver(api, [this, list] { emit foldersLoaded(list); });
  });
}

void Library::loadFolder(const QString& id) {
  auto api = Session::instance()->api();
  if (!api) {
    whenReady([this, id] { loadFolder(id); });
    return;
  }
  Session::async([this, api, id] {
    QVariantMap map{{"id", id}};
    QVariantList albums;
    try {
      const auto detail = api->folder(id.toStdString());
      map["name"] = qs(detail.folder.name);
      for (const Album& a : detail.albums) albums.append(albumMap(a));
    } catch (const std::exception& e) {
      report(e);
    }
    map["albums"] = albums;
    deliver(api, [this, id, map, albums] {
      absorbStars(albums);
      emit folderLoaded(id, map);
    });
  });
}

// ---- eos: the graph of related songs ----------------------------------------------

namespace {

QString capitalised(const std::string& s) {
  const QString q = qs(s);
  return q.left(1).toUpper() + q.mid(1);
}

QString edgeLabel(const GraphEdge& e) {
  if (e.type == "performance") {
    if (e.arrangement_name && !e.arrangement_name->empty()) return qs(*e.arrangement_name);
    return e.is_original ? QStringLiteral("Original") : capitalised(e.arrangement_kind.value_or("arrangement"));
  }
  if (e.type == "credit") return capitalised(e.role.value_or(""));
  if (e.type == "similar") return e.score ? QString::number(*e.score, 'f', 2) : QString();
  if (e.directed) return capitalised(e.type);  // medley, quote, derivative, cover, related
  return {};
}

}  // namespace

void Library::loadGraph(const QString& seed, const QString& mode) {
  auto api = Session::instance()->api();
  if (!api) {
    whenReady([this, seed, mode] { loadGraph(seed, mode); });
    return;
  }
  Session::async([this, api, seed, mode] {
    GraphQuery q{.seed = seed.toStdString()};
    if (mode == "similar") {
      q.depth = 1;
      q.include = {"similar"};
      q.similar_k = 10;
    } else {
      q.depth = 2;
      q.include = {"composition", "relation", "title"};
      q.limit = 120;
      // "sure": only the estimates MusicBrainz backs directly (a recording of the work, an
      // arrangement of it, a part of it); name and audio matches are left out.
      if (mode == "sure") q.rules = std::vector<std::string>{"musicbrainz_work", "musicbrainz_arrangement", "musicbrainz_parts"};
    }
    QVariantMap map;
    QVariantList nodes, edges, songs;
    try {
      const Graph g = api->graph(q);
      for (const GraphNode& n : g.nodes) {
        QVariantMap node{{"id", qs(n.id)},       {"type", qs(n.type)},          {"label", qs(n.label)},
                         {"distance", n.distance}, {"degree", n.degree},          {"expanded", n.expanded},
                         {"itemId", qs(n.id.substr(n.id.find(':') + 1))}};
        if (n.song) {
          const QVariantMap track = trackMap(*n.song, QString());
          node["track"] = track;
          node["subtitle"] = track["album"].toString();
          songs.append(track);
        } else if (n.composition) {
          node["subtitle"] = names(n.composition->composers);
        } else if (n.title) {
          QStringList parts;
          if (n.title->kind) parts << capitalised(*n.title->kind);
          if (n.title->year) parts << QString::number(*n.title->year);
          node["subtitle"] = parts.join(QStringLiteral(" · "));
        } else if (n.album) {
          node["subtitle"] = qs(n.album->display_artist.empty() ? n.album->artist : n.album->display_artist);
        }
        nodes.append(node);
      }
      for (const GraphEdge& e : g.edges) {
        edges.append(QVariantMap{{"from", qs(e.from)},
                                 {"to", qs(e.to)},
                                 {"type", qs(e.type)},
                                 {"label", edgeLabel(e)},
                                 {"score", e.score.value_or(0.0)},
                                 {"directed", e.directed},
                                 {"estimated", e.provenance == "rule" || e.provenance == "llm"}});
      }
      map["truncated"] = g.truncated;
    } catch (const Error& e) {
      map["error"] = describe(e);
    } catch (const std::exception& e) {
      map["error"] = QString::fromUtf8(e.what());
    }
    map["nodes"] = nodes;
    map["edges"] = edges;
    deliver(api, [this, seed, mode, map, songs] {
      absorbStars(songs);
      emit graphLoaded(seed, mode, map);
    });
  });
}
