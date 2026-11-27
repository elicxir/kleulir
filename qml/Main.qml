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
    // The screenshot hook always wants the window.
    visible: !(App.closeToTray && App.startInTray)
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
    function render() {
        const entry = Nav.current
        if (entry.page === "album")
            stack.replace(null, albumPage, { album: entry.album })
        else if (entry.page === "settings")
            stack.replace(null, settingsPage)
        else if (entry.page === "search")
            stack.replace(null, searchPage)
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

    // `--demo-play`: also start that album, to check real playback.
    Connections {
        target: Library
        function onAlbumLoaded(id, album) {
            if (Qt.application.arguments.indexOf("--demo-play") >= 0 && Player.queue.count === 0)
                Player.playAlbum(album, 0)
        }
    }

    // The mouse's back and forward buttons, anywhere in the window.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.BackButton | Qt.ForwardButton
        onClicked: mouse => mouse.button === Qt.BackButton ? Nav.back() : Nav.forward()
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
