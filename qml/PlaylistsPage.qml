import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Kleulir

Item {
    id: root

    Component.onCompleted: Library.refreshPlaylists()

    function create() {
        const name = nameField.text.trim()
        if (name.length === 0)
            return
        Library.createPlaylist(name, [])
        nameField.text = ""
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: 20
        anchors.leftMargin: 24
        anchors.rightMargin: 24
        spacing: 16

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Text {
                text: "Playlists"
                color: Theme.text
                font.pixelSize: Theme.fontTitle
                font.weight: Font.Bold
            }
            Text {
                text: Library.playlists.length + " playlists"
                color: Theme.textFaint
                font.pixelSize: Theme.fontBody
                Layout.alignment: Qt.AlignBaseline
            }
            Item { Layout.fillWidth: true }

            TextField {
                id: nameField
                implicitWidth: 220
                implicitHeight: 32
                leftPadding: 10
                placeholderText: "New playlist name"
                placeholderTextColor: Theme.textFaint
                color: Theme.text
                font.pixelSize: Theme.fontBody
                selectByMouse: true
                onAccepted: root.create()
                background: Rectangle {
                    color: Theme.raised
                    border.color: nameField.activeFocus ? Theme.accent : Theme.line
                }
            }
            IconButton {
                text: "Create"
                enabled: nameField.text.trim().length > 0
                onClicked: root.create()
            }
        }

        Text {
            visible: Library.playlists.length === 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            text: "No playlists yet. Create one here, or right-click a song and choose Add to playlist."
            color: Theme.textFaint
            font.pixelSize: 14
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.Wrap
        }

        ListView {
            id: list
            visible: Library.playlists.length > 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: Library.playlists
            ScrollBar.vertical: ScrollBar {}

            delegate: Rectangle {
                id: row
                required property var modelData
                width: list.width - 12
                height: 52
                color: area.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.gap
                    anchors.rightMargin: 12
                    spacing: 12

                    Rectangle {
                        Layout.preferredWidth: 36
                        Layout.preferredHeight: 36
                        color: Qt.hsla(Theme.coverHue(row.modelData.name), 0.30, 0.34, 1)
                        Icon {
                            anchors.centerIn: parent
                            name: "queue"
                            size: 18
                            color: Qt.rgba(1, 1, 1, 0.8)
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: row.modelData.name
                        color: Theme.text
                        font.pixelSize: 14
                        elide: Text.ElideRight
                    }
                    Text {
                        text: row.modelData.songCount + " tracks"
                        color: Theme.textDim
                        font.pixelSize: Theme.fontBody
                    }
                    Text {
                        Layout.preferredWidth: 56
                        text: Theme.time(row.modelData.duration)
                        color: Theme.textFaint
                        font.pixelSize: Theme.fontBody
                        font.features: { "tnum": 1 }
                        horizontalAlignment: Text.AlignRight
                    }
                }
                MouseArea {
                    id: area
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Nav.go({ page: "playlist", playlist: row.modelData })
                }
            }
        }
    }
}
