#include "library.h"

#include <QCoreApplication>
#include <QJSEngine>

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
  connect(Session::instance(), &Session::changed, this, [this] {
    const bool ready = Session::instance()->state() == Session::Ready;
    if (ready && albums_.isEmpty() && !loading_) {
      refresh();
    } else if (Session::instance()->state() == Session::LoggedOut && !albums_.isEmpty()) {
      ++generation_;
      albums_.clear();
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
  emit albumsChanged();

  Session::async([this, api, eos, generation] {
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
    Session::onMain([this, list, error, generation] {
      if (generation != generation_) return;
      loading_ = false;
      error_ = error;
      if (error.isEmpty()) albums_ = list;
      emit albumsChanged();
    });
  });
}

void Library::loadAlbum(const QString& id) {
  auto api = Session::instance()->api();
  if (!api) return;
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
      Session::onMain([this, id, album] { emit albumLoaded(id, album); });
    } catch (const Error& e) {
      const QString text = describe(e);
      Session::onMain([this, id, text] { emit albumFailed(id, text); });
    } catch (const std::exception& e) {
      const QString text = QString::fromUtf8(e.what());
      Session::onMain([this, id, text] { emit albumFailed(id, text); });
    }
  });
}
