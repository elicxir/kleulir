import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Kleulir

// Album artists as a compact multi-column list. The server has no artist pictures,
// so names carry the page rather than a grid of portraits.
Item {
    id: root

    property string filter: ""
    readonly property var shown: {
        const text = filter.trim().toLowerCase()
        return text.length === 0 ? Library.artists
                                 : Library.artists.filter(a => a.name.toLowerCase().indexOf(text) >= 0)
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: 20
        anchors.leftMargin: 24
        anchors.rightMargin: 8
        spacing: 16

        RowLayout {
            Layout.fillWidth: true
            Layout.rightMargin: 16
            spacing: 10

            Text {
                text: "Artists"
                color: Theme.text
                font.pixelSize: Theme.fontTitle
                font.weight: Font.Bold
            }
            Text {
                text: root.shown.length + " artists"
                color: Theme.textFaint
                font.pixelSize: Theme.fontBody
                Layout.alignment: Qt.AlignBaseline
            }
            Item { Layout.fillWidth: true }
            TextField {
                id: filterField
                implicitWidth: 220
                implicitHeight: 32
                leftPadding: 10
                placeholderText: "Filter artists"
                placeholderTextColor: Theme.textFaint
                color: Theme.text
                font.pixelSize: Theme.fontBody
                selectByMouse: true
                onTextEdited: root.filter = text
                background: Rectangle {
                    color: Theme.raised
                    border.color: filterField.activeFocus ? Theme.accent : Theme.line
                }
            }
        }

        GridView {
            id: grid
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: root.shown
            readonly property int columns: Math.max(1, Math.floor(width / 280))
            cellWidth: Math.floor((width - 8) / columns)
            cellHeight: 48
            ScrollBar.vertical: ScrollBar {}

            delegate: Item {
                id: cell
                required property var modelData
                width: grid.cellWidth
                height: grid.cellHeight

                Rectangle {
                    anchors.fill: parent
                    anchors.rightMargin: 12
                    anchors.bottomMargin: 4
                    color: area.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        anchors.rightMargin: 10
                        spacing: 12

                        // Initial in a tile, tinted like a cover placeholder.
                        Rectangle {
                            Layout.preferredWidth: 32
                            Layout.preferredHeight: 32
                            color: Qt.hsla(Theme.coverHue(cell.modelData.name), 0.30, 0.34, 1)
                            Text {
                                anchors.centerIn: parent
                                text: cell.modelData.name.charAt(0)
                                color: Qt.rgba(1, 1, 1, 0.8)
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: cell.modelData.name
                            color: Theme.text
                            font.pixelSize: 14
                            elide: Text.ElideRight
                        }
                        Text {
                            text: cell.modelData.albumCount
                            color: Theme.textFaint
                            font.pixelSize: Theme.fontSmall
                            font.features: { "tnum": 1 }
                        }
                    }
                    MouseArea {
                        id: area
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Nav.go({ page: "artist", artist: cell.modelData })
                    }
                }
            }
        }
    }
}
