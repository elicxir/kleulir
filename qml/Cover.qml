import QtQuick
import QtQuick.Effects
import QtQuick.Window
import Kleulir

// Cover art. Three looks, chosen so nothing flashes on the way to the picture:
// - art still loading: a plain dark tile
// - art loaded: the picture, faded in
// - no art (or it failed): a two-tone tile with the title's first letter
Item {
    id: root
    property string title: ""
    // Cover art id from the server; empty means the album has none.
    property string art: ""
    property int radius: 0
    property bool shadow: false

    readonly property real hue: Theme.coverHue(title)
    readonly property bool hasArt: art.length > 0 && image.status !== Image.Error
    readonly property bool loaded: image.status === Image.Ready

    // Ask for one of a few fixed sizes rather than the exact item size, so resizing
    // the window does not reload every cover and all places share cached files.
    readonly property int needed: Math.ceil(Math.max(width, height) * Screen.devicePixelRatio)
    readonly property int bucket: needed <= 96 ? 96 : needed <= 320 ? 320 : 640

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
        color: Theme.raised

        // Placeholder for albums without art.
        Rectangle {
            anchors.fill: parent
            radius: root.radius
            visible: !root.hasArt
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0; color: Qt.hsla(root.hue, 0.32, 0.44, 1) }
                GradientStop { position: 1; color: Qt.hsla(root.hue, 0.34, 0.26, 1) }
            }
            Text {
                anchors.centerIn: parent
                text: root.title.length > 0 ? root.title.charAt(0) : ""
                color: Qt.rgba(1, 1, 1, 0.7)
                font.pixelSize: Math.max(12, root.height * 0.38)
                font.weight: Font.DemiBold
            }
        }

        Image {
            id: image
            anchors.fill: parent
            // Wait for a real size, or the first request would use the wrong bucket.
            source: root.art.length > 0 && root.width > 0 ? "image://cover/" + root.art : ""
            sourceSize: Qt.size(root.bucket, root.bucket)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            opacity: root.loaded ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 120 } }
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
