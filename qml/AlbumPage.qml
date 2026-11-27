import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Kleulir

// Album detail. Tracks are grouped by work (作品), as /ext/albums/{id}/titles
// returns them; tracks without a work fall under an untitled group.
Item {
    id: root
    // Starts as the summary from the list (no tracks) and is replaced by the
    // full album once it has loaded.
    property var album
    property string loadError: ""
    signal back()

    readonly property var tracks: album && album.tracks ? album.tracks : []
    property string requested: ""
    function request() {
        if (album && !album.tracks && requested !== album.id) {
            requested = album.id
            Library.loadAlbum(album.id)
        }
    }
    Connections {
        target: Library
        function onAlbumLoaded(id, loaded) {
            if (root.album && id === root.album.id)
                root.album = loaded
        }
        function onAlbumFailed(id, message) {
            if (root.album && id === root.album.id)
                root.loadError = message
        }
    }

    function reload() {
        trackModel.clear()
        request()
        // Read album.tracks directly: the `tracks` binding may not have updated yet
        // when this runs from onAlbumChanged.
        const list = album && album.tracks ? album.tracks : []
        list.forEach(t => trackModel.append({
                trackId: t.id, title: t.title, artist: t.artist,
                duration: t.duration, work: t.work, estimated: t.estimated
        }))
    }
    onAlbumChanged: reload()
    Component.onCompleted: reload()

    readonly property int totalSeconds: tracks.reduce((s, t) => s + t.duration, 0)
    readonly property real hue: Theme.coverHue(album ? album.title : "")

    // Wash of the cover's colour behind the header, fading into the panel.
    Rectangle {
        width: parent.width
        height: 300
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.hsla(root.hue, 0.30, 0.30, 0.55) }
            GradientStop { position: 1; color: Qt.hsla(root.hue, 0.30, 0.30, 0) }
        }
    }

    ListView {
        id: list
        anchors.fill: parent
        anchors.leftMargin: 24
        anchors.rightMargin: 12
        clip: true
        // A ListModel rather than the JS array: ListView sections need named roles.
        model: ListModel { id: trackModel }
        bottomMargin: Theme.pad

        ScrollBar.vertical: ScrollBar {}

        header: Column {
            width: list.width - 12
            topPadding: 14
            bottomPadding: 12
            spacing: 14

            IconButton {
                glyph: "back"
                tip: "Back to albums"
                onClicked: root.back()
            }

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
                            Accessible.name: "Play"
                            enabled: root.tracks.length > 0
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
                            onClicked: root.tracks.forEach(t => Player.enqueue(t, root.album))
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
                    }
                }
            }
        }

        section.property: "work"
        section.delegate: Item {
            required property string section
            width: list.width - 12
            height: 44
            Text {
                anchors.left: parent.left
                anchors.leftMargin: Theme.gap
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 8
                text: parent.section.length > 0 ? parent.section : "No work"
                color: parent.section.length > 0 ? Theme.text : Theme.textFaint
                font.pixelSize: Theme.fontSmall
                font.weight: Font.DemiBold
                font.letterSpacing: 0.4
            }
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: Qt.rgba(1, 1, 1, 0.06)
            }
        }

        delegate: Rectangle {
            id: row
            required property int index
            required property string trackId
            required property string title
            required property string artist
            required property real duration
            required property bool estimated
            readonly property var track: index < root.tracks.length ? root.tracks[index] : null
            readonly property bool isCurrent: Player.current !== null && Player.current.trackId === trackId
            readonly property bool hot: rowArea.containsMouse || nextButton.hovered || addButton.hovered

            width: list.width - 12
            height: 38
            color: row.hot ? Qt.rgba(1, 1, 1, 0.06) : row.isCurrent ? Qt.rgba(1, 1, 1, 0.03) : "transparent"

            MouseArea {
                id: rowArea
                anchors.fill: parent
                hoverEnabled: true
                onDoubleClicked: Player.playAlbum(root.album, row.index)
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.gap
                anchors.rightMargin: 12
                spacing: 10

                Item {
                    Layout.preferredWidth: 24
                    Layout.fillHeight: true
                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !row.isCurrent
                        text: row.index + 1
                        color: Theme.textFaint
                        font.pixelSize: Theme.fontBody
                        font.features: { "tnum": 1 }
                    }
                    Icon {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        visible: row.isCurrent
                        name: Player.playing ? "play" : "pause"
                        size: 14
                        color: Theme.accent
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: row.title
                    color: row.isCurrent ? Theme.accent : Theme.text
                    font.pixelSize: 14
                    elide: Text.ElideRight
                }
                Rectangle {
                    visible: row.estimated
                    implicitWidth: estimatedLabel.implicitWidth + 12
                    implicitHeight: 18
                    color: "transparent"
                    border.color: Qt.rgba(Theme.estimated.r, Theme.estimated.g, Theme.estimated.b, 0.6)
                    Text {
                        id: estimatedLabel
                        anchors.centerIn: parent
                        text: "EST"
                        color: Theme.estimated
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                    }
                }
                Text {
                    Layout.preferredWidth: 150
                    text: row.artist
                    color: Theme.textDim
                    font.pixelSize: Theme.fontBody
                    elide: Text.ElideRight
                }
                IconButton {
                    id: nextButton
                    opacity: row.hot ? 1 : 0
                    glyph: "playNext"
                    tip: "Play next"
                    onClicked: Player.playNext(row.track, root.album)
                }
                IconButton {
                    id: addButton
                    opacity: row.hot ? 1 : 0
                    glyph: "add"
                    tip: "Add to queue"
                    onClicked: Player.enqueue(row.track, root.album)
                }
                Text {
                    Layout.preferredWidth: 40
                    text: Theme.time(row.duration)
                    color: Theme.textDim
                    font.pixelSize: Theme.fontBody
                    font.features: { "tnum": 1 }
                    horizontalAlignment: Text.AlignRight
                }
            }
        }
    }
}
