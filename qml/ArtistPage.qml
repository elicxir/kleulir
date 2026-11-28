import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Kleulir

// One artist: their albums.
Item {
    id: root
    property var artist            // { id, name, albumCount } from the list
    property var albums: []
    property bool loaded: false

    function request() {
        if (artist)
            Library.loadArtist(artist.id)
    }
    onArtistChanged: request()
    Component.onCompleted: request()

    Connections {
        target: Library
        function onArtistLoaded(id, data) {
            if (!root.artist || id !== root.artist.id)
                return
            root.albums = data.albums || []
            root.loaded = true
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: 20
        anchors.leftMargin: 24
        anchors.rightMargin: 8
        spacing: 16

        ColumnLayout {
            spacing: 4
            Text {
                text: "ARTIST"
                color: Theme.textDim
                font.pixelSize: 11
                font.weight: Font.DemiBold
                font.letterSpacing: 0.6
            }
            CopyText {
                Layout.fillWidth: true
                text: root.artist ? root.artist.name : ""
                font.pixelSize: 32
                font.weight: Font.Bold
            }
            Text {
                text: root.loaded ? root.albums.length + " albums" : "Loading…"
                color: Theme.textDim
                font.pixelSize: Theme.fontBody
            }
        }

        AlbumGrid {
            Layout.fillWidth: true
            Layout.fillHeight: true
            albums: root.albums
        }
    }
}
