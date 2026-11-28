import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Kleulir

// One playlist: its songs, with rename and delete.
Item {
    id: root
    property var playlist          // starts as the summary from the list
    property bool renaming: false

    readonly property var tracks: playlist && playlist.tracks ? playlist.tracks : []
    readonly property int totalSeconds: tracks.reduce((s, t) => s + t.duration, 0)

    function request() {
        if (playlist)
            Library.loadPlaylist(playlist.id)
    }
    Component.onCompleted: request()

    Connections {
        target: Library
        function onPlaylistLoaded(id, loaded) {
            if (root.playlist && id === root.playlist.id)
                root.playlist = loaded
        }
        function onPlaylistChanged(id) {
            if (root.playlist && id === root.playlist.id)
                root.request()
        }
        function onPlaylistDeleted(id) {
            if (root.playlist && id === root.playlist.id)
                Nav.openPage("playlists")
        }
    }

    TrackList {
        id: list
        anchors.fill: parent
        anchors.leftMargin: 24
        anchors.rightMargin: 12
        tracks: root.tracks
        showAlbum: true
        playlistId: root.playlist ? root.playlist.id : ""

        header: Item {
            width: list.width - list.sideMargin
            height: headerLayout.implicitHeight + 36

            ColumnLayout {
                id: headerLayout
                y: 24
                width: parent.width
                spacing: 6

                Text {
                    text: "PLAYLIST"
                    color: Theme.textDim
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0.6
                }
                CopyText {
                    visible: !root.renaming
                    Layout.fillWidth: true
                    text: root.playlist ? root.playlist.name : ""
                    font.pixelSize: 32
                    font.weight: Font.Bold
                }
                TextField {
                    id: nameField
                    visible: root.renaming
                    Layout.preferredWidth: 420
                    implicitHeight: 40
                    leftPadding: 10
                    color: Theme.text
                    font.pixelSize: 20
                    selectByMouse: true
                    onAccepted: {
                        Library.renamePlaylist(root.playlist.id, text)
                        root.renaming = false
                    }
                    Keys.onEscapePressed: root.renaming = false
                    background: Rectangle {
                        color: Theme.raised
                        border.color: Theme.accent
                    }
                }
                Text {
                    text: root.playlist && root.playlist.tracks
                          ? root.tracks.length + " tracks · " + Theme.time(root.totalSeconds)
                          : "Loading…"
                    color: Theme.textDim
                    font.pixelSize: Theme.fontBody
                }

                RowLayout {
                    spacing: Theme.gap
                    Layout.topMargin: 10

                    AbstractButton {
                        id: playButton
                        implicitHeight: 36
                        implicitWidth: playRow.implicitWidth + 32
                        hoverEnabled: true
                        enabled: root.tracks.length > 0
                        Accessible.name: "Play"
                        onClicked: Player.playTracks(root.tracks, null, 0)
                        background: Rectangle {
                            color: !playButton.enabled ? Theme.raised
                                   : playButton.down ? Theme.textDim
                                   : playButton.hovered ? "#ffffff" : Theme.text
                        }
                        contentItem: Item {
                            Row {
                                id: playRow
                                anchors.centerIn: parent
                                spacing: 6
                                Icon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: "play"
                                    size: 18
                                    color: playButton.enabled ? Theme.bg : Theme.textFaint
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Play"
                                    color: playButton.enabled ? Theme.bg : Theme.textFaint
                                    font.pixelSize: Theme.fontBody
                                    font.weight: Font.Bold
                                }
                            }
                        }
                    }
                    IconButton {
                        text: "Add to queue"
                        enabled: root.tracks.length > 0
                        onClicked: Player.enqueueMany(root.tracks, null)
                    }
                    IconButton {
                        text: root.renaming ? "Cancel" : "Rename"
                        onClicked: {
                            root.renaming = !root.renaming
                            if (root.renaming) {
                                nameField.text = root.playlist.name
                                nameField.forceActiveFocus()
                                nameField.selectAll()
                            }
                        }
                    }
                    // Two clicks, so a playlist is not lost to a slip.
                    IconButton {
                        id: deleteButton
                        property bool armed: false
                        text: armed ? "Click again to delete" : "Delete"
                        onClicked: {
                            if (armed)
                                Library.deletePlaylist(root.playlist.id)
                            else
                                armed = true
                        }
                        onHoveredChanged: if (!hovered) armed = false
                    }
                }
            }
        }
    }
}
