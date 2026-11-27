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
        open: "M5 5h6v2H7v10h10v-4h2v6H5zM13 5h6v6h-2V8.4l-5.3 5.3-1.4-1.4L15.6 7H13z",
        forward: "M9.4 6L8 7.4l4.6 4.6L8 16.6 9.4 18l6-6z",
        more: "M6 10a2 2 0 1 0 0 4 2 2 0 0 0 0-4zm6 0a2 2 0 1 0 0 4 2 2 0 0 0 0-4zm6 0a2 2 0 1 0 0 4 2 2 0 0 0 0-4z",
        heart: "M12 21l-1.5-1.3C5.4 15.4 2 12.3 2 8.5 2 5.4 4.4 3 7.5 3c1.7 0 3.4.8 4.5 2.1C13.1 3.8 14.8 3 16.5 3 19.6 3 22 5.4 22 8.5c0 3.8-3.4 6.9-8.5 11.2z",
        heartOutline: "M16.5 3c-1.74 0-3.41.81-4.5 2.09C10.91 3.81 9.24 3 7.5 3 4.42 3 2 5.42 2 8.5c0 3.78 3.4 6.86 8.55 11.54L12 21.35l1.45-1.32C18.6 15.36 22 12.28 22 8.5 22 5.42 19.58 3 16.5 3zm-4.4 15.55l-.1.1-.1-.1C7.14 14.24 4 11.39 4 8.5 4 6.5 5.5 5 7.5 5c1.54 0 3.04.99 3.57 2.36h1.87C13.46 5.99 14.96 5 16.5 5c2 0 3.5 1.5 3.5 3.5 0 2.89-3.14 5.74-7.9 10.05z",
        shuffle: "M10.59 9.17L5.41 4 4 5.41l5.17 5.17 1.42-1.41zM14.5 4l2.04 2.04L4 18.59 5.41 20 17.96 7.46 20 9.5V4h-5.5zm.33 9.41l-1.41 1.41 3.13 3.13L14.5 20H20v-5.5l-2.04 2.04-3.13-3.13z",
        repeat: "M7 7h10v3l4-4-4-4v3H5v6h2V7zm10 10H7v-3l-4 4 4 4v-3h12v-6h-2v4z",
        repeatOne: "M7 7h10v3l4-4-4-4v3H5v6h2V7zm10 10H7v-3l-4 4 4 4v-3h12v-6h-2v4zm-4-2V9h-1l-2 1v1h1.5v4H13z",
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
