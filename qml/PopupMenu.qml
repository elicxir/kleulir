import QtQuick
import QtQuick.Controls.Basic
import Kleulir

// A context menu in the app's look. Fill it with PopupMenuItem and MenuDivider.
Menu {
    id: root
    padding: 4
    background: Rectangle {
        implicitWidth: 220
        color: Theme.raised
        border.color: Theme.line
    }
}
