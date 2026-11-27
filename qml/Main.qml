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
    color: Theme.bg

    property string currentKey: "albums"
    property bool queueOpen: true

    readonly property var pageTitles: ({
        artists: "アーティスト", genres: "ジャンル", folders: "フォルダ", works: "作品",
        starred: "お気に入り", playlists: "プレイリスト", suggestions: "候補の承認", search: "検索"
    })

    function navigate(key) {
        currentKey = key
        if (key === "albums")
            stack.replace(null, albumsPage)
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
        id: placeholderPage
        PlaceholderPage {}
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            Sidebar {
                Layout.preferredWidth: 200
                Layout.fillHeight: true
                currentKey: window.currentKey
                onNavigate: key => window.navigate(key)
            }

            StackView {
                id: stack
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                initialItem: albumsPage

                // Plain cross-fades; page slides feel heavy in a list-driven app.
                pushEnter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 120 } }
                pushExit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 80 } }
                popEnter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 120 } }
                popExit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 80 } }
                replaceEnter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 120 } }
                replaceExit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 80 } }
            }

            QueuePanel {
                visible: window.queueOpen
                Layout.preferredWidth: 300
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
        if (Qt.application.arguments.indexOf("--demo-album") >= 0) {
            const album = MockData.albums[0]
            stack.push(albumPage, { album: album })
            Player.playAlbum(album, 2)
        }
    }

    Shortcut {
        sequence: "Space"
        onActivated: Player.toggle()
    }
}
