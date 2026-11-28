import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Kleulir

// A list of songs that behaves like the ones in other players: click selects
// (Ctrl and Shift extend), double click plays from there, right click opens the
// menu for the selection, Ctrl+A selects all and Enter plays.
ListView {
    id: list

    property var tracks: []            // song maps from Library
    property var album: null           // set when the songs are one album's
    property bool groupByWork: false   // section headers per work (album pages)
    property bool showAlbum: false     // show each song's album (search results)
    property string playlistId: ""     // set on a playlist's page
    property bool showVariations: true // mark songs that have other recordings (VAR)
    property string markedId: ""       // the song a page is about, tagged in its row
    property real sideMargin: 12       // room kept for the scroll bar
    // The artist column: as wide as the setting says, but never more than a share of
    // the list, so that a narrow window leaves the room to the titles.
    readonly property real artistWidth: showAlbum ? Math.min(App.artistColumnWidth * 1.75, width * 0.26)
                                                  : Math.min(App.artistColumnWidth, width * 0.15)

    clip: true
    bottomMargin: Theme.pad
    focus: true
    ScrollBar.vertical: ScrollBar {}

    // A ListModel rather than the JS array: ListView sections need named roles.
    model: ListModel { id: rows }
    onTracksChanged: {
        clearSelection()
        rows.clear()
        tracks.forEach(t => rows.append({
            trackId: t.id, title: t.title, artist: t.artist, albumTitle: t.album || "",
            duration: t.duration, work: t.work || "", variations: t.variations || 0, badge: t.badge || ""
        }))
    }

    // Stay at the very top while the header changes height (search results arriving
    // make it taller). Without this the view keeps its old offset and the new part
    // of the header ends up scrolled out above it.
    property real knownOriginY: 0
    onOriginYChanged: {
        if (Math.abs(contentY - knownOriginY) < 1)
            contentY = originY
        knownOriginY = originY
    }

    // ---- selection ---------------------------------------------------------

    property var selected: ({})        // row index -> true
    property int anchor: -1            // where a Shift range starts
    property int selectionRevision: 0

    function isSelected(index) {
        selectionRevision
        return selected[index] === true
    }
    function selectedTracks() {
        return Object.keys(selected).map(Number).sort((a, b) => a - b).map(i => tracks[i])
    }
    function clearSelection() {
        selected = ({})
        anchor = -1
        ++selectionRevision
    }
    function selectOnly(index) {
        const next = {}
        next[index] = true
        selected = next
        anchor = index
        ++selectionRevision
    }
    function click(index, modifiers) {
        if (modifiers & Qt.ShiftModifier && anchor >= 0) {
            const next = {}
            for (let i = Math.min(anchor, index); i <= Math.max(anchor, index); ++i)
                next[i] = true
            selected = next
        } else if (modifiers & Qt.ControlModifier) {
            const next = Object.assign({}, selected)
            if (next[index])
                delete next[index]
            else
                next[index] = true
            selected = next
            anchor = index
        } else {
            selectOnly(index)
            return
        }
        ++selectionRevision
    }
    function openMenu(index) {
        // Right click on something outside the selection selects it first.
        if (!isSelected(index))
            selectOnly(index)
        menu.tracks = selectedTracks()
        menu.rows = Object.keys(selected).map(Number).sort((a, b) => a - b)
        menu.popup()
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier)) {
            const next = {}
            for (let i = 0; i < tracks.length; ++i)
                next[i] = true
            selected = next
            ++selectionRevision
            event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            const picked = Object.keys(selected).map(Number).sort((a, b) => a - b)
            if (picked.length === 1)
                Player.playTracks(tracks, album, picked[0])
            else if (picked.length > 1)
                Player.playTracks(selectedTracks(), album, 0)
            event.accepted = picked.length > 0
        } else if (event.key === Qt.Key_Escape) {
            clearSelection()
            event.accepted = true
        }
    }

    // Held as a property, not as a child: a child of a ListView lands in its
    // scrolling content, which is the wrong parent for a popup.
    property TrackMenu menu: TrackMenu {
        album: list.album
        showGoToAlbum: list.album === null
        playlistId: list.playlistId
    }

    // ---- sections ----------------------------------------------------------

    section.property: groupByWork ? "work" : ""
    section.delegate: Item {
        // `section` comes from the context, not through a required property: this
        // file's root is the ListView, which has a `section` of its own, and Qt then
        // fails to update a required one when it reuses a heading that scrolled out
        // of view (Disc 3 came up headed "Disc 1").
        readonly property string name: section
        width: list.width - list.sideMargin
        height: 44
        Text {
            anchors.left: parent.left
            anchors.leftMargin: Theme.gap
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 8
            text: parent.name.length > 0 ? parent.name : "No work"
            color: parent.name.length > 0 ? Theme.text : Theme.textFaint
            font.pixelSize: Theme.fontSmall
            font.weight: Font.DemiBold
            font.letterSpacing: 0.4
        }
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: Qt.rgba(1, 1, 1, 0.06)
        }
    }

    // ---- rows --------------------------------------------------------------

    delegate: Rectangle {
        id: row
        required property int index
        required property string trackId
        required property string title
        required property string artist
        required property string albumTitle
        required property real duration
        required property int variations
        required property string badge    // e.g. the arrangement, on the variations list
        readonly property var track: index < list.tracks.length ? list.tracks[index] : null
        readonly property bool isCurrent: Player.current !== null && Player.current.trackId === trackId
        readonly property bool isSelected: list.isSelected(index)
        readonly property bool hot: rowArea.containsMouse || starButton.hovered || moreButton.hovered || variationsArea.containsMouse
                                    || artistArea.containsMouse || albumArea.containsMouse
        readonly property bool starred: {
            Library.starRevision
            return Library.isStarred(trackId)
        }

        width: list.width - list.sideMargin
        height: 38
        color: row.isSelected ? Qt.rgba(1, 1, 1, 0.12) : row.hot ? Qt.rgba(1, 1, 1, 0.06) : "transparent"

        MouseArea {
            id: rowArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onPressed: mouse => {
                list.forceActiveFocus()
                if (mouse.button === Qt.RightButton)
                    list.openMenu(row.index)
                else
                    list.click(row.index, mouse.modifiers)
            }
            onDoubleClicked: mouse => {
                if (mouse.button === Qt.LeftButton)
                    Player.playTracks(list.tracks, list.album, row.index)
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.gap
            anchors.rightMargin: 12
            spacing: 10

            Item {
                Layout.preferredWidth: 24
                Layout.fillHeight: true
                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !row.isCurrent
                    text: row.index + 1
                    color: Theme.textFaint
                    font.pixelSize: Theme.fontBody
                    font.features: { "tnum": 1 }
                }
                Icon {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: row.isCurrent
                    name: Player.playing ? "play" : "pause"
                    size: 14
                    color: Theme.accent
                }
            }
            Text {
                Layout.fillWidth: true
                text: row.title
                color: row.isCurrent ? Theme.accent : Theme.text
                font.pixelSize: 14
                elide: Text.ElideRight
            }
            Rectangle {
                visible: row.badge.length > 0
                implicitWidth: badgeLabel.implicitWidth + 12
                implicitHeight: 18
                color: Theme.raised
                Text {
                    id: badgeLabel
                    anchors.centerIn: parent
                    text: row.badge
                    color: Theme.textDim
                    font.pixelSize: 10
                }
            }
            // The song has other recordings (arrangements, performances); a click lists them.
            Rectangle {
                visible: list.showVariations && row.variations > 0
                implicitWidth: variationsLabel.implicitWidth + 12
                implicitHeight: 18
                color: variationsArea.containsMouse ? Theme.hover : "transparent"
                border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.6)
                Text {
                    id: variationsLabel
                    anchors.centerIn: parent
                    text: "VAR"
                    color: Theme.accent
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                }
                MouseArea {
                    id: variationsArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Nav.go({ page: "versions", song: row.track })
                    ToolTip.visible: containsMouse
                    ToolTip.delay: 600
                    ToolTip.text: row.variations === 1 ? "1 other variation" : row.variations + " other variations"
                }
            }
            Rectangle {
                visible: list.markedId.length > 0 && row.trackId === list.markedId
                implicitWidth: markedLabel.implicitWidth + 12
                implicitHeight: 18
                color: "transparent"
                border.color: Qt.rgba(1, 1, 1, 0.25)
                Text {
                    id: markedLabel
                    anchors.centerIn: parent
                    text: "THIS SONG"
                    color: Theme.textDim
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                }
            }
            // Artist, and on lists across albums the album: each opens its page on a click.
            RowLayout {
                id: byline
                Layout.preferredWidth: list.artistWidth
                Layout.maximumWidth: list.artistWidth
                spacing: 0
                readonly property bool withAlbum: list.showAlbum && row.albumTitle.length > 0
                readonly property bool artistLink: !!row.track && !!row.track.artistId
                readonly property bool albumLink: !!row.track && !!row.track.albumId
                Text {
                    Layout.maximumWidth: byline.withAlbum ? list.artistWidth * 0.45 : list.artistWidth
                    text: row.artist
                    color: artistArea.containsMouse ? Theme.text : Theme.textDim
                    font.pixelSize: Theme.fontBody
                    font.underline: artistArea.containsMouse
                    elide: Text.ElideRight
                    MouseArea {
                        id: artistArea
                        anchors.fill: parent
                        enabled: byline.artistLink
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Nav.openArtist(row.track.artistId, row.track.artistName)
                    }
                }
                Text {
                    visible: byline.withAlbum
                    text: " · "
                    color: Theme.textDim
                    font.pixelSize: Theme.fontBody
                }
                Text {
                    visible: byline.withAlbum
                    Layout.fillWidth: true
                    text: row.albumTitle
                    color: albumArea.containsMouse ? Theme.text : Theme.textDim
                    font.pixelSize: Theme.fontBody
                    font.underline: albumArea.containsMouse
                    elide: Text.ElideRight
                    MouseArea {
                        id: albumArea
                        anchors.fill: parent
                        enabled: byline.albumLink
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Nav.openAlbumId(row.track.albumId, row.albumTitle)
                    }
                }
                Item { Layout.fillWidth: true; visible: !byline.withAlbum }
            }
            IconButton {
                id: starButton
                opacity: row.hot || row.starred ? 1 : 0
                glyph: row.starred ? "heart" : "heartOutline"
                glyphSize: 16
                active: row.starred
                tip: row.starred ? "Remove from Starred" : "Add to Starred"
                onClicked: Library.setStarred([row.trackId], !row.starred)
            }
            IconButton {
                id: moreButton
                opacity: row.hot ? 1 : 0
                glyph: "more"
                tip: "More"
                onClicked: list.openMenu(row.index)
            }
            Text {
                Layout.preferredWidth: 40
                text: Theme.time(row.duration)
                color: Theme.textDim
                font.pixelSize: Theme.fontBody
                font.features: { "tnum": 1 }
                horizontalAlignment: Text.AlignRight
            }
        }
    }
}
