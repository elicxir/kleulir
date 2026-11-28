import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Kleulir

// One work: the albums it appears on, then every song of it.
Item {
    id: root
    property var work              // { id, name } from the list
    property var albums: []
    property var songs: []
    property string detail: ""
    property bool loaded: false

    function request() {
        if (work)
            Library.loadWork(work.id)
    }
    onWorkChanged: request()
    Component.onCompleted: request()

    Connections {
        target: Library
        function onWorkLoaded(id, data) {
            if (!root.work || id !== root.work.id)
                return
            root.albums = data.albums || []
            root.songs = data.songs || []
            root.detail = [data.kind || "", data.year > 0 ? data.year : ""].filter(x => x !== "").join(" · ")
            root.loaded = true
        }
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

                ColumnLayout {
                    spacing: 4
                    Text {
                        text: "WORK"
                        color: Theme.textDim
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        font.letterSpacing: 0.6
                    }
                    CopyText {
                        Layout.fillWidth: true
                        text: root.work ? root.work.name : ""
                        font.pixelSize: 32
                        font.weight: Font.Bold
                    }
                    Text {
                        text: !root.loaded ? "Loading…"
                              : [root.detail, root.songs.length + " songs", root.albums.length + " albums"]
                                    .filter(x => x !== "").join(" · ")
                        color: Theme.textDim
                        font.pixelSize: Theme.fontBody
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
