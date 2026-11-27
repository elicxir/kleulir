pragma Singleton
import QtQuick

// Placeholder library so the screens can be built before libeos exists.
// Shapes follow the server: a track carries the work ("title" in /ext terms)
// it belongs to, and whether that link is an estimate.
QtObject {
    readonly property var albums: [
        {
            id: "al1", title: "Harbor Lights Collection", artist: "Various Artists",
            year: 2019, kind: "physical",
            tracks: [
                { id: "t1", title: "Opening Tide", artist: "M. Sato", duration: 184, work: "Harbor Lights", estimated: false },
                { id: "t2", title: "Lantern Street", artist: "M. Sato", duration: 213, work: "Harbor Lights", estimated: false },
                { id: "t3", title: "Opening Tide (Piano Ver.)", artist: "K. Arai", duration: 201, work: "Harbor Lights", estimated: true },
                { id: "t4", title: "Signal Fire", artist: "R. Honda", duration: 167, work: "Harbor Lights II", estimated: false },
                { id: "t5", title: "Night Ferry", artist: "R. Honda", duration: 242, work: "Harbor Lights II", estimated: false },
                { id: "t6", title: "Bonus: Demo Reel", artist: "M. Sato", duration: 95, work: "", estimated: false }
            ]
        },
        {
            id: "al2", title: "Glass Orchard OST", artist: "Y. Kimura",
            year: 2021, kind: "physical",
            tracks: [
                { id: "t7", title: "First Frost", artist: "Y. Kimura", duration: 156, work: "Glass Orchard", estimated: false },
                { id: "t8", title: "Orchard Theme", artist: "Y. Kimura", duration: 228, work: "Glass Orchard", estimated: false },
                { id: "t9", title: "Orchard Theme (TV Size)", artist: "Y. Kimura", duration: 91, work: "Glass Orchard", estimated: true }
            ]
        },
        {
            id: "al3", title: "Harbor Lights II (Selection)", artist: "R. Honda",
            year: 2019, kind: "virtual",
            tracks: [
                { id: "t4", title: "Signal Fire", artist: "R. Honda", duration: 167, work: "Harbor Lights II", estimated: false },
                { id: "t5", title: "Night Ferry", artist: "R. Honda", duration: 242, work: "Harbor Lights II", estimated: false }
            ]
        },
        {
            id: "al4", title: "Paper Kites", artist: "Trio Minato",
            year: 2016, kind: "physical",
            tracks: [
                { id: "t10", title: "Paper Kites", artist: "Trio Minato", duration: 305, work: "", estimated: false },
                { id: "t11", title: "Low Tide Waltz", artist: "Trio Minato", duration: 274, work: "", estimated: false }
            ]
        },
        {
            id: "al5", title: "Winter Arcade", artist: "H. Mori",
            year: 2023, kind: "physical",
            tracks: [
                { id: "t12", title: "Coin Drop", artist: "H. Mori", duration: 132, work: "Winter Arcade", estimated: false },
                { id: "t13", title: "Stage Select", artist: "H. Mori", duration: 118, work: "Winter Arcade", estimated: false },
                { id: "t14", title: "Final Round", artist: "H. Mori", duration: 249, work: "Winter Arcade", estimated: false }
            ]
        }
    ]

    // What a plain OpenSubsonic server would not offer. Screens read this
    // to hide eos-only entries; the real value will come from /ext/info.
    property bool eosFeatures: true

    readonly property var devices: [
        { id: "d1", name: "このPC", online: true },
        { id: "d2", name: "Pi Zero（リビング）", online: true },
        { id: "d3", name: "Ubuntuデスクトップ", online: false }
    ]
}
