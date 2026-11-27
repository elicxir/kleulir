import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Kleulir

Rectangle {
    id: root
    property string currentKey: "albums"
    signal navigate(string key)

    color: Theme.panel

    // `eos: true` entries need /ext and are hidden on a plain OpenSubsonic server.
    readonly property var entries: [
        { section: "ライブラリ" },
        { key: "albums", label: "アルバム" },
        { key: "artists", label: "アーティスト" },
        { key: "genres", label: "ジャンル" },
        { key: "folders", label: "フォルダ", eos: true },
        { key: "works", label: "作品", eos: true },
        { section: "自分" },
        { key: "starred", label: "お気に入り" },
        { key: "playlists", label: "プレイリスト" },
        { section: "管理", eos: true },
        { key: "suggestions", label: "候補の承認", eos: true }
    ]

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.gap
        spacing: 2

        Text {
            text: "kleulir"
            color: Theme.text
            font.pixelSize: 18
            font.weight: Font.DemiBold
            Layout.margins: Theme.gap
        }

        Button {
            id: searchButton
            Layout.fillWidth: true
            implicitHeight: 32
            hoverEnabled: true
            onClicked: root.navigate("search")
            background: Rectangle {
                radius: Theme.radius
                color: searchButton.hovered ? Theme.hover : Theme.raised
            }
            contentItem: Text {
                text: "検索"
                color: Theme.textDim
                font.pixelSize: Theme.fontBody
                leftPadding: Theme.gap
                verticalAlignment: Text.AlignVCenter
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
                        font.pixelSize: Theme.fontSmall
                        topPadding: Theme.pad
                        leftPadding: Theme.gap
                        bottomPadding: 4
                    }
                }

                Component {
                    id: navItem
                    ItemDelegate {
                        id: item
                        readonly property bool selected: root.currentKey === slot.modelData.key
                        implicitHeight: 32
                        hoverEnabled: true
                        onClicked: root.navigate(slot.modelData.key)
                        background: Rectangle {
                            radius: Theme.radius
                            color: item.selected ? Theme.raised : item.hovered ? Theme.hover : "transparent"
                        }
                        contentItem: Text {
                            text: slot.modelData.label
                            color: item.selected ? Theme.text : Theme.textDim
                            font.pixelSize: Theme.fontBody
                            leftPadding: Theme.gap
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }
        }

        Item { Layout.fillHeight: true }
    }
}
