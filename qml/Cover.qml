import QtQuick
import QtQuick.Effects
import Kleulir

// Cover art. Until real art is wired in (`source` takes the getCoverArt URL)
// it draws a two-tone tile with the title's first letter.
Item {
    id: root
    property string title: ""
    property url source
    property int radius: 0
    property bool shadow: false

    readonly property real hue: Theme.coverHue(title)

    RectangularShadow {
        visible: root.shadow
        anchors.fill: tile
        offset.y: 4
        blur: 18
        spread: -2
        radius: root.radius
        color: Qt.rgba(0, 0, 0, 0.55)
    }

    Rectangle {
        id: tile
        anchors.fill: parent
        radius: root.radius
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0; color: Qt.hsla(root.hue, 0.32, 0.44, 1) }
            GradientStop { position: 1; color: Qt.hsla(root.hue, 0.34, 0.26, 1) }
        }

        Text {
            anchors.centerIn: parent
            visible: image.status !== Image.Ready
            text: root.title.length > 0 ? root.title.charAt(0) : ""
            color: Qt.rgba(1, 1, 1, 0.7)
            font.pixelSize: Math.max(12, root.height * 0.38)
            font.weight: Font.DemiBold
        }

        Image {
            id: image
            anchors.fill: parent
            source: root.source
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: width
            sourceSize.height: height
        }

        // Thin light edge so the tile reads as a surface, not a flat block.
        Rectangle {
            anchors.fill: parent
            radius: root.radius
            color: "transparent"
            border.color: Qt.rgba(1, 1, 1, 0.08)
            border.width: 1
        }
    }
}
