import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Kleulir

// Results for Nav.query, refreshed shortly after each keystroke.
Item {
    id: root

    property var albums: []
    property var songs: []
    property string shownFor: ""       // the query the lists belong to
    property bool waiting: false

    readonly property string query: Nav.query.trim()
    onQueryChanged: {
        if (query.length === 0) {
            albums = []
            songs = []
            shownFor = ""
            waiting = false
        } else {
            waiting = true
            debounce.restart()
        }
    }
    Component.onCompleted: if (query.length > 0) { waiting = true; debounce.restart() }

    // Wait for a pause in typing before asking the server.
    Timer {
        id: debounce
        interval: 220
        onTriggered: Library.search(root.query)
    }
    Connections {
        target: Library
        function onSearchLoaded(query, result) {
            // Answers can arrive out of order; keep only the one for what is typed now.
            if (query !== root.query)
                return
            root.albums = result.albums || []
            root.songs = result.songs || []
            root.shownFor = query
            root.waiting = false
        }
    }

    readonly property bool empty: albums.length === 0 && songs.length === 0

    Text {
        anchors.centerIn: parent
        visible: root.empty
        text: root.query.length === 0 ? "Type to search your library"
              : root.waiting ? "Searching…"
              : "No results for “" + root.shownFor + "”"
        color: Theme.textFaint
        font.pixelSize: 14
    }

    TrackList {
        id: list
        anchors.fill: parent
        anchors.leftMargin: 24
        anchors.rightMargin: 12
        // Always visible, even when empty: hiding the list and showing it again
        // left the header's Column with stale positions.
        tracks: root.songs
        showAlbum: true

        // A layout, not a Column positioner: as a ListView header the positioner
        // did not re-stack its children when the album row became visible.
        header: Item {
            width: list.width - list.sideMargin
            height: headerLayout.implicitHeight + 28

            ColumnLayout {
                id: headerLayout
                y: 20
                width: parent.width
                spacing: 14

            Text {
                text: "Search"
                color: Theme.text
                font.pixelSize: Theme.fontTitle
                font.weight: Font.Bold
            }

            Text {
                visible: root.albums.length > 0
                text: "Albums"
                color: Theme.text
                font.pixelSize: 15
                font.weight: Font.DemiBold
            }
            // One row of albums; the wheel scrolls it sideways when there are many.
            ListView {
                id: albumRow
                visible: root.albums.length > 0
                Layout.fillWidth: true
                Layout.preferredHeight: 196
                orientation: ListView.Horizontal
                spacing: 16
                clip: true
                model: root.albums
                boundsBehavior: Flickable.StopAtBounds

                delegate: Item {
                    id: card
                    required property var modelData
                    width: 140
                    height: albumRow.height

                    Column {
                        width: parent.width
                        spacing: 4
                        Cover {
                            width: 140
                            height: 140
                            title: card.modelData.title
                            art: card.modelData.coverArt
                            shadow: cardArea.containsMouse
                        }
                        Text {
                            width: parent.width
                            topPadding: 4
                            text: card.modelData.title
                            color: Theme.text
                            font.pixelSize: Theme.fontBody
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: card.modelData.artist
                            color: Theme.textDim
                            font.pixelSize: Theme.fontSmall
                            elide: Text.ElideRight
                        }
                    }
                    MouseArea {
                        id: cardArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Nav.openAlbum(card.modelData)
                    }
                }
            }

            Text {
                visible: root.songs.length > 0
                topPadding: 4
                text: "Songs"
                color: Theme.text
                font.pixelSize: 15
                font.weight: Font.DemiBold
            }
            }
        }
    }
}
