import QtQuick
import QtQuick.Controls.Basic
import Kleulir

// One horizontal row of album covers (search results, starred albums).
ListView {
    id: row
    property var albums: []

    implicitHeight: 196
    orientation: ListView.Horizontal
    spacing: 16
    clip: true
    model: albums
    boundsBehavior: Flickable.StopAtBounds

    delegate: Item {
        id: card
        required property var modelData
        width: 140
        height: row.height

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
