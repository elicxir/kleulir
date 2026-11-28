#include "library.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QHash>
#include <QJSEngine>
#include <QJsonArray>
#include <QJsonDocument>
#include <QLocale>
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
      // The first artist's page is where a click on the name goes.
      {"artistId", qs(!s.artists.empty() && !s.artists[0].id.empty() ? s.artists[0].id : s.artist_id)},
      {"artistName", qs(!s.artists.empty() && !s.artists[0].name.empty() ? s.artists[0].name : s.artist)},
      {"duration", s.duration},
      {"coverArt", qs(s.cover_art)},
      {"work", work},
      {"album", qs(s.album)},
      {"albumId", qs(s.album_id)},
      {"starred", s.starred.has_value()},
      {"estimated", provenance == "rule" || provenance == "llm"},
      // Other recordings of the same composition (eos only).
      {"variations", s.variation_count},
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
              // The artist's picture; empty for most (the server has one only when given).
              {"coverArt", qs(a.cover_art)},
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
      const QVariantMap map{
          {"id", id}, {"name", qs(artist.name)}, {"albums", albums}, {"coverArt", qs(artist.cover_art)}};
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
      // The song asked about leads its own group, so the page lists every variation.
      songs.append(trackMap(v.song, QStringLiteral("This arrangement")));
      for (const Song& s : v.performances) songs.append(trackMap(s, QStringLiteral("This arrangement")));
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

// ---- song details ----

