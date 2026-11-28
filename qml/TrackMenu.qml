import QtQuick
import QtQml.Models
import Kleulir

// Right-click menu for one or more songs. Set `tracks` (and `album`, when they come
// from an album page) and call popup().
PopupMenu {
    id: root
    property var tracks: []
    property var album: null
    // Off where the songs already are their album's page.
    property bool showGoToAlbum: true
    // Set on a playlist's page: offers "Remove from this playlist" for `rows`,
    // the songs' positions in it.
    property string playlistId: ""
    property var rows: []
    // Set on the graph page: "Show related graph" adds the song's neighbours to the graph
    // on screen (called with the track) instead of opening a new one.
    property var showGraph: null

    readonly property var ids: tracks.map(t => t.id)

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
    PopupMenu {
        id: playlistMenu
        title: "Add to playlist"
        PopupMenuItem {
            // Named after its first song, as other players do; rename it on its page.
            text: "New playlist"
            onTriggered: Library.createPlaylist(root.tracks[0].title, root.ids)
        }
        MenuDivider {}
        Instantiator {
            model: Library.playlists
            delegate: PopupMenuItem {
                required property var modelData
                text: modelData.name
                onTriggered: Library.addToPlaylist(modelData.id, root.ids)
            }
            onObjectAdded: (index, object) => playlistMenu.insertItem(index + 2, object)
            onObjectRemoved: (index, object) => playlistMenu.removeItem(object)
        }
    }
    PopupMenuItem {
        visible: root.playlistId.length > 0
        text: "Remove from this playlist"
        onTriggered: Library.removeFromPlaylist(root.playlistId, root.rows)
    }
    PopupMenuItem {
        text: root.allStarred ? "Remove from Starred" : "Add to Starred"
        onTriggered: Library.setStarred(root.tracks.map(t => t.id), !root.allStarred)
    }
    PopupMenuItem {
        // Other recordings of the same music; only an eos server knows them.
        visible: Session.eosFeatures && root.picked === 1
        text: "Show other versions"
        onTriggered: Nav.go({ page: "versions", song: root.tracks[0] })
    }
    PopupMenuItem {
        // The song's composition, work and their other songs, or the songs that sound alike.
        visible: Session.serverFeatures.indexOf("graph") >= 0 && root.picked === 1
        text: "Show related graph"
        onTriggered: {
            if (root.showGraph)
                root.showGraph(root.tracks[0])
            else
                Nav.go({ page: "graph", seed: "song:" + root.tracks[0].id, label: root.tracks[0].title, mode: "related" })
        }
    }
    PopupMenuItem {
        visible: root.showGoToAlbum && root.picked === 1 && !!root.tracks[0].albumId
        text: "Go to album"
        onTriggered: Nav.openAlbumId(root.tracks[0].albumId, root.tracks[0].album)
    }
    PopupMenuItem {
        // Everything known about the song: credits, file, and on an eos server its tags.
        visible: root.picked === 1
        text: "Show details"
        onTriggered: Nav.openSong(root.tracks[0].id, root.tracks[0].title)
    }
}
