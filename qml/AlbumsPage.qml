import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Kleulir

Item {
    id: root

    // "all" | "physical" | "virtual" — the same filter /ext/albums takes.
    property string kind: "all"
    // "name" (the server's reading order) | "artist" | "year" | "added"
    property string sort: "name"

    readonly property var shown: {
        const list = Library.albums.filter(a => kind === "all" || a.kind === kind)
        if (sort === "artist")
            list.sort((a, b) => a.artist.localeCompare(b.artist) || a.title.localeCompare(b.title))
        else if (sort === "year")
            list.sort((a, b) => b.year - a.year || a.title.localeCompare(b.title))
        else if (sort === "added")
            list.sort((a, b) => (b.created || "").localeCompare(a.created || ""))
        return list
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: 20
        anchors.leftMargin: 24
        anchors.rightMargin: 8
        spacing: 16

        RowLayout {
            Layout.fillWidth: true
            Layout.rightMargin: 16
            spacing: 10

            Text {
                text: "Albums"
                color: Theme.text
                font.pixelSize: Theme.fontTitle
                font.weight: Font.Bold
            }
            Text {
                text: Library.albums.length === 0 && Library.loading ? "Loading…"
                      : Library.error.length > 0 ? Library.error : root.shown.length + " albums"
                color: Theme.textFaint
                font.pixelSize: Theme.fontBody
                Layout.alignment: Qt.AlignBaseline
            }
            Item { Layout.fillWidth: true }

            Segmented {
                options: [
                    { key: "name", label: "Name" },
                    { key: "artist", label: "Artist" },
                    { key: "year", label: "Year" },
                    { key: "added", label: "Recently added" }
                ]
                current: root.sort
                onPicked: key => root.sort = key
            }
            Segmented {
                visible: Session.eosFeatures
                options: [
                    { key: "all", label: "All" },
                    { key: "physical", label: "Physical" },
                    { key: "virtual", label: "Virtual" }
                ]
                current: root.kind
                onPicked: key => root.kind = key
            }
        }

        AlbumGrid {
            Layout.fillWidth: true
            Layout.fillHeight: true
            albums: root.shown
        }
    }
}