namespace {

QVariantMap textItem(const QString& text) { return {{"text", text}}; }

QVariantMap navItem(const QString& text, const QVariantMap& nav) { return {{"text", text}, {"nav", nav}}; }

QVariantMap urlItem(const QString& text, const QString& url) { return {{"text", text}, {"url", url}}; }

QVariantMap rowOf(const QString& label, const QVariantList& items, const QString& note = {}, bool estimated = false) {
  return {{"label", label}, {"items", items}, {"note", note}, {"estimated", estimated}};
}

// A row with one plain value; nothing when the value is empty.
void addRow(QVariantList& rows, const QString& label, const QString& value) {
  if (!value.isEmpty()) rows.append(rowOf(label, {textItem(value)}));
}

void addSection(QVariantList& sections, const QString& title, const QVariantList& rows) {
  if (!rows.isEmpty()) sections.append(QVariantMap{{"title", title}, {"rows", rows}});
}

QVariantMap artistNav(const ArtistRef& a) {
  return {{"page", "artist"}, {"artist", QVariantMap{{"id", qs(a.id)}, {"name", qs(a.name)}}}};
}

QVariantList artistItems(const std::vector<ArtistRef>& artists) {
  QVariantList items;
  for (const ArtistRef& a : artists) {
    if (a.name.empty()) continue;
    items.append(a.id.empty() ? textItem(qs(a.name)) : navItem(qs(a.name), artistNav(a)));
  }
  return items;
}

// "2026-11-28 21:47" in local time from the server's ISO 8601 (UTC); the text as it is
// when it does not parse.
QString localTime(const std::string& iso) {
  if (iso.empty()) return {};
  const QDateTime t = QDateTime::fromString(qs(iso), Qt::ISODateWithMs);
  return t.isValid() ? t.toLocalTime().toString(QStringLiteral("yyyy-MM-dd HH:mm")) : qs(iso);
}

QString sizeText(int64_t bytes) {
  if (bytes <= 0) return {};
  const QLocale c = QLocale::c();
  if (bytes < 1024 * 1024) return c.toString(bytes / 1024.0, 'f', 0) + QStringLiteral(" KB");
  return c.toString(bytes / (1024.0 * 1024.0), 'f', 1) + QStringLiteral(" MB");
}

QString capitalized(const QString& s) { return s.left(1).toUpper() + s.mid(1); }

QString roleLabel(const Contributor& c) {
  if (c.role == "performer") return c.sub_role.empty() ? QStringLiteral("Performer") : capitalized(qs(c.sub_role));
  if (!c.sub_role.empty()) return capitalized(qs(c.role)) + " (" + qs(c.sub_role) + ")";
  return capitalized(qs(c.role));
}

QString gainText(const std::optional<double>& gain, const std::optional<double>& peak) {
  if (!gain && !peak) return {};
  QStringList parts;
  if (gain) parts << (*gain > 0 ? QStringLiteral("+") : QString()) + QString::number(*gain, 'f', 2) + QStringLiteral(" dB");
  if (peak) parts << QStringLiteral("peak ") + QString::number(*peak, 'f', 3);
  return parts.join(QStringLiteral(" · "));
}

bool estimated(const std::string& provenance) { return provenance == "rule" || provenance == "llm"; }

// Where a link came from, in a few words: "Tag", "Manual", or for an estimate what it
// rests on, how sure it is and the rule that made it.
QString linkNote(const LinkInfo& l) {
  if (l.provenance == "tag") return QStringLiteral("Tag");
  if (l.provenance == "manual") return QStringLiteral("Manual");
  const std::string origin = l.origin.value_or(l.provenance == "llm" ? "llm" : "");
  QStringList parts;
  parts << (origin == "external" ? QStringLiteral("Estimated from an outside database")
            : origin == "audio"  ? QStringLiteral("Estimated from the audio")
            : origin == "name"   ? QStringLiteral("Estimated from names")
            : origin == "llm"    ? QStringLiteral("Estimated by a language model")
                                 : QStringLiteral("Estimated"));
  if (l.confidence) parts << QString::number(qRound(*l.confidence * 100)) + QStringLiteral("%");
  if (l.rule && !l.rule->empty()) parts << qs(*l.rule);
  return parts.join(QStringLiteral(" · "));
}

QString provenanceNote(const std::string& provenance) {
  if (provenance == "tag") return QStringLiteral("Tag");
  if (provenance == "manual") return QStringLiteral("Manual");
  return estimated(provenance) ? QStringLiteral("Estimated") : QString();
}

// What every server tells about a song. `albumNav` is the entry the album name opens;
// `virtualAlbums` are rows that go right under the album (eos only).
QVariantList songSections(const Song& s, const QVariantMap& albumNav, const QVariantList& virtualAlbums = {}) {
  QVariantList sections, rows;

  addRow(rows, QStringLiteral("Title"), qs(s.title));
  QVariantList artists = artistItems(s.artists);
  if (artists.isEmpty()) {
    const QString name = qs(s.display_artist.empty() ? s.artist : s.display_artist);
    if (!name.isEmpty())
      artists.append(s.artist_id.empty() ? textItem(name) : navItem(name, artistNav({s.artist_id, name.toStdString()})));
  }
  if (!artists.isEmpty()) rows.append(rowOf(QStringLiteral("Artist"), artists));
  if (!s.album.empty())
    rows.append(rowOf(QStringLiteral("Album"),
                      {albumNav.isEmpty() ? textItem(qs(s.album)) : navItem(qs(s.album), albumNav)}));
  rows.append(virtualAlbums);
  QVariantList albumArtists = artistItems(s.album_artists);
  if (albumArtists.isEmpty() && !s.display_album_artist.empty()) albumArtists.append(textItem(qs(s.display_album_artist)));
  if (!albumArtists.isEmpty()) rows.append(rowOf(QStringLiteral("Album artist"), albumArtists));
  QStringList position;
  if (s.disc_number) position << QStringLiteral("Disc %1").arg(*s.disc_number);
  if (s.track) position << QStringLiteral("Track %1").arg(*s.track);
  addRow(rows, QStringLiteral("Position"), position.join(QStringLiteral(" · ")));
  if (s.year) addRow(rows, QStringLiteral("Year"), QString::number(*s.year));
  QStringList genres;
  for (const std::string& g : s.genres) genres << qs(g);
  if (genres.isEmpty() && !s.genre.empty()) genres << qs(s.genre);
  addRow(rows, QStringLiteral("Genre"), genres.join(QStringLiteral(", ")));
  if (s.duration > 0) {
    const int m = s.duration / 60, sec = s.duration % 60;
    addRow(rows, QStringLiteral("Length"), QStringLiteral("%1:%2").arg(m).arg(sec, 2, 10, QLatin1Char('0')));
  }
  addSection(sections, QStringLiteral("Song"), rows);

  // People by what they did, in the order the server gives them.
  rows.clear();
  QStringList labels;
  QHash<QString, QVariantList> people;
  for (const Contributor& c : s.contributors) {
    if (c.artist.name.empty()) continue;
    const QString label = roleLabel(c);
    if (!people.contains(label)) labels << label;
    people[label].append(c.artist.id.empty() ? textItem(qs(c.artist.name))
                                              : navItem(qs(c.artist.name), artistNav(c.artist)));
  }
  for (const QString& label : labels) rows.append(rowOf(label, people[label]));
  if (!people.contains(QStringLiteral("Composer"))) addRow(rows, QStringLiteral("Composer"), qs(s.display_composer));
  addSection(sections, QStringLiteral("Credits"), rows);

  rows.clear();
  addRow(rows, QStringLiteral("Plays"), QString::number(s.play_count));
  addRow(rows, QStringLiteral("Last played"), localTime(s.played.value_or("")));
  addRow(rows, QStringLiteral("Starred"), localTime(s.starred.value_or("")));
  if (s.user_rating && *s.user_rating > 0)
    addRow(rows, QStringLiteral("Rating"), QString(*s.user_rating, QChar(0x2605)) + QString(5 - *s.user_rating, QChar(0x2606)));
  addSection(sections, QStringLiteral("Listening"), rows);
  return sections;
}

// The audio and the file, as far as a song from /rest says.
QVariantList fileRows(const Song& s) {
  QVariantList rows;
  QStringList format;
  if (!s.suffix.empty()) format << qs(s.suffix).toUpper();
  if (s.bit_depth && *s.bit_depth > 0) format << QStringLiteral("%1 bit").arg(*s.bit_depth);
  if (s.sampling_rate && *s.sampling_rate > 0)
    format << QString::number(*s.sampling_rate / 1000.0, 'g', 4) + QStringLiteral(" kHz");
  if (s.channel_count && *s.channel_count > 0)
    format << (*s.channel_count == 1 ? QStringLiteral("Mono")
               : *s.channel_count == 2 ? QStringLiteral("Stereo")
                                       : QStringLiteral("%1 channels").arg(*s.channel_count));
  if (s.bit_rate && *s.bit_rate > 0) format << QStringLiteral("%1 kbps").arg(*s.bit_rate);
  addRow(rows, QStringLiteral("Format"), format.join(QStringLiteral(" · ")));
  addRow(rows, QStringLiteral("Size"), sizeText(s.size));
  if (s.replay_gain) {
    addRow(rows, QStringLiteral("Track gain"), gainText(s.replay_gain->track_gain, s.replay_gain->track_peak));
    addRow(rows, QStringLiteral("Album gain"), gainText(s.replay_gain->album_gain, s.replay_gain->album_peak));
  }
  return rows;
}

}  // namespace

