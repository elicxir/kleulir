import QtQuick
import QtQuick.Controls.Basic
import Kleulir

// Albums as a grid of covers: click opens, the round button on hover plays, right
// click opens the menu. Used by the Albums page and by an artist's page.
GridView {
    id: grid
    property var albums: []

    // The list has no tracks; fetch the album, then act on it.
    // mode: "play" | "next" | "queue"
    property var pending: null
    function act(album, mode) {
        pending = { id: album.id, mode: mode }
        Library.loadAlbum(album.id)
    }
    property Connections loads: Connections {
        target: Library
        function onAlbumLoaded(id, album) {
            if (!grid.pending || id !== grid.pending.id)
                return
            const mode = grid.pending.mode
            grid.pending = null
            if (mode === "play")
                Player.playAlbum(album, 0)
            else if (mode === "next")
                Player.playNextMany(album.tracks, album)
            else
                Player.enqueueMany(album.tracks, album)
        }
    }

    property PopupMenu menu: PopupMenu {
        id: albumMenu
        property var album: null
        readonly property bool starred: {
            Library.starRevision
            return album ? Library.isStarred(album.id) : false
        }
        PopupMenuItem {
            text: "Play"
            onTriggered: grid.act(albumMenu.album, "play")
        }
        PopupMenuItem {
            text: "Play next"
            onTriggered: grid.act(albumMenu.album, "next")
        }
        PopupMenuItem {
            text: "Add to queue"
            onTriggered: grid.act(albumMenu.album, "queue")
        }
        MenuDivider {}
        PopupMenuItem {
            text: albumMenu.starred ? "Remove from Starred" : "Add to Starred"
            onTriggered: Library.setStarred([albumMenu.album.id], !albumMenu.starred)
        }
        PopupMenuItem {
            text: "Open album"
            onTriggered: Nav.openAlbum(albumMenu.album)
        }
    }

    clip: true
    model: albums
    // Build a few rows beyond the view, so covers are ready before they scroll in.
    cacheBuffer: 900

    readonly property int columns: Math.max(2, Math.floor(width / 200))
    cellWidth: Math.floor((width - 8) / columns)
    cellHeight: cellWidth + 52

    ScrollBar.vertical: ScrollBar {}

    delegate: Item {
        id: cell
        required property var modelData
        width: grid.cellWidth
        height: grid.cellHeight

        readonly property int side: width - 20

        Column {
            width: cell.side
            spacing: 4

            Item {
                width: cell.side
                height: cell.side

                Cover {
                    anchors.fill: parent
                    title: cell.modelData.title
                    art: cell.modelData.coverArt
                    shadow: area.containsMouse
                }

                Rectangle {
                    visible: cell.modelData.kind === "virtual"
                    anchors.left: parent.left
                    anchors.top: parent.top
                    color: Qt.rgba(0, 0, 0, 0.6)
                    width: badge.implicitWidth + 14
                    height: 18
                    Text {
                        id: badge
                        anchors.centerIn: parent
                        text: "Virtual"
                        color: Theme.text
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                    }
                }

                // Play button over the cover, shown on hover.
                Rectangle {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 8
                    width: 40
                    height: 40
                    radius: 20
                    color: Theme.text
                    opacity: area.containsMouse ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 100 } }
                    Icon {
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: 1
                        name: "play"
                        size: 22
                        color: Theme.bg
                    }
                }
            }

            Text {
                width: parent.width
                topPadding: 6
                text: cell.modelData.title
                color: Theme.text
                font.pixelSize: 14
                font.weight: Font.Medium
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                text: cell.modelData.year > 0 ? cell.modelData.artist + " · " + cell.modelData.year : cell.modelData.artist
                color: Theme.textDim
                font.pixelSize: Theme.fontSmall
                elide: Text.ElideRight
            }
        }

        MouseArea {
            id: area
            width: cell.side
            height: cell.height - 8
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton) {
                    albumMenu.album = cell.modelData
                    albumMenu.popup()
                    return
                }
                // The lower-right corner of the cover is the play button.
                const s = cell.side
                const onPlay = mouse.x > s - 52 && mouse.y > s - 52 && mouse.y < s
                if (onPlay)
                    grid.act(cell.modelData, "play")
                else
                    Nav.openAlbum(cell.modelData)
            }
        }
    }
}
