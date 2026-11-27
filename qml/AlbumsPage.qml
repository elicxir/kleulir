import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Kleulir

Item {
    id: root
    signal openAlbum(var album)

    // "all" | "physical" | "virtual" — the same filter /ext/albums takes.
    property string kind: "all"
    readonly property var shown: MockData.albums.filter(a => kind === "all" || a.kind === kind)

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.pad
        spacing: Theme.pad

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.gap

            Text {
                text: "アルバム"
                color: Theme.text
                font.pixelSize: Theme.fontTitle
                font.weight: Font.DemiBold
            }
            Text {
                text: root.shown.length + " 枚"
                color: Theme.textFaint
                font.pixelSize: Theme.fontBody
                Layout.alignment: Qt.AlignBaseline
            }
            Item { Layout.fillWidth: true }

            Repeater {
                model: [
                    { key: "all", label: "すべて" },
                    { key: "physical", label: "物理" },
                    { key: "virtual", label: "仮想" }
                ]
                delegate: IconButton {
                    required property var modelData
                    visible: MockData.eosFeatures
                    text: modelData.label
                    glyphSize: Theme.fontBody
                    active: root.kind === modelData.key
                    onClicked: root.kind = modelData.key
                }
            }
        }

        GridView {
            id: grid
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: root.shown

            readonly property int columns: Math.max(2, Math.floor(width / 190))
            cellWidth: Math.floor(width / columns)
            cellHeight: cellWidth + 56

            ScrollBar.vertical: ScrollBar {}

            delegate: Item {
                id: cell
                required property var modelData
                width: grid.cellWidth
                height: grid.cellHeight

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 4
                    radius: Theme.radius
                    color: area.containsMouse ? Theme.hover : "transparent"
                }

                Column {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 6

                    Cover {
                        width: parent.width
                        height: width
                        title: cell.modelData.title

                        Rectangle {
                            visible: cell.modelData.kind === "virtual"
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.margins: 6
                            radius: 3
                            color: Qt.rgba(0, 0, 0, 0.55)
                            width: badge.implicitWidth + 10
                            height: badge.implicitHeight + 4
                            Text {
                                id: badge
                                anchors.centerIn: parent
                                text: "仮想"
                                color: Theme.text
                                font.pixelSize: 11
                            }
                        }
                    }
                    Text {
                        width: parent.width
                        text: cell.modelData.title
                        color: Theme.text
                        font.pixelSize: Theme.fontBody
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: cell.modelData.artist + " · " + cell.modelData.year
                        color: Theme.textDim
                        font.pixelSize: Theme.fontSmall
                        elide: Text.ElideRight
                    }
                }

                MouseArea {
                    id: area
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openAlbum(cell.modelData)
                    onDoubleClicked: Player.playAlbum(cell.modelData, 0)
                }
            }
        }
    }
}
