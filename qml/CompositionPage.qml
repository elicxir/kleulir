import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Kleulir

// The recordings of one piece of music, grouped by arrangement.
// Opened in one of two ways:
//   composition: { id, name }  every recording of it
//   song: a track              the other versions of that song, and what is related
Item {
    id: root
    property var composition: null
    property var song: null

    property var songs: []
    property var related: []          // compositions: { id, name, relation }
    property string name: ""
    property string composers: ""
    property string compositionId: ""
    property bool loaded: false

    function request() {
        if (song)
            Library.loadVersions(song.id)
        else if (composition)
            Library.loadComposition(composition.id)
    }
    onCompositionChanged: request()
    onSongChanged: request()
    Component.onCompleted: request()

    Connections {
        target: Library
        function onCompositionLoaded(id, data) {
            if (root.song || !root.composition || id !== root.composition.id)
                return
            root.name = data.name || root.composition.name
            root.composers = data.composers || ""
            root.songs = data.songs || []
            root.loaded = true
        }
        function onVersionsLoaded(songId, data) {
            if (!root.song || songId !== root.song.id)
                return
            root.name = data.compositionName || ""
            root.compositionId = data.compositionId || ""
            root.composers = data.composers || ""
            root.songs = data.songs || []
            root.related = data.compositions || []
            root.loaded = true
        }
    }

    TrackList {
        id: list
        anchors.fill: parent
        anchors.leftMargin: 24
        anchors.rightMargin: 12
        tracks: root.songs
        showAlbum: true
        groupByWork: true
        showVariations: false   // every song here is a variation

        header: Item {
            width: list.width - list.sideMargin
            height: headerLayout.implicitHeight + 28

            ColumnLayout {
                id: headerLayout
                y: 20
                width: parent.width
                spacing: 12

                ColumnLayout {
                    spacing: 4
                    Text {
                        text: root.song ? "OTHER VERSIONS OF" : "COMPOSITION"
                        color: Theme.textDim
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        font.letterSpacing: 0.6
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.song ? root.song.title : root.composition ? root.composition.name : ""
                        color: Theme.text
                        font.pixelSize: 32
                        font.weight: Font.Bold
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: {
                            if (!root.loaded)
                                return "Loading…"
                            const parts = []
                            if (root.composers.length > 0)
                                parts.push("Composed by " + root.composers)
                            parts.push(root.songs.length + (root.song ? " other recordings" : " recordings"))
                            return parts.join(" · ")
                        }
                        color: Theme.textDim
                        font.pixelSize: Theme.fontBody
                    }
                }

                RowLayout {
                    spacing: 8
                    visible: root.loaded
                    IconButton {
                        visible: root.songs.length > 0
                        text: "Play all"
                        labelSize: Theme.fontSmall
                        implicitHeight: 26
                        onClicked: Player.playTracks(root.songs, null, 0)
                    }
                    // From a song to everything recorded of its composition.
                    IconButton {
                        visible: root.song !== null && root.compositionId.length > 0
                        text: "All recordings of “" + root.name + "”"
                        labelSize: Theme.fontSmall
                        implicitHeight: 26
                        onClicked: Nav.go({ page: "composition",
                                            composition: { id: root.compositionId, name: root.name } })
                    }
                }

                // Other compositions this one is tied to (medleys, quotes, covers).
                Repeater {
                    model: root.related
                    delegate: RowLayout {
                        id: relatedRow
                        required property var modelData
                        spacing: 8
                        Text {
                            text: relatedRow.modelData.relation
                            color: Theme.textDim
                            font.pixelSize: Theme.fontBody
                        }
                        IconButton {
                            text: relatedRow.modelData.name
                            implicitHeight: 26
                            onClicked: Nav.go({ page: "composition", composition: relatedRow.modelData })
                        }
                    }
                }

                Text {
                    visible: root.loaded && root.songs.length === 0
                    Layout.topMargin: 24
                    text: root.song && root.compositionId.length === 0
                          ? "This song is not linked to a composition yet, so no other versions are known."
                          : root.song ? "No other versions of this song in the library."
                                      : "No recordings."
                    color: Theme.textFaint
                    font.pixelSize: 14
                }
            }
        }
    }
}
