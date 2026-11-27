pragma Singleton
import QtCore
import QtQuick

QtObject {
    id: root

    // Neutral grey surfaces, darkest to lightest. Panels sit flush and are
    // separated by `line`, not by gaps or rounding.
    readonly property color bg: "#1a1a1a"
    readonly property color panel: "#212121"
    readonly property color raised: "#2b2b2b"
    readonly property color hover: "#343434"
    readonly property color line: "#383838"

    // Text
    readonly property color text: "#ededed"
    readonly property color textDim: "#a6a6a6"
    readonly property color textFaint: "#737373"

    // Accent: user-chosen, stored with the app settings. Default is jade (翡翠色).
    readonly property color defaultAccent: "#38b48b"
    property Settings store: Settings {
        category: "appearance"
        property color accent: root.defaultAccent
    }
    readonly property color accent: store.accent
    readonly property color accentStrong: Qt.lighter(accent, 1.18)
    readonly property color accentDim: Qt.darker(accent, 1.5)
    // Text and icons drawn on top of the accent colour.
    readonly property color onAccent: accent.hslLightness > 0.5 ? "#101010" : "#ffffff"

    function setAccent(color) {
        store.accent = color
    }

    readonly property var accentPresets: [
        { name: "Jade", color: "#38b48b" },
        { name: "Celadon", color: "#7ebeab" },
        { name: "Teal", color: "#00a3af" },
        { name: "Lapis", color: "#4a7fd0" },
        { name: "Wisteria", color: "#a59aca" },
        { name: "Madder", color: "#c8505a" },
        { name: "Amber", color: "#f0a530" },
        { name: "Grey", color: "#9a9a9a" }
    ]

    readonly property color estimated: "#d9a955"

    readonly property int radius: 2
    readonly property int panelRadius: 0
    readonly property int gap: 8
    readonly property int pad: 16

    readonly property int fontSmall: 12
    readonly property int fontBody: 13
    readonly property int fontTitle: 22

    // "3:07" from seconds
    function time(seconds) {
        const s = Math.max(0, Math.floor(seconds))
        const m = Math.floor(s / 60)
        const r = s % 60
        return m + ":" + (r < 10 ? "0" + r : r)
    }

    // Stable placeholder hue for a cover, derived from its title
    function coverHue(title) {
        let h = 0
        for (let i = 0; i < title.length; ++i)
            h = (h * 31 + title.charCodeAt(i)) % 360
        return h / 360
    }
}
