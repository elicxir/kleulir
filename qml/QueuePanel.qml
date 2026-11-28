import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Kleulir

Rectangle {
    id: root
    color: Theme.panel

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.gap
        anchors.topMargin: 14
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.gap
            spacing: Theme.gap

            Text {
                text: "Queue"
                color: Theme.text
                font.pixelSize: 16
                font.weight: Font.Bold
            }
            Text {
                text: Player.queue.count + " tracks"
                color: Theme.textFaint
                font.pixelSize: Theme.fontSmall
                Layout.alignment: Qt.AlignBaseline
            }
            Item { Layout.fillWidth: true }
            IconButton {
                text: "Clear"
                labelSize: Theme.fontSmall
                implicitHeight: 28
                visible: Player.queue.count > 0
                onClicked: Player.clear()
            }
        }

        Item {
            visible: Player.queue.count === 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            Column {
                anchors.centerIn: parent
                spacing: 8
                Icon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: "queue"
                    size: 32
                    color: Theme.hover
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Queue is empty"
                    color: Theme.textFaint
                    font.pixelSize: Theme.fontBody
                }
            }
        }

        // Right-click menu for one queue entry.
        PopupMenu {
            id: menu
            property int row: -1
            readonly property var entry: row >= 0 && row < Player.queue.count ? Player.queue.get(row) : null
            readonly property bool starred: {
                Library.starRevision
                return entry ? Library.isStarred(entry.trackId) : false
            }
            PopupMenuItem {
                text: "Play"
                onTriggered: Player.jump(menu.row)
            }
            PopupMenuItem {
                text: "Remove from queue"
                onTriggered: Player.removeAt(menu.row)
            }
            MenuDivider {}
            PopupMenuItem {
                text: menu.starred ? "Remove from Starred" : "Add to Starred"
                onTriggered: Library.setStarred([menu.entry.trackId], !menu.starred)
            }
            PopupMenuItem {
                visible: menu.entry !== null && menu.entry.albumId.length > 0
                text: "Go to album"
                onTriggered: Nav.openAlbumId(menu.entry.albumId, menu.entry.album)
            }
            PopupMenuItem {
                text: "Show details"
                onTriggered: Nav.openSong(menu.entry.trackId, menu.entry.title)
            }
        }

        ListView {
            id: list
            visible: Player.queue.count > 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 0
            model: Player.queue
            ScrollBar.vertical: ScrollBar {}

            // Dragging a row: nothing moves until it is dropped; a line shows
            // where it would go. dropAt is the gap before that row (0..count).
            readonly property int rowHeight: 52
            property int dragFrom: -1
            property int dropAt: -1
            property real dragY: 0  // the pointer, in the list's own coordinates

            function trackDrag(y) {
                dragY = y
                dropAt = Math.max(0, Math.min(count, Math.round((y + contentY - originY) / rowHeight)))
            }
            function endDrag(commit) {
                if (commit && dragFrom >= 0 && dropAt >= 0) {
                    const to = dropAt > dragFrom ? dropAt - 1 : dropAt
                    if (to !== dragFrom)
                        Player.move(dragFrom, to)
                }
                dragFrom = -1
                dropAt = -1
            }

            // Scrolls while the pointer is held near the top or bottom edge.
            Timer {
                interval: 16
                repeat: true
                running: list.dragFrom >= 0
                onTriggered: {
                    const edge = 36
                    let step = 0
                    if (list.dragY < edge)
                        step = -Math.ceil((edge - list.dragY) / 3)
                    else if (list.dragY > list.height - edge)
                        step = Math.ceil((list.dragY - (list.height - edge)) / 3)
                    if (step === 0)
                        return
                    const top = list.originY
                    const bottom = Math.max(top, top + list.contentHeight - list.height)
                    list.contentY = Math.max(top, Math.min(bottom, list.contentY + Math.max(-16, Math.min(16, step))))
                    list.trackDrag(list.dragY)
                }
            }

            Rectangle {
                visible: list.dragFrom >= 0 && list.dropAt >= 0
                         && list.dropAt !== list.dragFrom && list.dropAt !== list.dragFrom + 1
                z: 5
                x: 0
                y: list.dropAt * list.rowHeight - (list.contentY - list.originY) - 1
                width: list.width
                height: 2
                color: Theme.text
            }

            delegate: Rectangle {
                id: row
                required property int index
                required property string title
                required property string artist
                required property string album
                required property string coverArt
                required property real duration
                readonly property bool isCurrent: index === Player.currentIndex
                readonly property bool played: index < Player.currentIndex
                readonly property bool dragged: list.dragFrom === index
                readonly property bool hot: list.dragFrom < 0 && (rowArea.containsMouse || removeButton.hovered)

                width: list.width
                height: list.rowHeight
                opacity: dragged ? 0.35 : 1
                color: row.isCurrent ? Theme.raised : row.hot ? Qt.rgba(1, 1, 1, 0.05) : "transparent"

                MouseArea {
                    id: rowArea
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    // Otherwise the list takes the press over as a scroll.
                    preventStealing: true
                    cursorShape: list.dragFrom >= 0 ? Qt.ClosedHandCursor : Qt.ArrowCursor
                    property real pressY: 0
                    onPressed: mouse => {
                        pressY = mouse.y
                        if (mouse.button === Qt.RightButton) {
                            menu.row = row.index
                            menu.popup()
                        }
                    }
                    onPositionChanged: mouse => {
                        if (!(mouse.buttons & Qt.LeftButton))
                            return
                        if (list.dragFrom < 0) {
                            if (Math.abs(mouse.y - pressY) < 6 || Player.queue.count < 2)
                                return
                            list.dragFrom = row.index
                        }
                        list.trackDrag(mapToItem(list, mouse.x, mouse.y).y)
                    }
                    onReleased: list.endDrag(true)
                    onCanceled: list.endDrag(false)
                    onDoubleClicked: mouse => {
                        if (mouse.button === Qt.LeftButton)
                            Player.jump(row.index)
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.gap
                    anchors.rightMargin: 4
                    spacing: 10

                    Cover {
                        Layout.preferredWidth: 36
                        Layout.preferredHeight: 36
                        title: row.album
                        art: row.coverArt
                        opacity: row.played ? 0.45 : 1
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        opacity: row.played ? 0.5 : 1
                        Text {
                            Layout.fillWidth: true
                            text: row.title
                            color: row.isCurrent ? Theme.accent : Theme.text
                            font.pixelSize: Theme.fontBody
                            font.weight: row.isCurrent ? Font.DemiBold : Font.Normal
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            text: row.artist
                            color: Theme.textDim
                            font.pixelSize: Theme.fontSmall
                            elide: Text.ElideRight
                        }
                    }
                    Text {
                        visible: !row.hot
                        Layout.rightMargin: 8
                        text: Theme.time(row.duration)
                        color: Theme.textFaint
                        font.pixelSize: Theme.fontSmall
                        font.features: { "tnum": 1 }
                    }
                    Row {
                        visible: row.hot
                        IconButton {
                            id: removeButton
                            implicitWidth: 28
                            glyph: "close"
                            glyphSize: 16
                            tip: "Remove from queue"
                            onClicked: Player.removeAt(row.index)
                        }
                    }
                }
            }
        }
    }
}
