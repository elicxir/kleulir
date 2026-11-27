import QtQuick
import QtQuick.Shapes

// Monochrome icon drawn from path data on a 24x24 grid, so it takes any
// colour and stays sharp at any scale without image files.
Item {
    id: root
    property string name: ""
    property color color: "white"
    property real size: 18

    implicitWidth: size
    implicitHeight: size

    readonly property var paths: ({
        play: "M8 5v14l11-7z",
        pause: "M6 5h4v14H6zM14 5h4v14h-4z",
        previous: "M6 6h2v12H6zM9.5 12l8.5 6V6z",
        next: "M16 6h2v12h-2zM6 18l8.5-6L6 6z",
        volume: "M3 9v6h4l5 5V4L7 9H3zM14 7.97v8.05c1.48-.73 2.5-2.25 2.5-4.02 0-1.77-1.02-3.29-2.5-4.03zM14 3.23v2.06c2.89.86 5 3.54 5 6.71s-2.11 5.85-5 6.71v2.06c4.01-.91 7-4.49 7-8.77s-2.99-7.86-7-8.77z",
        mute: "M3 9v6h4l5 5V4L7 9H3zM16 9.4L17.4 8l2.1 2.1L21.6 8 23 9.4l-2.1 2.1L23 13.6 21.6 15l-2.1-2.1L17.4 15 16 13.6l2.1-2.1z",
        queue: "M4 6h16v2H4zM4 11h16v2H4zM4 16h10v2H4z",
        search: "M10 4a6 6 0 1 0 3.7 10.7l4.8 4.8 1.4-1.4-4.8-4.8A6 6 0 0 0 10 4zm0 2a4 4 0 1 1 0 8 4 4 0 0 1 0-8z",
        device: "M7 3h10a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2zm5 3.5a1.5 1.5 0 1 0 0 3 1.5 1.5 0 0 0 0-3zm0 5.5a3.5 3.5 0 1 0 0 7 3.5 3.5 0 0 0 0-7z",
        add: "M11 5h2v6h6v2h-6v6h-2v-6H5v-2h6z",
        close: "M6.4 5L12 10.6 17.6 5 19 6.4 13.4 12 19 17.6 17.6 19 12 13.4 6.4 19 5 17.6 10.6 12 5 6.4z",
        up: "M12 8l6 6-1.4 1.4L12 10.8l-4.6 4.6L6 14z",
        down: "M12 16l-6-6 1.4-1.4L12 13.2l4.6-4.6L18 10z",
        back: "M14.6 6L16 7.4 11.4 12l4.6 4.6L14.6 18l-6-6z",
        playNext: "M4 6h10v2H4zM4 11h10v2H4zM4 16h6v2H4zM16 11v8l6-4z"
    })

    Shape {
        anchors.centerIn: parent
        width: 24
        height: 24
        scale: root.size / 24
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: "transparent"
            fillColor: root.color
            fillRule: ShapePath.OddEvenFill
            PathSvg { path: root.paths[root.name] || "" }
        }
    }
}
