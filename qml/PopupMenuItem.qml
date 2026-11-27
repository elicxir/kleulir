import QtQuick
import QtQuick.Controls.Basic
import Kleulir

MenuItem {
    id: root
    implicitHeight: 32
    // Hidden items take no room.
    height: visible ? implicitHeight : 0

    background: Rectangle {
        color: root.highlighted && root.enabled ? Theme.hover : "transparent"
    }
    contentItem: Text {
        text: root.text
        color: root.enabled ? Theme.text : Theme.textFaint
        font.pixelSize: Theme.fontBody
        leftPadding: Theme.gap
        rightPadding: Theme.gap
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
}
