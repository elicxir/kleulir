import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Kleulir

ApplicationWindow {
    id: window
    width: 1280
    height: 800
    minimumWidth: 960
    minimumHeight: 600
    visible: true
    title: Player.current ? Player.current.title + " — kleulir" : "kleulir"
    color: Theme.line

    // Colours for the stock controls (tooltips, scroll bars, menus).
    palette.window: Theme.panel
    palette.windowText: Theme.text
    palette.base: Theme.raised
    palette.text: Theme.text
    palette.button: Theme.raised
    palette.buttonText: Theme.text
    palette.mid: Theme.hover
    palette.dark: Theme.textFaint
    palette.highlight: Theme.accent
    palette.highlightedText: Theme.bg
    palette.toolTipBase: Theme.raised
    palette.toolTipText: Theme.text

    property string currentKey: "albums"
    property bool queueOpen: true

    readonly property var pageTitles: ({
        artists: "Artists", genres: "Genres", folders: "Folders", works: "Works",
        starred: "Starred", playlists: "Playlists", suggestions: "Suggestions", search: "Search"
    })

    function navigate(key) {
        currentKey = key
        if (key === "albums")
            stack.replace(null, albumsPage)
        else if (key === "settings")
            stack.replace(null, settingsPage)
        else
            stack.replace(null, placeholderPage, { title: pageTitles[key] })
    }

    Component {
        id: albumsPage
        AlbumsPage {
            onOpenAlbum: album => stack.push(albumPage, { album: album })
        }
    }
    Component {
        id: albumPage
        AlbumPage {
            onBack: stack.pop()
        }
    }
    Component {
        id: settingsPage
        SettingsPage {}
    }
    Component {
        id: placeholderPage
        PlaceholderPage {}
    }

    // Panels sit flush; the 1px gaps let the window colour show as dividers.
    ColumnLayout {
        anchors.fill: parent
        spacing: 1

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 1

            Sidebar {
                Layout.preferredWidth: 200
                Layout.fillHeight: true
                currentKey: window.currentKey
                onNavigate: key => window.navigate(key)
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Theme.panel

                StackView {
                    id: stack
                    anchors.fill: parent
                    clip: true
                    initialItem: albumsPage

                    // Plain cross-fades; page slides feel heavy in a list-driven app.
                    pushEnter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 140 } }
                    pushExit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 80 } }
                    popEnter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 140 } }
                    popExit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 80 } }
                    replaceEnter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 140 } }
                    replaceExit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 80 } }
                }
            }

            QueuePanel {
                visible: window.queueOpen
                Layout.preferredWidth: 320
                Layout.fillHeight: true
            }
        }

        PlayerBar {
            Layout.fillWidth: true
            queueOpen: window.queueOpen
            onToggleQueue: window.queueOpen = !window.queueOpen
        }
    }

    // Development aid: `--demo-album` opens the first album and starts it,
    // so the detail page and the queue can be checked in a screenshot run.
    Component.onCompleted: {
        if (Qt.application.arguments.indexOf("--demo-settings") >= 0)
            navigate("settings")
        // The album list may already be there from the cache.
        tryDemo()
    }

    // `--demo-album`: once the library has loaded, open its first album.
    property bool demoDone: false
    function tryDemo() {
            if (window.demoDone || Library.albums.length === 0
                    || Qt.application.arguments.indexOf("--demo-album") < 0)
                return
            window.demoDone = true
            stack.push(albumPage, { album: Library.albums[0] })
            if (Qt.application.arguments.indexOf("--demo-play") >= 0)
                Library.loadAlbum(Library.albums[0].id)
    }
    Connections {
        target: Library
        function onAlbumsChanged() { window.tryDemo() }
    }

    // `--demo-play`: also start that album, to check real playback.
    Connections {
        target: Library
        function onAlbumLoaded(id, album) {
            if (Qt.application.arguments.indexOf("--demo-play") >= 0 && Player.queue.count === 0)
                Player.playAlbum(album, 0)
        }
    }

    LoginPage {
        anchors.fill: parent
        // Not while reconnecting with a saved key: that shows the cached library.
        visible: Session.state !== Session.Ready && !Session.restoring
        // Swallow clicks meant for the UI underneath.
        MouseArea { anchors.fill: parent; z: -1 }
    }

    Shortcut {
        sequence: "Space"
        onActivated: Player.toggle()
    }
}