void Library::loadSong(const QString& id) {
  auto api = Session::instance()->api();
  if (!api) {
    whenReady([this, id] { loadSong(id); });
    return;
  }
  const bool eos = Session::instance()->eosFeatures();
  const bool detailed = Session::instance()->hasFeature(QStringLiteral("songDetail"));
  Session::async([this, api, id, eos, detailed] {
    QVariantMap map{{"id", id}};
    try {
      SongDetail d;
      if (detailed)
        d = api->song_detail(id.toStdString());
      else
        d.song = eos ? api->ext_song(id.toStdString()) : api->song(id.toStdString());
      const Song& s = d.song;

      map["title"] = qs(s.title);
      map["artist"] = qs(s.display_artist.empty() ? s.artist : s.display_artist);
      map["album"] = qs(s.album);
      map["albumId"] = qs(s.album_id);
      map["coverArt"] = qs(s.cover_art);
      map["duration"] = s.duration;
      map["track"] = trackMap(s, QString());

      QVariantMap albumNav;
      if (detailed)
        albumNav = {{"page", "album"}, {"album", albumMap(d.album)}};
      else if (!s.album_id.empty())
        albumNav = {{"page", "album"},
                    {"album", QVariantMap{{"id", qs(s.album_id)}, {"title", qs(s.album)}, {"artist", QString()},
                                          {"year", 0}, {"kind", "physical"}, {"coverArt", qs(s.cover_art)}}}};
      // Each virtual album the song is on, with its place there and where that came from.
      QVariantList virtualAlbums;
      for (const SongDetail::VirtualAlbumLink& v : d.virtual_albums) {
        QStringList about;
        if (v.disc_number) about << QStringLiteral("Disc %1").arg(*v.disc_number);
        if (v.track_number) about << QStringLiteral("Track %1").arg(*v.track_number);
        about << linkNote(v.link);
        virtualAlbums.append(rowOf(QStringLiteral("Virtual album"),
                                   {navItem(qs(v.album.name), QVariantMap{{"page", "album"}, {"album", albumMap(v.album)}})},
                                   about.join(QStringLiteral(" · ")), estimated(v.link.provenance)));
      }
      QVariantList sections = songSections(s, albumNav, virtualAlbums);

      // What the music is: composition, arrangement, works. Only an eos server knows.
      QVariantList music;
      if (d.composition) {
        const QVariantMap nav{{"page", "composition"},
                              {"composition", QVariantMap{{"id", qs(d.composition->id)}, {"name", qs(d.composition->name)}}}};
        const bool guess = d.arrangement_link && estimated(d.arrangement_link->provenance);
        music.append(rowOf(QStringLiteral("Composition"), {navItem(qs(d.composition->name), nav)},
                           d.arrangement_link ? linkNote(*d.arrangement_link) : QString(), guess));
        if (d.arrangement_link && d.arrangement_link->origin_ref && d.arrangement_link->origin_ref->starts_with("http"))
          music.append(rowOf(QStringLiteral("Source"), {urlItem(qs(*d.arrangement_link->origin_ref),
                                                                qs(*d.arrangement_link->origin_ref))}));
        const QVariantList composers = artistItems(d.composition->composers);
        if (!composers.isEmpty())
          music.append(rowOf(QStringLiteral("Composed by"), composers, provenanceNote(d.composition->provenance),
                             estimated(d.composition->provenance)));
        if (d.composition->music_brainz_work_id && !d.composition->music_brainz_work_id->empty())
          music.append(rowOf(QStringLiteral("MusicBrainz work"),
                             {urlItem(qs(*d.composition->music_brainz_work_id),
                                      "https://musicbrainz.org/work/" + qs(*d.composition->music_brainz_work_id))}));
      }
      if (d.arrangement) {
        music.append(rowOf(QStringLiteral("Arrangement"), {textItem(arrangementLabel(*d.arrangement))},
                           provenanceNote(d.arrangement->provenance), estimated(d.arrangement->provenance)));
        const QVariantList arrangers = artistItems(d.arrangement->arrangers);
        if (!arrangers.isEmpty()) music.append(rowOf(QStringLiteral("Arranged by"), arrangers));
      }
      for (const SongDetail::TitleLink& t : d.titles) {
        QStringList about;
        if (t.title.kind && !t.title.kind->empty()) about << capitalized(qs(*t.title.kind));
        if (t.title.year && *t.title.year > 0) about << QString::number(*t.title.year);
        about << linkNote(t.link);
        const QVariantMap nav{{"page", "work"}, {"work", QVariantMap{{"id", qs(t.title.id)}, {"name", qs(t.title.name)}}}};
        music.append(rowOf(QStringLiteral("Work"), {navItem(qs(t.title.name), nav)}, about.join(QStringLiteral(" · ")),
                           estimated(t.link.provenance)));
      }
      if (s.performance_kind) addRow(music, QStringLiteral("Performance"), capitalized(qs(*s.performance_kind)));
      if (s.recorded_date) addRow(music, QStringLiteral("Recorded"), qs(*s.recorded_date));
      if (!music.isEmpty())
        sections.insert(qMin<qsizetype>(2, sections.size()), QVariantMap{{"title", "Music"}, {"rows", music}});

      QVariantList file = fileRows(s);
      const QString path = detailed ? qs(d.file.path) : qs(s.path);
      addRow(file, QStringLiteral("Path"), path);
      if (detailed) {
        addRow(file, QStringLiteral("Library"), qs(d.file.library));
        addRow(file, QStringLiteral("Added"), localTime(d.file.added));
        addRow(file, QStringLiteral("File changed"), localTime(d.file.modified));
        addRow(file, QStringLiteral("Cover in file"), d.file.has_embedded_art ? QStringLiteral("Yes") : QStringLiteral("No"));
        addRow(file, QStringLiteral("Audio MD5"), qs(d.file.audio_md5.value_or("")));
        if (d.file.music_brainz_recording_id && !d.file.music_brainz_recording_id->empty())
          file.append(rowOf(QStringLiteral("MusicBrainz recording"),
                            {urlItem(qs(*d.file.music_brainz_recording_id),
                                     "https://musicbrainz.org/recording/" + qs(*d.file.music_brainz_recording_id))}));
      } else {
        addRow(file, QStringLiteral("Added"), localTime(s.created));
        if (!s.music_brainz_id.empty())
          file.append(rowOf(QStringLiteral("MusicBrainz recording"),
                            {urlItem(qs(s.music_brainz_id), "https://musicbrainz.org/recording/" + qs(s.music_brainz_id))}));
      }
      addRow(file, QStringLiteral("ID"), qs(s.id));
      addSection(sections, QStringLiteral("File"), file);

      QVariantList tags;
      for (const SongTag& t : d.tags) {
        QStringList values;
        for (const std::string& v : t.values) values << qs(v);
        addRow(tags, qs(t.key), values.join(QStringLiteral("; ")));
      }
      addSection(sections, QStringLiteral("Tags"), tags);

      map["sections"] = sections;
    } catch (const std::exception& e) {
      map["error"] = describe(e);
    }
    deliver(api, [this, id, map] {
      if (map.contains("track")) absorbStars({map["track"]});
      emit songLoaded(id, map);
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
      // "sure": tags, people, and what an outside database (MusicBrainz) states; name and
      // audio matches are left out.
      if (mode == "sure") q.origins = std::vector<std::string>{"external", "tag", "manual"};
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
