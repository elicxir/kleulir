import QtQuick
import QtQuick.Controls.Basic
import Kleulir

MenuItem {
    id: root
    implicitHeight: 32
    // Hidden items take no room.
    height: visible ? implicitHeight : 0

    // A submenu's row shows where it leads.
    arrow: Icon {
        x: root.width - width - 6
        y: (root.height - height) / 2
        visible: root.subMenu !== null
        name: "forward"
        size: 16
        color: Theme.textDim
    }

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
