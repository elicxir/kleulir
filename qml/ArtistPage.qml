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
    // Their picture: known at once when opened from the list, else once loaded.
    property string art: artist && artist.coverArt ? artist.coverArt : ""

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
            if (data.coverArt)
                root.art = data.coverArt
            root.loaded = true
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: 20
        anchors.leftMargin: 24
        anchors.rightMargin: 8
        spacing: 16

        RowLayout {
            Layout.fillWidth: true
            spacing: 20

            Image {
                visible: root.art.length > 0
                Layout.preferredWidth: 120
                Layout.preferredHeight: 120
                source: visible ? "image://cover/" + root.art : ""
                sourceSize: Qt.size(320, 320)
                fillMode: Image.PreserveAspectCrop
                verticalAlignment: Image.AlignTop
                asynchronous: true
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                Text {
                    text: "ARTIST"
                    color: Theme.textDim
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0.6
                }
                Text {
                    Layout.fillWidth: true
                    text: root.artist ? root.artist.name : ""
                    color: Theme.text
                    font.pixelSize: 32
                    font.weight: Font.Bold
                    elide: Text.ElideRight
                }
                Text {
                    text: root.loaded ? root.albums.length + " albums" : "Loading…"
                    color: Theme.textDim
                    font.pixelSize: Theme.fontBody
                }
            }
        }

        AlbumGrid {
            Layout.fillWidth: true
            Layout.fillHeight: true
            albums: root.albums
        }
    }
}
