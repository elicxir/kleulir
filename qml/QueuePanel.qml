import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Kleulir

Rectangle {
    id: root
    color: Theme.panel

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.gap
        anchors.topMargin: 14
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.gap
            spacing: Theme.gap

            Text {
                text: "Queue"
                color: Theme.text
                font.pixelSize: 16
                font.weight: Font.Bold
            }
            Text {
                text: Player.queue.count + " tracks"
                color: Theme.textFaint
                font.pixelSize: Theme.fontSmall
                Layout.alignment: Qt.AlignBaseline
            }
            Item { Layout.fillWidth: true }
            IconButton {
                text: "Clear"
                labelSize: Theme.fontSmall
                implicitHeight: 28
                visible: Player.queue.count > 0
                onClicked: Player.clear()
            }
        }

        Item {
            visible: Player.queue.count === 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            Column {
                anchors.centerIn: parent
                spacing: 8
                Icon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: "queue"
                    size: 32
                    color: Theme.hover
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Queue is empty"
                    color: Theme.textFaint
                    font.pixelSize: Theme.fontBody
                }
            }
        }

        ListView {
            id: list
            visible: Player.queue.count > 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 0
            model: Player.queue
            ScrollBar.vertical: ScrollBar {}

            delegate: Rectangle {
                id: row
                required property int index
                required property string title
                required property string artist
                required property string album
                required property string coverArt
                required property real duration
                readonly property bool isCurrent: index === Player.currentIndex
                readonly property bool played: index < Player.currentIndex
                readonly property bool hot: rowArea.containsMouse || upButton.hovered
                                            || downButton.hovered || removeButton.hovered

                width: list.width
                height: 52
                color: row.isCurrent ? Theme.raised : row.hot ? Qt.rgba(1, 1, 1, 0.05) : "transparent"

                MouseArea {
                    id: rowArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onDoubleClicked: Player.jump(row.index)
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.gap
                    anchors.rightMargin: 4
                    spacing: 10

                    Cover {
                        Layout.preferredWidth: 36
                        Layout.preferredHeight: 36
                        title: row.album
                        art: row.coverArt
                        opacity: row.played ? 0.45 : 1
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        opacity: row.played ? 0.5 : 1
                        Text {
                            Layout.fillWidth: true
                            text: row.title
                            color: row.isCurrent ? Theme.accent : Theme.text
                            font.pixelSize: Theme.fontBody
                            font.weight: row.isCurrent ? Font.DemiBold : Font.Normal
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            text: row.artist
                            color: Theme.textDim
                            font.pixelSize: Theme.fontSmall
                            elide: Text.ElideRight
                        }
                    }
                    Text {
                        visible: !row.hot
                        Layout.rightMargin: 8
                        text: Theme.time(row.duration)
                        color: Theme.textFaint
                        font.pixelSize: Theme.fontSmall
                        font.features: { "tnum": 1 }
                    }
                    // Reordering by buttons for now; drag comes with the real queue model.
                    Row {
                        visible: row.hot
                        IconButton {
                            id: upButton
                            implicitWidth: 28
                            glyph: "up"
                            tip: "Move up"
                            enabled: row.index > 0
                            onClicked: Player.move(row.index, row.index - 1)
                        }
                        IconButton {
                            id: downButton
                            implicitWidth: 28
                            glyph: "down"
                            tip: "Move down"
                            enabled: row.index < Player.queue.count - 1
                            onClicked: Player.move(row.index, row.index + 1)
                        }
                        IconButton {
                            id: removeButton
                            implicitWidth: 28
                            glyph: "close"
                            glyphSize: 16
                            tip: "Remove from queue"
                            onClicked: Player.removeAt(row.index)
                        }
                    }
                }
            }
        }
    }
}
