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
  if (Session::instance()->state() == Session::Ready) refresh();

  connect(Session::instance(), &Session::changed, this, [this] {
    const bool ready = Session::instance()->state() == Session::Ready;
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
      details_.clear();
      waiting_.clear();
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
  if (!api || text.isEmpty()) {
    emit searchLoaded(query, {});
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
