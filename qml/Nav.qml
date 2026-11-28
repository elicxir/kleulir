pragma Singleton
import QtQuick
import Kleulir

// Where the content area is, with a back/forward history like a browser's.
// An entry is { page, album? | artist? | playlist? | ... }; page is one of albums,
// album, artists, artist, starred, playlists, playlist, search, settings, and on an
// eos server folders, folder, works, work, compositions, composition, versions, graph.
// song (one song's details, { song: { id, title } }) is there on every server.
QtObject {
    id: root

    property var entries: [{ page: "albums" }]
    property int index: 0
    readonly property var current: entries[index]
    readonly property bool canBack: index > 0
    readonly property bool canForward: index < entries.length - 1

    // The search text. Typing changes this without adding history entries.
    property string query: ""

    function same(a, b) {
        if (a.page !== b.page)
            return false
        if (a.page === "album")
            return a.album.id === b.album.id
        if (a.page === "artist")
            return a.artist.id === b.artist.id
        if (a.page === "playlist")
            return a.playlist.id === b.playlist.id
        if (a.page === "folder")
            return a.folder.id === b.folder.id
        if (a.page === "work")
            return a.work.id === b.work.id
        if (a.page === "composition")
            return a.composition.id === b.composition.id
        if (a.page === "versions" || a.page === "song")
            return a.song.id === b.song.id
        if (a.page === "graph")
            return a.seed === b.seed && a.mode === b.mode
        return true
    }

    function go(entry) {
        if (same(entry, current))
            return
        entries = entries.slice(0, index + 1).concat([entry])
        index = entries.length - 1
    }

    function back() {
        if (canBack)
            --index
    }

    function forward() {
        if (canForward)
            ++index
    }

    function openPage(page) {
        go({ page: page })
    }

    function openAlbum(album) {
        go({ page: "album", album: album })
    }

    // From a song: the album is looked up in the library list, which has its cover
    // and artist; failing that the page starts with just the id and title.
    function openAlbumId(id, title) {
        if (!id)
            return
        const found = Library.albums.find(a => a.id === id)
        openAlbum(found || { id: id, title: title || "", artist: "", year: 0, kind: "physical", coverArt: "" })
    }

    function openSong(id, title) {
        if (id)
            go({ page: "song", song: { id: id, title: title || "" } })
    }

    function search(text) {
        query = text
        if (text.trim().length > 0 && current.page !== "search")
            go({ page: "search" })
    }
}
