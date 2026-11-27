import QtQuick
import QtQuick.Controls.Basic
import Kleulir

// Flat button showing an icon (`glyph`, a name from Icon.qml) or a short label.
AbstractButton {
    id: root
    property string glyph: ""
    property string tip: ""
    property bool active: false
    // Draws a small accent mark under the icon: a toggle that is switched on.
    property bool marked: false
    property int glyphSize: 18
    property int labelSize: Theme.fontBody

    readonly property color tint: !enabled ? Theme.textFaint
                                  : active ? Theme.text
                                  : hovered ? Theme.text : Theme.textDim

    implicitWidth: glyph.length > 0 ? 32 : label.implicitWidth + 20
    implicitHeight: 32
    hoverEnabled: true

    Accessible.name: tip.length > 0 ? tip : text

    background: Rectangle {
        color: root.down ? Theme.raised : root.hovered && root.enabled ? Theme.hover : "transparent"
    }

    contentItem: Item {
        Rectangle {
            visible: root.marked
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 2
            width: 4
            height: 4
            color: Theme.accent
        }
        Icon {
            anchors.centerIn: parent
            visible: root.glyph.length > 0
            name: root.glyph
            size: root.glyphSize
            color: root.tint
        }
        Text {
            id: label
            anchors.centerIn: parent
            visible: root.glyph.length === 0
            text: root.text
            color: root.tint
            font.pixelSize: root.labelSize
        }
    }

    ToolTip.visible: hovered && tip.length > 0
    ToolTip.delay: 600
    ToolTip.text: tip
}
