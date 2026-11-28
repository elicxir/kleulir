import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Kleulir

// Album detail, in the album's track order. A run of tracks from one work (作品) gets
// a heading; tracks without a work fall under an untitled one.
Item {
    id: root
    // Starts as the summary from the list (no tracks) and is replaced by the
    // full album once it has loaded.
    property var album
    property string loadError: ""

    readonly property var tracks: album && album.tracks ? album.tracks : []
    readonly property int totalSeconds: tracks.reduce((s, t) => s + t.duration, 0)
    readonly property real hue: Theme.coverHue(album ? album.title : "")
    readonly property bool starred: {
        Library.starRevision
        return album ? Library.isStarred(album.id) : false
    }

    property string requested: ""
    function request() {
        if (album && !album.tracks && requested !== album.id) {
            requested = album.id
            Library.loadAlbum(album.id)
        }
    }
    onAlbumChanged: request()
    Component.onCompleted: request()

    Connections {
        target: Library
        function onAlbumLoaded(id, loaded) {
            if (root.album && id === root.album.id && !root.album.tracks)
                root.album = loaded
        }
        function onAlbumFailed(id, message) {
            if (root.album && id === root.album.id)
                root.loadError = message
        }
    }

    // Wash of the cover's colour behind the header, fading into the panel.
    Rectangle {
        width: parent.width
        height: 300
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.hsla(root.hue, 0.30, 0.30, 0.55) }
            GradientStop { position: 1; color: Qt.hsla(root.hue, 0.30, 0.30, 0) }
        }
    }

    TrackList {
        id: list
        anchors.fill: parent
        anchors.leftMargin: 24
        anchors.rightMargin: 12
        tracks: root.tracks
        album: root.album
        groupByWork: true

        header: Column {
            width: list.width - list.sideMargin
            topPadding: 28
            bottomPadding: 12

            RowLayout {
                width: parent.width
                spacing: 24

                Cover {
                    Layout.preferredWidth: 184
                    Layout.preferredHeight: 184
                    title: root.album ? root.album.title : ""
                    art: root.album ? root.album.coverArt : ""
                    shadow: true
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignBottom
                    spacing: 6

                    Text {
                        text: root.album && root.album.kind === "virtual" ? "VIRTUAL ALBUM" : "ALBUM"
                        color: Theme.textDim
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        font.letterSpacing: 0.6
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.album ? root.album.title : ""
                        color: Theme.text
                        font.pixelSize: 32
                        font.weight: Font.Bold
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                    Text {
                        text: root.album
                              ? [root.album.artist, root.album.year > 0 ? root.album.year : "",
                                 root.loadError.length > 0 ? root.loadError
                                 : root.album.tracks ? root.tracks.length + " tracks" : "Loading…",
                                 root.album.tracks ? Theme.time(root.totalSeconds) : ""]
                                .filter(part => String(part).length > 0).join(" · ")
                              : ""
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
                            onClicked: Player.playAlbum(root.album, 0)
                            background: Rectangle {
                                color: playButton.down ? Theme.textDim
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
                                        color: Theme.bg
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "Play"
                                        color: Theme.bg
                                        font.pixelSize: Theme.fontBody
                                        font.weight: Font.Bold
                                    }
                                }
                            }
                        }
                        AbstractButton {
                            id: enqueueButton
                            implicitHeight: 36
                            implicitWidth: enqueueLabel.implicitWidth + 32
                            hoverEnabled: true
                            enabled: root.tracks.length > 0
                            onClicked: Player.enqueueMany(root.tracks, root.album)
                            background: Rectangle {
                                color: enqueueButton.hovered ? Qt.rgba(1, 1, 1, 0.10) : "transparent"
                                border.color: Qt.rgba(1, 1, 1, 0.28)
                            }
                            contentItem: Text {
                                id: enqueueLabel
                                text: "Add to queue"
                                color: Theme.text
                                font.pixelSize: Theme.fontBody
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                        IconButton {
                            implicitWidth: 36
                            implicitHeight: 36
                            glyph: root.starred ? "heart" : "heartOutline"
                            glyphSize: 20
                            active: root.starred
                            tip: root.starred ? "Remove from Starred" : "Add to Starred"
                            onClicked: Library.setStarred([root.album.id], !root.starred)
                        }
                    }
                }
            }
        }
    }
}
