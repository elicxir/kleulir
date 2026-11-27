import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Kleulir

// The server's folders: the user's own shelves for albums. One page per folder;
// `folder` is null at the top.
Item {
    id: root
    property var folder: null         // { id, name }

    property var all: []              // every folder, flat
    property var albums: []
    property bool foldersLoaded: false
    property bool albumsLoaded: false

    readonly property string folderId: folder ? folder.id : ""
    readonly property var subfolders: all.filter(f => f.parentId === folderId)
                                       .sort((a, b) => a.sortOrder - b.sortOrder || a.name.localeCompare(b.name))
    // From the top down to this folder.
    readonly property var path: {
        const out = []
        let id = folderId
        for (let guard = 0; id !== "" && guard < 32; ++guard) {
            const found = all.find(f => f.id === id)
            if (!found)
                break
            out.unshift(found)
            id = found.parentId
        }
        return out
    }

    function request() {
        Library.loadFolders()
        albums = []
        albumsLoaded = folderId === ""
        if (folderId !== "")
            Library.loadFolder(folderId)
    }
    onFolderChanged: request()
    Component.onCompleted: request()

    Connections {
        target: Library
        function onFoldersLoaded(folders) {
            root.all = folders
            root.foldersLoaded = true
        }
        function onFolderLoaded(id, data) {
            if (id !== root.folderId)
                return
            root.albums = data.albums || []
            root.albumsLoaded = true
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: 20
        anchors.leftMargin: 24
        anchors.rightMargin: 8
        spacing: 14

        // Title, with the way back up in front of it.
        ColumnLayout {
            spacing: 2
            Row {
                visible: root.folder !== null
                spacing: 0
                IconButton {
                    text: "Folders"
                    labelSize: Theme.fontSmall
                    implicitHeight: 24
                    onClicked: Nav.openPage("folders")
                }
                Repeater {
                    model: root.path.slice(0, -1)
                    delegate: Row {
                        id: crumb
                        required property var modelData
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "/"
                            color: Theme.textFaint
                            font.pixelSize: Theme.fontSmall
                        }
                        IconButton {
                            text: crumb.modelData.name
                            labelSize: Theme.fontSmall
                            implicitHeight: 24
                            onClicked: Nav.go({ page: "folder", folder: crumb.modelData })
                        }
                    }
                }
            }
            RowLayout {
                spacing: 10
                Text {
                    text: root.folder ? root.folder.name : "Folders"
                    color: Theme.text
                    font.pixelSize: Theme.fontTitle
                    font.weight: Font.Bold
                    elide: Text.ElideRight
                    Layout.maximumWidth: root.width - 260
                }
                Text {
                    visible: root.foldersLoaded
                    text: {
                        const parts = []
                        if (root.subfolders.length > 0)
                            parts.push(root.subfolders.length + " folders")
                        if (root.folder && root.albumsLoaded)
                            parts.push(root.albums.length + " albums")
                        return parts.join(" · ")
                    }
                    color: Theme.textFaint
                    font.pixelSize: Theme.fontBody
                    Layout.alignment: Qt.AlignBaseline
                }
            }
        }

        Item {
            visible: root.foldersLoaded && root.albumsLoaded
                     && root.subfolders.length === 0 && root.albums.length === 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            Text {
                anchors.centerIn: parent
                text: root.folder ? "This folder is empty." : "The server has no folders yet."
                color: Theme.textFaint
                font.pixelSize: 14
            }
        }

        // The folders inside this one.
        Flow {
            visible: root.subfolders.length > 0
            Layout.fillWidth: true
            Layout.rightMargin: 16
            spacing: 8

            Repeater {
                model: root.subfolders
                delegate: AbstractButton {
                    id: tile
                    required property var modelData
                    implicitWidth: 240
                    implicitHeight: 52
                    hoverEnabled: true
                    onClicked: Nav.go({ page: "folder", folder: tile.modelData })
                    background: Rectangle {
                        color: tile.hovered ? Theme.hover : Theme.raised
                    }
                    contentItem: ColumnLayout {
                        spacing: 1
                        Text {
                            Layout.fillWidth: true
                            Layout.leftMargin: 12
                            Layout.rightMargin: 12
                            text: tile.modelData.name
                            color: Theme.text
                            font.pixelSize: 14
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            Layout.leftMargin: 12
                            Layout.rightMargin: 12
                            text: {
                                const parts = []
                                if (tile.modelData.childCount > 0)
                                    parts.push(tile.modelData.childCount + " folders")
                                parts.push(tile.modelData.albumCount + " albums")
                                return parts.join(" · ")
                            }
                            color: Theme.textDim
                            font.pixelSize: Theme.fontSmall
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }

        AlbumGrid {
            visible: root.albums.length > 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            albums: root.albums
        }
        Item {
            visible: root.albums.length === 0
            Layout.fillHeight: true
        }
    }
}
