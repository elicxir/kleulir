import QtQuick
import QtQuick.Controls.Basic
import Kleulir

// A row of mutually exclusive choices. `options` is [{ key, label }].
Rectangle {
    id: root
    property var options: []
    property string current: ""
    signal picked(string key)

    implicitWidth: row.implicitWidth + 6
    implicitHeight: 32
    color: Theme.raised
    border.color: Theme.line

    Row {
        id: row
        anchors.centerIn: parent
        Repeater {
            model: root.options
            delegate: AbstractButton {
                id: segment
                required property var modelData
                readonly property bool selected: root.current === modelData.key
                implicitWidth: label.implicitWidth + 28
                implicitHeight: 26
                hoverEnabled: true
                onClicked: root.picked(modelData.key)
                background: Rectangle {
                    color: segment.selected ? Theme.hover : "transparent"
                }
                contentItem: Text {
                    id: label
                    text: segment.modelData.label
                    color: segment.selected ? Theme.text : segment.hovered ? Theme.text : Theme.textDim
                    font.pixelSize: Theme.fontSmall
                    font.weight: segment.selected ? Font.DemiBold : Font.Normal
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
    }
}
