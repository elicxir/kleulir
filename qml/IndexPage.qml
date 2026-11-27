import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Kleulir

// A page of names in columns, with a filter: works, compositions.
// `items` is [{ id, name, detail?, count? }].
Item {
    id: root

    property string title: ""
    property string unit: "items"        // "12 works"
    property string emptyText: "Nothing here yet."
    property var items: []
    property bool loaded: false
    signal opened(var item)

    // `--demo-first`: open the first entry once the list is there (screenshot runs).
    property bool demoDone: false
    onItemsChanged: {
        if (!demoDone && items.length > 0 && Qt.application.arguments.indexOf("--demo-first") >= 0) {
            demoDone = true
            opened(items[0])
        }
    }

    property string filter: ""
    readonly property var shown: {
        const text = filter.trim().toLowerCase()
        if (text.length === 0)
            return items
        return items.filter(i => i.name.toLowerCase().indexOf(text) >= 0
                                 || (i.detail || "").toLowerCase().indexOf(text) >= 0)
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
                text: root.title
                color: Theme.text
                font.pixelSize: Theme.fontTitle
                font.weight: Font.Bold
            }
            Text {
                visible: root.loaded && root.items.length > 0
                text: root.shown.length + " " + root.unit
                color: Theme.textFaint
                font.pixelSize: Theme.fontBody
                Layout.alignment: Qt.AlignBaseline
            }
            Item { Layout.fillWidth: true }
            TextField {
                id: filterField
                visible: root.items.length > 0
                implicitWidth: 220
                implicitHeight: 32
                leftPadding: 10
                placeholderText: "Filter"
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

        Item {
            visible: root.items.length === 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            Text {
                anchors.centerIn: parent
                text: root.loaded ? root.emptyText : "Loading…"
                color: Theme.textFaint
                font.pixelSize: 14
            }
        }

        GridView {
            id: grid
            visible: root.items.length > 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: root.shown
            readonly property int columns: Math.max(1, Math.floor(width / 360))
            cellWidth: Math.floor((width - 8) / columns)
            cellHeight: 52
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
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 12

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text {
                                Layout.fillWidth: true
                                text: cell.modelData.name
                                color: Theme.text
                                font.pixelSize: 14
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.fillWidth: true
                                visible: text.length > 0
                                text: cell.modelData.detail || ""
                                color: Theme.textDim
                                font.pixelSize: Theme.fontSmall
                                elide: Text.ElideRight
                            }
                        }
                        Text {
                            visible: cell.modelData.count !== undefined
                            text: cell.modelData.count || ""
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
                        onClicked: root.opened(cell.modelData)
                    }
                }
            }
        }
    }
}
