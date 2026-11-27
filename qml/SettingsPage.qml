import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Kleulir

Item {
    id: root

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: 20
        anchors.leftMargin: 24
        anchors.rightMargin: 24
        spacing: 20

        Text {
            text: "Settings"
            color: Theme.text
            font.pixelSize: Theme.fontTitle
            font.weight: Font.Bold
        }

        ColumnLayout {
            spacing: 10

            Text {
                text: "Accent colour"
                color: Theme.text
                font.pixelSize: 15
                font.weight: Font.DemiBold
            }
            Text {
                text: "Marks the current selection and the playing track."
                color: Theme.textDim
                font.pixelSize: Theme.fontBody
            }

            Row {
                spacing: 8
                Layout.topMargin: 4

                Repeater {
                    model: Theme.accentPresets
                    delegate: AbstractButton {
                        id: swatch
                        required property var modelData
                        readonly property bool selected: Qt.colorEqual(Theme.accent, modelData.color)
                        implicitWidth: 64
                        implicitHeight: 64
                        hoverEnabled: true
                        Accessible.name: modelData.name
                        onClicked: Theme.setAccent(modelData.color)
                        background: Rectangle {
                            color: swatch.modelData.color
                            border.width: swatch.selected ? 2 : swatch.hovered ? 1 : 0
                            border.color: Theme.text
                        }
                        contentItem: Text {
                            text: swatch.modelData.name
                            color: Qt.color(swatch.modelData.color).hslLightness > 0.5 ? "#101010" : "#ffffff"
                            font.pixelSize: Theme.fontSmall
                            font.weight: Font.DemiBold
                            leftPadding: 6
                            bottomPadding: 4
                            verticalAlignment: Text.AlignBottom
                        }
                    }
                }
            }

            RowLayout {
                spacing: Theme.gap
                Layout.topMargin: 4

                Text {
                    text: "Hex"
                    color: Theme.textDim
                    font.pixelSize: Theme.fontBody
                }
                TextField {
                    id: hex
                    implicitWidth: 110
                    implicitHeight: 32
                    text: Theme.accent.toString()
                    color: Theme.text
                    font.pixelSize: Theme.fontBody
                    font.family: "Consolas"
                    maximumLength: 7
                    validator: RegularExpressionValidator { regularExpression: /^#[0-9a-fA-F]{6}$/ }
                    selectByMouse: true
                    onAccepted: Theme.setAccent(text)
                    background: Rectangle {
                        color: Theme.raised
                        border.color: hex.activeFocus ? Theme.accent : Theme.line
                    }
                }
                Rectangle {
                    implicitWidth: 32
                    implicitHeight: 32
                    color: hex.acceptableInput ? hex.text : Theme.accent
                    border.color: Theme.line
                }
                IconButton {
                    text: "Apply"
                    enabled: hex.acceptableInput && !Qt.colorEqual(Theme.accent, hex.text)
                    onClicked: Theme.setAccent(hex.text)
                }
                IconButton {
                    text: "Reset"
                    enabled: !Qt.colorEqual(Theme.accent, Theme.defaultAccent)
                    onClicked: Theme.setAccent(Theme.defaultAccent)
                }
            }
        }

        Item { Layout.fillHeight: true }
    }
}
