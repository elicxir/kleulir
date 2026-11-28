import QtQuick
import Kleulir

// Text that can be copied: drag to select (Ctrl+C), or right-click for "Copy", which
// takes the selection or, with none, the whole text. For names a person may want to
// paste elsewhere: album, song, artist, work. It wraps rather than elides.
TextEdit {
    id: root
    readOnly: true
    selectByMouse: true
    wrapMode: TextEdit.Wrap
    color: Theme.text
    selectionColor: Theme.accentDim
    selectedTextColor: Theme.text
    font.pixelSize: Theme.fontBody
    // Clicking elsewhere drops the selection.
    onActiveFocusChanged: if (!activeFocus) deselect()

    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: menu.popup()
    }
    PopupMenu {
        id: menu
        PopupMenuItem {
            text: root.selectedText.length > 0 ? "Copy selection" : "Copy"
            onTriggered: App.copyText(root.selectedText.length > 0 ? root.selectedText : root.text)
        }
    }
}
