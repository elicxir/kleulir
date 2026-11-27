pragma Singleton
import QtQuick
import Kleulir

// Where the content area is, with a back/forward history like a browser's.
// An entry is { page: "albums" | "album" | "search" | "settings", album? }.
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
        return a.page === b.page && (a.page !== "album" || a.album.id === b.album.id)
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

    function search(text) {
        query = text
        if (text.trim().length > 0 && current.page !== "search")
            go({ page: "search" })
    }
}
