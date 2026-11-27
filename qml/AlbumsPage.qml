import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Kleulir

Item {
    id: root
    // The list has no tracks; fetch the album, then act on it.
    // mode: "play" | "next" | "queue"
    property var pending: null
    function act(album, mode) {
        pending = { id: album.id, mode: mode }
        Library.loadAlbum(album.id)
    }
    function playAlbum(album) { act(album, "play") }
    Connections {
        target: Library
        function onAlbumLoaded(id, album) {
            if (!root.pending || id !== root.pending.id)
                return
            const mode = root.pending.mode
            root.pending = null
            if (mode === "play")
                Player.playAlbum(album, 0)
            else if (mode === "next")
                Player.playNextMany(album.tracks, album)
            else
                Player.enqueueMany(album.tracks, album)
        }
    }

    PopupMenu {
        id: albumMenu
        property var album: null
        readonly property bool starred: {
            Library.starRevision
            return album ? Library.isStarred(album.id) : false
        }
        PopupMenuItem {
            text: "Play"
            onTriggered: root.act(albumMenu.album, "play")
        }
        PopupMenuItem {
            text: "Play next"
            onTriggered: root.act(albumMenu.album, "next")
        }
        PopupMenuItem {
            text: "Add to queue"
            onTriggered: root.act(albumMenu.album, "queue")
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

    // "all" | "physical" | "virtual" — the same filter /ext/albums takes.
    property string kind: "all"
    readonly property var shown: Library.albums.filter(a => kind === "all" || a.kind === kind)

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: 20
        anchors.leftMargin: 24
        anchors.rightMargin: 8
        spacing: 16

        RowLayout {
            Layout.fillWidth: true
            Layout.rightMargin: 16
            spacing: 10

            Text {
                text: "Albums"
                color: Theme.text
                font.pixelSize: Theme.fontTitle
                font.weight: Font.Bold
            }
            Text {
                text: Library.albums.length === 0 && Library.loading ? "Loading…"
                      : Library.error.length > 0 ? Library.error : root.shown.length + " albums"
                color: Theme.textFaint
                font.pixelSize: Theme.fontBody
                Layout.alignment: Qt.AlignBaseline
            }
            Item { Layout.fillWidth: true }

            // Segmented filter
            Rectangle {
                visible: Session.eosFeatures
                implicitWidth: segments.implicitWidth + 6
                implicitHeight: 32
                color: Theme.raised
                border.color: Theme.line

                Row {
                    id: segments
                    anchors.centerIn: parent
                    Repeater {
                        model: [
                            { key: "all", label: "All" },
                            { key: "physical", label: "Physical" },
                            { key: "virtual", label: "Virtual" }
                        ]
                        delegate: AbstractButton {
                            id: segment
                            required property var modelData
                            readonly property bool selected: root.kind === modelData.key
                            implicitWidth: segmentLabel.implicitWidth + 28
                            implicitHeight: 26
                            hoverEnabled: true
                            onClicked: root.kind = modelData.key
                            background: Rectangle {
                                color: segment.selected ? Theme.hover : "transparent"
                            }
                            contentItem: Text {
                                id: segmentLabel
                                text: segment.modelData.label
                                color: segment.selected ? Theme.text
                                       : segment.hovered ? Theme.text : Theme.textDim
                                font.pixelSize: Theme.fontSmall
                                font.weight: segment.selected ? Font.DemiBold : Font.Normal
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }
                }
            }
        }

        GridView {
            id: grid
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: root.shown
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
                            id: cover
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
                            id: playDot
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
                            root.playAlbum(cell.modelData)
                        else
                            Nav.openAlbum(cell.modelData)
                    }
                }
            }
        }
    }
}
