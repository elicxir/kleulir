#include "library.h"

#include <QCoreApplication>
#include <QJSEngine>
#include <QJsonArray>
#include <QJsonDocument>

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

}  // namespace

Library::Library(QObject* parent) : QObject(parent) {
  // Show last run's album list at once; the server's answer replaces it.
  loadCachedAlbums();
  if (Session::instance()->state() == Session::Ready) {
    refresh();
    refreshArtists();
    refreshPlaylists();
  }

  connect(Session::instance(), &Session::changed, this, [this] {
    const bool ready = Session::instance()->state() == Session::Ready;
    if (ready && artists_.isEmpty()) refreshArtists();
    if (ready && playlists_.isEmpty()) refreshPlaylists();
    if (ready && !deferred_.isEmpty()) {
      const auto calls = deferred_;
      deferred_.clear();
      for (const auto& call : calls) call();
    }
    if (ready && !waiting_.isEmpty()) {
      const QStringList ids = waiting_;
      waiting_.clear();
      for (const QString& id : ids) loadAlbum(id);
    }
    if (ready && !fresh_ && !loading_) {
      refresh();
    } else if (Session::instance()->state() == Session::LoggedOut && !albums_.isEmpty()) {
      ++generation_;
      albums_.clear();
      artists_.clear();
      playlists_.clear();
      details_.clear();
      waiting_.clear();
      deferred_.clear();
      emit artistsChanged();
      emit playlistsChanged();
      fresh_ = false;
      emit albumsChanged();
    }
  });
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
    Session::onMain([this, list, error, generation] {
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
        // Grouped by the work each song belongs to; a song in two works shows in both.
        for (const TitleGroup& group : api->album_titles(id.toStdString())) {
          const QString work = group.title ? qs(group.title->name) : QString();
          for (const Song& s : group.songs) tracks.append(trackMap(s, work));
        }
      } else {
        const auto full = api->album(id.toStdString());
        album = albumMap(full);
        for (const Song& s : full.songs) tracks.append(trackMap(s, {}));
      }
      album["tracks"] = tracks;
      Session::onMain([this, id, album] {
        details_.insert(id, album);
        absorbStars(album.value("tracks").toList());
        emit albumLoaded(id, album);
      });
    } catch (const Error& e) {
      const QString text = describe(e);
      Session::onMain([this, id, text] { emit albumFailed(id, text); });
    } catch (const std::exception& e) {
      const QString text = QString::fromUtf8(e.what());
      Session::onMain([this, id, text] { emit albumFailed(id, text); });
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
    } catch (const std::exception&) {
      Session::onMain([ids, starred, apply] { apply(ids, !starred); });
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
    } catch (const std::exception&) {
      // Leave the lists empty; the page shows "no results".
    }
    Session::onMain([this, query, albums, songs] {
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
    } catch (const std::exception&) {
      // Leave the lists empty.
    }
    Session::onMain([this, albums, songs] {
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
    } catch (const std::exception&) {
      return;  // keep what we have
    }
    Session::onMain([this, list] {
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
      Session::onMain([this, id, map, albums] {
        absorbStars(albums);
        emit artistLoaded(id, map);
      });
    } catch (const std::exception&) {
      Session::onMain([this, id] { emit artistLoaded(id, {{"id", id}, {"name", QString()}, {"albums", QVariantList()}}); });
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
    } catch (const std::exception&) {
      return;
    }
    Session::onMain([this, list] {
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
      Session::onMain([this, id, map, tracks] {
        absorbStars(tracks);
        emit playlistLoaded(id, map);
      });
    } catch (const std::exception&) {
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
      Session::onMain([this, id, name] {
        refreshPlaylists();
        emit playlistCreated(id, name.trimmed());
      });
    } catch (const std::exception&) {
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
      Session::onMain([this, id] {
        refreshPlaylists();
        emit playlistChanged(id);
      });
    } catch (const std::exception&) {
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
      Session::onMain([this, id] {
        refreshPlaylists();
        emit playlistChanged(id);
      });
    } catch (const std::exception&) {
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
      Session::onMain([this, id] {
        refreshPlaylists();
        emit playlistChanged(id);
      });
    } catch (const std::exception&) {
    }
  });
}

void Library::deletePlaylist(const QString& id) {
  auto api = Session::instance()->api();
  if (!api) return;
  Session::async([this, api, id] {
    try {
      api->delete_playlist(id.toStdString());
      Session::onMain([this, id] {
        refreshPlaylists();
        emit playlistDeleted(id);
      });
    } catch (const std::exception&) {
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
    } catch (const std::exception&) {
      // Leave what was read; the page shows it, or that there is nothing.
    }
    Session::onMain([this, list] { emit worksLoaded(list); });
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
    } catch (const std::exception&) {
    }
    map["albums"] = albums;
    map["songs"] = songs;
    Session::onMain([this, id, map, albums, songs] {
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
    } catch (const std::exception&) {
    }
    Session::onMain([this, list] { emit compositionsLoaded(list); });
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
    } catch (const std::exception&) {
    }
    map["songs"] = songs;
    Session::onMain([this, id, map, songs] {
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
    } catch (const std::exception&) {
    }
    map["songs"] = songs;
    map["compositions"] = compositions;
    Session::onMain([this, songId, map, songs] {
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
    } catch (const std::exception&) {
    }
    Session::onMain([this, list] { emit foldersLoaded(list); });
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
    } catch (const std::exception&) {
    }
    map["albums"] = albums;
    Session::onMain([this, id, map, albums] {
      absorbStars(albums);
      emit folderLoaded(id, map);
    });
  });
}
