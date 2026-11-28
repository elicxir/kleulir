import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Kleulir

// Everything the user has starred: albums in a row, then songs.
Item {
    id: root

    property var albums: []
    property var songs: []
    property bool loaded: false

    Component.onCompleted: Library.loadStarred()

    Connections {
        target: Library
        function onStarredLoaded(result) {
            root.albums = result.albums || []
            root.songs = result.songs || []
            root.loaded = true
        }
        // A star changed somewhere: refresh, but not on every click of a burst.
        function onStarsChanged() { reload.restart() }
    }
    Timer {
        id: reload
        interval: 600
        onTriggered: Library.loadStarred()
    }

    readonly property bool empty: albums.length === 0 && songs.length === 0

    Text {
        anchors.centerIn: parent
        visible: root.empty
        text: root.loaded ? "Nothing starred yet. Use the heart on a song or an album." : "Loading…"
        color: Theme.textFaint
        font.pixelSize: 14
    }

    TrackList {
        id: list
        anchors.fill: parent
        anchors.leftMargin: 24
        anchors.rightMargin: 12
        tracks: root.songs
        showAlbum: true

        // The heading stays put; the songs scroll beneath it.
        headerPositioning: ListView.OverlayHeader

        header: Rectangle {
            z: 3  // above the rows and the section headings
            color: Theme.panel
            width: list.width - list.sideMargin
            height: headerLayout.implicitHeight + 28

            ColumnLayout {
                id: headerLayout
                y: 20
                width: parent.width
                spacing: 14

                RowLayout {
                    spacing: 10
                    Text {
                        text: "Starred"
                        color: Theme.text
                        font.pixelSize: Theme.fontTitle
                        font.weight: Font.Bold
                    }
                    Text {
                        visible: !root.empty
                        text: root.songs.length + " songs · " + root.albums.length + " albums"
                        color: Theme.textFaint
                        font.pixelSize: Theme.fontBody
                        Layout.alignment: Qt.AlignBaseline
                    }
                }

                Text {
                    visible: root.albums.length > 0
                    text: "Albums"
                    color: Theme.text
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                }
                AlbumRow {
                    visible: root.albums.length > 0
                    Layout.fillWidth: true
                    Layout.preferredHeight: 196
                    albums: root.albums
                }

                RowLayout {
                    visible: root.songs.length > 0
                    spacing: 12
                    Text {
                        text: "Songs"
                        color: Theme.text
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                    }
                    IconButton {
                        text: "Play all"
                        labelSize: Theme.fontSmall
                        implicitHeight: 26
                        onClicked: Player.playTracks(root.songs, null, 0)
                    }
                }
            }
        }
    }
}
