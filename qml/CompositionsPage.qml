import QtQuick
import Kleulir

// Compositions: each piece of music once, however many recordings of it there are.
IndexPage {
    id: root
    title: "Compositions"
    unit: "compositions"
    emptyText: "The server has no compositions yet."
    onOpened: item => Nav.go({ page: "composition", composition: item })

    Component.onCompleted: Library.loadCompositions()
    Connections {
        target: Library
        function onCompositionsLoaded(compositions) {
            root.items = compositions.map(c => ({ id: c.id, name: c.name, detail: c.composers }))
            root.loaded = true
        }
    }
}
