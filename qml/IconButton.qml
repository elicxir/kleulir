import QtQuick
import QtQuick.Controls.Basic
import Kleulir

// Flat button showing a glyph or a short label.
AbstractButton {
    id: root
    property string tip: ""
    property bool active: false
    property int glyphSize: 16

    implicitWidth: Math.max(32, label.implicitWidth + 16)
    implicitHeight: 32
    hoverEnabled: true

    Accessible.name: tip.length > 0 ? tip : text

    background: Rectangle {
        radius: Theme.radius
        color: root.down ? Theme.raised : root.hovered ? Theme.hover : "transparent"
    }

    contentItem: Text {
        id: label
        text: root.text
        color: !root.enabled ? Theme.textFaint : root.active ? Theme.accent : Theme.text
        font.pixelSize: root.glyphSize
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    ToolTip.visible: hovered && tip.length > 0
    ToolTip.delay: 600
    ToolTip.text: tip
}
