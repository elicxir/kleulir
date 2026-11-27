import QtQuick
import Kleulir

// Cover art placeholder: a tinted tile with the title's first letter.
// `source` will take the getCoverArt URL once the library is wired in.
Rectangle {
    id: root
    property string title: ""
    property url source

    radius: Theme.radius
    color: Theme.coverColor(title)
    clip: true

    Text {
        anchors.centerIn: parent
        visible: image.status !== Image.Ready
        text: root.title.length > 0 ? root.title.charAt(0) : ""
        color: Qt.rgba(1, 1, 1, 0.55)
        font.pixelSize: Math.max(12, root.height * 0.4)
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
}
