import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Kleulir

// Everything known about one song: who made it, what it is a recording of, how often it
// was played, the file, and on an eos server the tags as they are in the file.
// Library.loadSong() hands over ready-made sections of rows; this page only draws them.
Item {
    id: root
    property var song              // { id, title } from wherever it was opened
    property var info: ({})
    property bool loaded: false

    readonly property var track: info.track || null
    readonly property var sections: info.sections || []
    readonly property string error: info.error || ""
    readonly property bool starred: {
        Library.starRevision
        return root.song ? Library.isStarred(root.song.id) : false
    }

    function request() {
        loaded = false
        info = {}
        if (song)
            Library.loadSong(song.id)
    }
    onSongChanged: request()
    Component.onCompleted: request()

    Connections {
        target: Library
        function onSongLoaded(id, data) {
            if (!root.song || id !== root.song.id)
                return
            root.info = data
            root.loaded = true
            // A new song starts at the top. Development aid: `--demo-song-end` shows the
            // end of the page instead (file and tags).
            const end = Qt.application.arguments.indexOf("--demo-song-end") >= 0
            Qt.callLater(() => flick.contentY = end ? Math.max(0, flick.contentHeight - flick.height) : 0)
        }
    }

    Flickable {
        id: flick
        anchors.fill: parent
        anchors.leftMargin: 24
        contentWidth: width
        contentHeight: content.implicitHeight + 48
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}

        ColumnLayout {
            id: content
            y: 20
            width: flick.width - 36
            spacing: 22

            // ---- what it is, and what can be done with it ----
            RowLayout {
                Layout.fillWidth: true
                spacing: 20

                Cover {
                    Layout.preferredWidth: 148
                    Layout.preferredHeight: 148
                    Layout.alignment: Qt.AlignTop
                    title: root.info.album || (root.song ? root.song.title : "")
                    art: root.info.coverArt || ""
                    shadow: true
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 4
                    Text {
                        text: "SONG"
                        color: Theme.textDim
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        font.letterSpacing: 0.6
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.info.title || (root.song ? root.song.title : "")
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
                            const parts = [root.info.artist || "", root.info.album || ""]
                            if (root.info.duration > 0)
                                parts.push(Theme.time(root.info.duration))
                            return parts.filter(x => x !== "").join(" · ")
                        }
                        color: Theme.textDim
                        font.pixelSize: Theme.fontBody
                    }

                    Flow {
                        Layout.fillWidth: true
                        Layout.topMargin: 10
                        spacing: 8
                        visible: root.track !== null
                        IconButton {
                            text: "Play"
                            labelSize: Theme.fontSmall
                            implicitHeight: 26
                            onClicked: Player.playTracks([root.track], null, 0)
                        }
                        IconButton {
                            text: "Play next"
                            labelSize: Theme.fontSmall
                            implicitHeight: 26
                            onClicked: Player.playNext(root.track, null)
                        }
                        IconButton {
                            text: "Add to queue"
                            labelSize: Theme.fontSmall
                            implicitHeight: 26
                            onClicked: Player.enqueue(root.track, null)
                        }
                        IconButton {
                            text: root.starred ? "Starred" : "Star"
                            active: root.starred
                            labelSize: Theme.fontSmall
                            implicitHeight: 26
                            onClicked: Library.setStarred([root.song.id], !root.starred)
                        }
                        // Other recordings of the same music; only an eos server knows them.
                        IconButton {
                            visible: Session.eosFeatures
                            text: "All variations"
                            labelSize: Theme.fontSmall
                            implicitHeight: 26
                            onClicked: Nav.go({ page: "versions", song: root.track })
                        }
                        IconButton {
                            visible: Session.serverFeatures.indexOf("graph") >= 0
                            text: "Related graph"
                            labelSize: Theme.fontSmall
                            implicitHeight: 26
                            onClicked: Nav.go({ page: "graph", seed: "song:" + root.song.id,
                                                label: root.info.title || "", mode: "related" })
                        }
                    }
                }
            }

            Text {
                visible: root.error.length > 0
                text: root.error
                color: Theme.estimated
                font.pixelSize: 14
            }

            // ---- sections of label / value rows ----
            Repeater {
                model: root.sections
                delegate: ColumnLayout {
                    id: section
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 0

                    Text {
                        Layout.bottomMargin: 8
                        text: section.modelData.title
                        color: Theme.text
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Qt.rgba(1, 1, 1, 0.06)
                    }

                    Repeater {
                        model: section.modelData.rows
                        delegate: Item {
                            id: row
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: Math.max(30, values.implicitHeight + 12)

                            Text {
                                x: Theme.gap
                                y: 7
                                width: 172
                                text: row.modelData.label
                                color: Theme.textDim
                                font.pixelSize: Theme.fontBody
                                elide: Text.ElideRight
                            }
                            Flow {
                                id: values
                                x: 196
                                y: 6
                                width: row.width - x - Theme.gap
                                spacing: 6

                                Repeater {
                                    model: row.modelData.items
                                    delegate: Loader {
                                        id: value
                                        required property var modelData
                                        required property int index
                                        readonly property bool last: index === row.modelData.items.length - 1
                                        sourceComponent: modelData.nav || modelData.url ? linkValue : plainValue

                                        // Something to go to: an artist, an album, a work, a web page.
                                        Component {
                                            id: linkValue
                                            Text {
                                                width: Math.min(implicitWidth, values.width)
                                                text: value.modelData.text + (value.last ? "" : ",")
                                                color: linkHover.hovered ? Theme.accentStrong : Theme.accent
                                                font.pixelSize: Theme.fontBody
                                                font.underline: linkHover.hovered
                                                elide: Text.ElideRight
                                                HoverHandler {
                                                    id: linkHover
                                                    cursorShape: Qt.PointingHandCursor
                                                }
                                                TapHandler {
                                                    onTapped: {
                                                        if (value.modelData.nav)
                                                            Nav.go(value.modelData.nav)
                                                        else
                                                            Qt.openUrlExternally(value.modelData.url)
                                                    }
                                                }
                                            }
                                        }
                                        // Plain text, selectable so a path or an id can be copied.
                                        Component {
                                            id: plainValue
                                            TextEdit {
                                                width: Math.min(implicitWidth, values.width)
                                                text: value.modelData.text + (value.last ? "" : ",")
                                                readOnly: true
                                                selectByMouse: true
                                                wrapMode: TextEdit.Wrap
                                                color: Theme.text
                                                selectionColor: Theme.accentDim
                                                selectedTextColor: Theme.text
                                                font.pixelSize: Theme.fontBody
                                            }
                                        }
                                    }
                                }
                                // Where the value came from; estimates stand out.
                                Text {
                                    visible: row.modelData.note.length > 0
                                    leftPadding: 6
                                    text: row.modelData.note
                                    color: row.modelData.estimated ? Theme.estimated : Theme.textFaint
                                    font.pixelSize: Theme.fontSmall
                                    height: 17
                                    verticalAlignment: Text.AlignBottom
                                }
                            }
                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width
                                height: 1
                                color: Qt.rgba(1, 1, 1, 0.03)
                            }
                        }
                    }
                }
            }
        }
    }
}
