import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Qt.labs.platform as Platform
import Kleulir

ApplicationWindow {
    id: window
    width: 1280
    height: 800
    minimumWidth: 960
    minimumHeight: 600
    // Starting kleulir opens its window. Only `--hidden` (how it is started with
    // Windows) keeps it in the tray, and only when the tray is in use at all.
    // The screenshot hook always wants the window.
    visible: !(App.closeToTray && Qt.application.arguments.indexOf("--hidden") >= 0)
             || Qt.application.arguments.some(a => a.startsWith("--demo-"))
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

    // Closing quits, unless kleulir is set to live in the tray.
    //
    // Qt asks every window to close when the app is told to quit, and a window that
    // refuses cancels the quit. So "hide instead of close" must not apply once a
    // real quit is under way, or Quit would do nothing.
    property bool quitting: false
    function quitApp() {
        quitting = true
        Qt.quit()
    }
    onClosing: close => {
        if (App.closeToTray && !quitting) {
            close.accepted = false
            window.hide()
        } else {
            quitApp()
        }
    }

    function bringToFront() {
        if (window.visibility === Window.Minimized)
            window.showNormal()
        else
            window.show()
        window.raise()
        window.requestActivate()
    }

    // kleulir was launched again while this one is running.
    Connections {
        target: App
        function onActivationRequested() { window.bringToFront() }
    }

    Timer {
        id: hideShowTimer
        property int step: 0
        interval: 800
        repeat: true
        onTriggered: {
            ++step
            if (step === 1) window.hide()
            else if (step === 2) { window.bringToFront(); stop() }
        }
    }

    Platform.SystemTrayIcon {
        id: tray
        visible: App.closeToTray
        icon.source: "qrc:/qt/qml/Kleulir/assets/kleulir.svg"
        tooltip: Player.current ? Player.current.title + " — " + Player.current.artist : "kleulir"
        // Click (single or double): the main window, as in Spotify or Discord.
        // Right click: the menu, drawn by Windows, so it lands in the right place
        // on any monitor.
        onActivated: reason => {
            if (reason !== Platform.SystemTrayIcon.Context)
                window.bringToFront()
        }
        menu: Platform.Menu {
            Platform.MenuItem {
                text: window.visible ? "Hide window" : "Show kleulir"
                onTriggered: window.visible ? window.hide() : window.bringToFront()
            }
            Platform.MenuSeparator {}
            Platform.MenuItem {
                text: Player.playing ? "Pause" : "Play"
                enabled: Player.current !== null
                onTriggered: Player.toggle()
            }
            Platform.MenuItem {
                text: "Next"
                enabled: Player.current !== null
                onTriggered: Player.next()
            }
            Platform.MenuItem {
                text: "Previous"
                enabled: Player.current !== null
                onTriggered: Player.previous()
            }
            Platform.MenuSeparator {}
            Platform.MenuItem {
                text: "Quit"
                onTriggered: window.quitApp()
            }
        }
    }

    property bool queueOpen: true

    // The album grid stays alive (so it keeps its scroll position); the other pages
    // are built when Nav moves to them.
    Component {
        id: albumPage
        AlbumPage {}
    }
    Component {
        id: settingsPage
        SettingsPage {}
    }
    Component {
        id: searchPage
        SearchPage {}
    }
    Component {
        id: starredPage
        StarredPage {}
    }
    Component {
        id: artistsPage
        ArtistsPage {}
    }
    Component {
        id: artistPage
        ArtistPage {}
    }
    Component {
        id: playlistsPage
        PlaylistsPage {}
    }
    Component {
        id: playlistPage
        PlaylistPage {}
    }
    Component {
        id: foldersPage
        FoldersPage {}
    }
    Component {
        id: worksPage
        WorksPage {}
    }
    Component {
        id: workPage
        WorkPage {}
    }
    Component {
        id: compositionsPage
        CompositionsPage {}
    }
    Component {
        id: compositionPage
        CompositionPage {}
    }
    Component {
        id: graphPage
        GraphPage {}
    }
    function render() {
        const entry = Nav.current
        if (entry.page === "album")
            stack.replace(null, albumPage, { album: entry.album })
        else if (entry.page === "settings")
            stack.replace(null, settingsPage)
        else if (entry.page === "search")
            stack.replace(null, searchPage)
        else if (entry.page === "starred")
            stack.replace(null, starredPage)
        else if (entry.page === "artists")
            stack.replace(null, artistsPage)
        else if (entry.page === "artist")
            stack.replace(null, artistPage, { artist: entry.artist })
        else if (entry.page === "playlists")
            stack.replace(null, playlistsPage)
        else if (entry.page === "playlist")
            stack.replace(null, playlistPage, { playlist: entry.playlist })
        else if (entry.page === "folders")
            stack.replace(null, foldersPage)
        else if (entry.page === "folder")
            stack.replace(null, foldersPage, { folder: entry.folder })
        else if (entry.page === "works")
            stack.replace(null, worksPage)
        else if (entry.page === "work")
            stack.replace(null, workPage, { work: entry.work })
        else if (entry.page === "compositions")
            stack.replace(null, compositionsPage)
        else if (entry.page === "composition")
            stack.replace(null, compositionPage, { composition: entry.composition })
        else if (entry.page === "versions")
            stack.replace(null, compositionPage, { song: entry.song })
        else if (entry.page === "graph")
            stack.replace(null, graphPage, { seed: entry.seed, seedLabel: entry.label || "", mode: entry.mode || "related" })
        else
            stack.clear()
    }
    Connections {
        target: Nav
        function onCurrentChanged() { window.render() }
    }

    Shortcut {
        sequences: ["Alt+Left", StandardKey.Back]
        onActivated: Nav.back()
    }
    Shortcut {
        sequences: ["Alt+Right", StandardKey.Forward]
        onActivated: Nav.forward()
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
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Theme.panel

                AlbumsPage {
                    anchors.fill: parent
                    visible: Nav.current.page === "albums"
                }

                StackView {
                    id: stack
                    anchors.fill: parent
                    clip: true
                    visible: Nav.current.page !== "albums"

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
            Nav.openPage("settings")
        // `--demo-page=<name>`: open that page (starred, artists, playlists).
        const demoPage = Qt.application.arguments.find(a => a.startsWith("--demo-page="))
        if (demoPage)
            Nav.openPage(demoPage.substring(12))
        // `--demo-graph=<seed>[,similar]`: open the graph around that node, e.g. song:<id>.
        const demoGraph = Qt.application.arguments.find(a => a.startsWith("--demo-graph="))
        if (demoGraph) {
            const parts = demoGraph.substring(13).split(",")
            Nav.go({ page: "graph", seed: parts[0], label: "", mode: parts[1] || "related" })
        }
        // `--demo-search=<text>`: open the search page with that text.
        const demoSearch = Qt.application.arguments.find(a => a.startsWith("--demo-search="))
        if (demoSearch)
            Nav.search(demoSearch.substring(14))
        // `--demo-hide-show`: hide to the tray and come back, as a tray click would.
        if (Qt.application.arguments.indexOf("--demo-hide-show") >= 0) {
            hideShowTimer.start()
        }
        // The album list may already be there from the cache.
        tryDemo()
    }

    // `--demo-album`: once the library has loaded, open its first album.
    property bool demoDone: false
    property bool demoPlayed: false
    function tryDemo() {
            if (window.demoDone || Library.albums.length === 0
                    || Qt.application.arguments.indexOf("--demo-album") < 0)
                return
            window.demoDone = true
            Nav.openAlbum(Library.albums[0])
            if (Qt.application.arguments.indexOf("--demo-play") >= 0)
                Library.loadAlbum(Library.albums[0].id)
    }
    Connections {
        target: Library
        function onAlbumsChanged() { window.tryDemo() }
    }

    // `--demo-gapless`: jump close to the end of the first track, to watch the
    // change to the second one.
    Timer {
        interval: 2500
        running: Qt.application.arguments.indexOf("--demo-gapless") >= 0 && Player.playing && Player.currentIndex === 0
        onTriggered: Player.seek(Player.duration - 5)
    }

    // `--demo-play`: also start that album, to check real playback.
    Connections {
        target: Library
        function onAlbumLoaded(id, album) {
            if (Qt.application.arguments.indexOf("--demo-play") >= 0 && !window.demoPlayed) {
                window.demoPlayed = true
                Player.playAlbum(album, 0)
            }
        }
    }

    // The mouse's back and forward buttons, anywhere in the window.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.BackButton | Qt.ForwardButton
        onClicked: mouse => mouse.button === Qt.BackButton ? Nav.back() : Nav.forward()
    }

    // A call to the server failed: say so, briefly, instead of showing nothing.
    Rectangle {
        id: toast
        property string message: ""
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 100
        width: Math.min(toastText.implicitWidth + 32, parent.width - 80)
        height: toastText.implicitHeight + 20
        radius: 6
        color: Theme.raised
        border.color: Theme.line
        opacity: toastTimer.running ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 160 } }

        Text {
            id: toastText
            anchors.centerIn: parent
            width: Math.min(implicitWidth, toast.parent.width - 112)
            text: toast.message
            color: Theme.text
            font.pixelSize: Theme.fontBody
            elide: Text.ElideRight
        }
        Timer {
            id: toastTimer
            interval: 4000
        }
        Connections {
            target: Library
            function onProblem(message) {
                toast.message = message
                toastTimer.restart()
            }
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
