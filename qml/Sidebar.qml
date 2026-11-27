import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Kleulir

Rectangle {
    id: root
    color: Theme.bg

    // The page that is open; an album belongs under Albums.
    readonly property string currentKey: {
        const page = Nav.current.page
        return page === "album" ? "albums" : page === "artist" ? "artists" : page === "playlist" ? "playlists" : page
    }

    // Only pages that exist. Genres, Folders, Works and Suggestions come back as
    // they are built.
    readonly property var entries: [
        { section: "LIBRARY" },
        { key: "albums", label: "Albums" },
        { key: "artists", label: "Artists" },
        { section: "YOU" },
        { key: "starred", label: "Starred" },
        { key: "playlists", label: "Playlists" }
    ]

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.gap
        spacing: 2

        // History, like a browser's back and forward.
        RowLayout {
            spacing: 2
            Layout.bottomMargin: 4
            IconButton {
                glyph: "back"
                tip: "Back  (Alt+Left)"
                enabled: Nav.canBack
                onClicked: Nav.back()
            }
            IconButton {
                glyph: "forward"
                tip: "Forward  (Alt+Right)"
                enabled: Nav.canForward
                onClicked: Nav.forward()
            }
        }

        // Search as you type.
        TextField {
            id: search
            Layout.fillWidth: true
            Layout.bottomMargin: 6
            implicitHeight: 34
            leftPadding: 34
            rightPadding: clear.visible ? 30 : 8
            placeholderText: "Search"
            placeholderTextColor: Theme.textFaint
            color: Theme.text
            font.pixelSize: Theme.fontBody
            selectByMouse: true
            text: Nav.query
            onTextEdited: Nav.search(text)
            onAccepted: Nav.search(text)
            Keys.onEscapePressed: {
                Nav.search("")
                focus = false
            }
            background: Rectangle {
                color: Theme.raised
                border.color: search.activeFocus ? Theme.accent : Theme.line
            }

            Icon {
                x: 10
                anchors.verticalCenter: parent.verticalCenter
                name: "search"
                size: 16
                color: Theme.textDim
            }
            IconButton {
                id: clear
                visible: search.text.length > 0
                anchors.right: parent.right
                anchors.rightMargin: 2
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: 26
                implicitHeight: 26
                glyph: "close"
                glyphSize: 14
                onClicked: {
                    Nav.search("")
                    search.forceActiveFocus()
                }
            }
        }
        Shortcut {
            sequences: ["Ctrl+K", "Ctrl+F"]
            onActivated: {
                search.forceActiveFocus()
                search.selectAll()
            }
        }

        Repeater {
            model: root.entries

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
                        topPadding: 14
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
                        onClicked: Nav.openPage(slot.modelData.key)
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
            onClicked: Nav.openPage("settings")
        }
    }
}
