import QtQuick
import Kleulir

// Right-click menu for one or more songs. Set `tracks` (and `album`, when they come
// from an album page) and call popup().
PopupMenu {
    id: root
    property var tracks: []
    property var album: null
    // Off where the songs already are their album's page.
    property bool showGoToAlbum: true

    readonly property int picked: tracks.length
    readonly property bool allStarred: {
        Library.starRevision
        return picked > 0 && tracks.every(t => Library.isStarred(t.id))
    }

    PopupMenuItem {
        text: root.picked > 1 ? "Play " + root.picked + " tracks" : "Play"
        onTriggered: Player.playTracks(root.tracks, root.album, 0)
    }
    PopupMenuItem {
        text: "Play next"
        onTriggered: Player.playNextMany(root.tracks, root.album)
    }
    PopupMenuItem {
        text: "Add to queue"
        onTriggered: Player.enqueueMany(root.tracks, root.album)
    }
    MenuDivider {}
    PopupMenuItem {
        text: root.allStarred ? "Remove from Starred" : "Add to Starred"
        onTriggered: Library.setStarred(root.tracks.map(t => t.id), !root.allStarred)
    }
    PopupMenuItem {
        visible: root.showGoToAlbum && root.picked === 1 && !!root.tracks[0].albumId
        text: "Go to album"
        onTriggered: Nav.openAlbumId(root.tracks[0].albumId, root.tracks[0].album)
    }
}
