pragma Singleton
import QtQuick

QtObject {
    // Surfaces
    readonly property color bg: "#15171a"
    readonly property color panel: "#1c1f23"
    readonly property color raised: "#25292e"
    readonly property color hover: "#2c3137"
    readonly property color line: "#30353b"

    // Text
    readonly property color text: "#e8eaed"
    readonly property color textDim: "#9aa1a9"
    readonly property color textFaint: "#6b727a"

    // Accent and status
    readonly property color accent: "#6fb3a8"
    readonly property color accentDim: "#3d6a63"
    readonly property color estimated: "#c9a35a"

    readonly property int radius: 6
    readonly property int gap: 8
    readonly property int pad: 16

    readonly property int fontSmall: 12
    readonly property int fontBody: 13
    readonly property int fontTitle: 20

    // "3:07" from seconds
    function time(seconds) {
        const s = Math.max(0, Math.floor(seconds))
        const m = Math.floor(s / 60)
        const r = s % 60
        return m + ":" + (r < 10 ? "0" + r : r)
    }

    // Stable placeholder colour for a cover, derived from its title
    function coverColor(title) {
        let h = 0
        for (let i = 0; i < title.length; ++i)
            h = (h * 31 + title.charCodeAt(i)) % 360
        return Qt.hsla(h / 360, 0.35, 0.32, 1)
    }
}
