import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Kleulir

Rectangle {
    id: root
    color: Theme.bg
    property string currentKey: "albums"
    signal navigate(string key)

    // `eos: true` entries need /ext and are hidden on a plain OpenSubsonic server.
    readonly property var entries: [
        { section: "LIBRARY" },
        { key: "albums", label: "Albums" },
        { key: "artists", label: "Artists" },
        { key: "genres", label: "Genres" },
        { key: "folders", label: "Folders", eos: true },
        { key: "works", label: "Works", eos: true },
        { section: "YOU" },
        { key: "starred", label: "Starred" },
        { key: "playlists", label: "Playlists" },
        { section: "MANAGE", eos: true },
        { key: "suggestions", label: "Suggestions", eos: true }
    ]

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.gap
        anchors.topMargin: 14
        spacing: 2

        Text {
            text: "kleulir"
            color: Theme.text
            font.pixelSize: 19
            font.weight: Font.Bold
            font.letterSpacing: 0.5
            Layout.leftMargin: 12
            Layout.bottomMargin: 14
        }

        Button {
            id: searchButton
            Layout.fillWidth: true
            Layout.bottomMargin: 6
            implicitHeight: 34
            hoverEnabled: true
            onClicked: root.navigate("search")
            background: Rectangle {
                color: searchButton.hovered ? Theme.hover : Theme.raised
                border.color: root.currentKey === "search" ? Theme.accentDim : Theme.line
            }
            contentItem: Row {
                leftPadding: 10
                spacing: Theme.gap
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "search"
                    size: 16
                    color: Theme.textDim
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Search"
                    color: Theme.textDim
                    font.pixelSize: Theme.fontBody
                }
            }
        }

        Repeater {
            model: root.entries.filter(e => !e.eos || MockData.eosFeatures)

            delegate: Loader {
                id: slot
                required property var modelData
                Layout.fillWidth: true
                sourceComponent: modelData.section ? sectionHeader : navItem

                Component {
                    id: sectionHeader
                    Text {
                        text: slot.modelData.section
                        color: Theme.textFaint
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        font.letterSpacing: 0.6
                        topPadding: 18
                        leftPadding: 12
                        bottomPadding: 6
                    }
                }

                Component {
                    id: navItem
                    ItemDelegate {
                        id: item
                        readonly property bool selected: root.currentKey === slot.modelData.key
                        implicitHeight: 34
                        hoverEnabled: true
                        onClicked: root.navigate(slot.modelData.key)
                        background: Rectangle {
                            color: item.selected ? Theme.raised : item.hovered ? Theme.panel : "transparent"
                            Rectangle {
                                visible: item.selected
                                width: 3
                                height: parent.height
                                color: Theme.accent
                            }
                        }
                        contentItem: Text {
                            text: slot.modelData.label
                            color: item.selected ? Theme.text : item.hovered ? Theme.text : Theme.textDim
                            font.pixelSize: Theme.fontBody
                            font.weight: item.selected ? Font.DemiBold : Font.Normal
                            leftPadding: 14
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }
        }

        Item { Layout.fillHeight: true }

        IconButton {
            Layout.fillWidth: true
            text: "Settings"
            active: root.currentKey === "settings"
            onClicked: root.navigate("settings")
        }
    }
}
