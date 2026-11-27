import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Kleulir

// Album detail. Tracks are grouped by work (作品), as /ext/albums/{id}/titles
// returns them; tracks without a work fall under an untitled group.
Item {
    id: root
    property var album
    signal back()

    function reload() {
        trackModel.clear()
        if (album)
            album.tracks.forEach(t => trackModel.append({
                trackId: t.id, title: t.title, artist: t.artist,
                duration: t.duration, work: t.work, estimated: t.estimated
            }))
    }
    onAlbumChanged: reload()
    Component.onCompleted: reload()

    readonly property int totalSeconds: album ? album.tracks.reduce((s, t) => s + t.duration, 0) : 0

    ListView {
        id: list
        anchors.fill: parent
        anchors.margins: Theme.pad
        clip: true
        // A ListModel rather than the JS array: ListView sections need named roles.
        model: ListModel { id: trackModel }

        ScrollBar.vertical: ScrollBar {}

        header: Column {
            width: list.width
            spacing: Theme.pad
            bottomPadding: Theme.pad

            IconButton {
                text: "← アルバム"
                glyphSize: Theme.fontBody
                onClicked: root.back()
            }

            RowLayout {
                width: parent.width
                spacing: Theme.pad

                Cover {
                    Layout.preferredWidth: 160
                    Layout.preferredHeight: 160
                    title: root.album ? root.album.title : ""
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignBottom
                    spacing: 4

                    Text {
                        visible: root.album && root.album.kind === "virtual"
                        text: "仮想アルバム"
                        color: Theme.textFaint
                        font.pixelSize: Theme.fontSmall
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.album ? root.album.title : ""
                        color: Theme.text
                        font.pixelSize: 26
                        font.weight: Font.DemiBold
                        wrapMode: Text.Wrap
                    }
                    Text {
                        text: root.album
                              ? root.album.artist + " · " + root.album.year + " · "
                                + root.album.tracks.length + " 曲 · " + Theme.time(root.totalSeconds)
                              : ""
                        color: Theme.textDim
                        font.pixelSize: Theme.fontBody
                    }
                    RowLayout {
                        spacing: Theme.gap
                        Layout.topMargin: Theme.gap

                        Button {
                            id: playButton
                            text: "再生"
                            implicitHeight: 32
                            implicitWidth: 88
                            onClicked: Player.playAlbum(root.album, 0)
                            background: Rectangle {
                                radius: Theme.radius
                                color: playButton.down ? Theme.accentDim : Theme.accent
                            }
                            contentItem: Text {
                                text: playButton.text
                                color: Theme.bg
                                font.pixelSize: Theme.fontBody
                                font.weight: Font.DemiBold
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                        IconButton {
                            text: "キューに追加"
                            glyphSize: Theme.fontBody
                            onClicked: root.album.tracks.forEach(t => Player.enqueue(t, root.album))
                        }
                    }
                }
            }
        }

        section.property: "work"
        section.delegate: Item {
            required property string section
            width: list.width
            height: 36
            Text {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 6
                text: parent.section.length > 0 ? parent.section : "作品なし"
                color: Theme.accent
                font.pixelSize: Theme.fontSmall
                font.weight: Font.DemiBold
            }
        }

        delegate: Rectangle {
            id: row
            required property int index
            required property string title
            required property string artist
            required property real duration
            required property bool estimated
            required property string trackId
            readonly property var track: root.album ? root.album.tracks[index] : null
            readonly property bool isCurrent: Player.current !== null && Player.current.trackId === trackId

            width: list.width
            height: 36
            radius: Theme.radius
            color: rowArea.containsMouse ? Theme.hover : "transparent"

            MouseArea {
                id: rowArea
                anchors.fill: parent
                hoverEnabled: true
                onDoubleClicked: Player.playAlbum(root.album, row.index)
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.gap
                anchors.rightMargin: Theme.gap
                spacing: Theme.gap

                Text {
                    Layout.preferredWidth: 28
                    text: row.isCurrent ? "▶" : row.index + 1
                    color: row.isCurrent ? Theme.accent : Theme.textFaint
                    font.pixelSize: Theme.fontBody
                    horizontalAlignment: Text.AlignRight
                }
                Text {
                    Layout.fillWidth: true
                    text: row.title
                    color: row.isCurrent ? Theme.accent : Theme.text
                    font.pixelSize: Theme.fontBody
                    elide: Text.ElideRight
                }
                Text {
                    visible: row.estimated
                    text: "推定"
                    color: Theme.estimated
                    font.pixelSize: 11
                }
                Text {
                    Layout.preferredWidth: 160
                    text: row.artist
                    color: Theme.textDim
                    font.pixelSize: Theme.fontBody
                    elide: Text.ElideRight
                }
                IconButton {
                    opacity: rowArea.containsMouse || hovered ? 1 : 0
                    text: "次に再生"
                    glyphSize: Theme.fontSmall
                    onClicked: Player.playNext(row.track, root.album)
                }
                IconButton {
                    opacity: rowArea.containsMouse || hovered ? 1 : 0
                    text: "＋"
                    tip: "キューの末尾に追加"
                    onClicked: Player.enqueue(row.track, root.album)
                }
                Text {
                    Layout.preferredWidth: 44
                    text: Theme.time(row.duration)
                    color: Theme.textDim
                    font.pixelSize: Theme.fontBody
                    horizontalAlignment: Text.AlignRight
                }
            }
        }
    }
}
