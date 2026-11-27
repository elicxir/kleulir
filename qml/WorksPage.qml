import QtQuick
import Kleulir

// Works: the games, films and shows the music belongs to (the server's "titles").
IndexPage {
    id: root
    title: "Works"
    unit: "works"
    emptyText: "The server has no works yet."
    onOpened: item => Nav.go({ page: "work", work: item })

    Component.onCompleted: Library.loadWorks()
    Connections {
        target: Library
        function onWorksLoaded(works) {
            root.items = works.map(w => ({
                id: w.id, name: w.name, count: w.songCount,
                detail: [w.kind, w.year > 0 ? w.year : ""].filter(x => x !== "").join(" · ")
            }))
            root.loaded = true
        }
    }
}
