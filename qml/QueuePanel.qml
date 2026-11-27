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
        spacing: Theme.gap

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.gap

            Text {
                text: "キュー"
                color: Theme.text
                font.pixelSize: 15
                font.weight: Font.DemiBold
            }
            Text {
                text: Player.queue.count + " 曲"
                color: Theme.textFaint
                font.pixelSize: Theme.fontSmall
            }
            Item { Layout.fillWidth: true }
            IconButton {
                text: "全消去"
                glyphSize: Theme.fontSmall
                enabled: Player.queue.count > 0
                onClicked: Player.clear()
            }
        }

        Text {
            visible: Player.queue.count === 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            text: "キューは空です"
            color: Theme.textFaint
            font.pixelSize: Theme.fontBody
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }

        ListView {
            id: list
            visible: Player.queue.count > 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: Player.queue
            ScrollBar.vertical: ScrollBar {}

            delegate: Rectangle {
                id: row
                required property int index
                required property string title
                required property string artist
                required property real duration
                readonly property bool isCurrent: index === Player.currentIndex

                width: list.width
                height: 44
                radius: Theme.radius
                color: rowArea.containsMouse ? Theme.hover : row.isCurrent ? Theme.raised : "transparent"

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
                    spacing: 4

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text {
                            Layout.fillWidth: true
                            text: row.title
                            color: row.isCurrent ? Theme.accent : Theme.text
                            font.pixelSize: Theme.fontBody
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            text: row.artist + " · " + Theme.time(row.duration)
                            color: Theme.textDim
                            font.pixelSize: Theme.fontSmall
                            elide: Text.ElideRight
                        }
                    }
                    // Reordering by buttons for now; drag comes with the real queue model.
                    IconButton {
                        visible: rowArea.containsMouse || hovered
                        text: "↑"
                        tip: "上へ"
                        enabled: row.index > 0
                        onClicked: Player.move(row.index, row.index - 1)
                    }
                    IconButton {
                        visible: rowArea.containsMouse || hovered
                        text: "↓"
                        tip: "下へ"
                        enabled: row.index < Player.queue.count - 1
                        onClicked: Player.move(row.index, row.index + 1)
                    }
                    IconButton {
                        visible: rowArea.containsMouse || hovered
                        text: "×"
                        tip: "キューから外す"
                        onClicked: Player.removeAt(row.index)
                    }
                }
            }
        }
    }
}
