import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Kleulir

// What one song (or composition, work, ...) is linked to, drawn as a graph.
//   Related:      the composition and the work it belongs to, and their other songs
//   Sure links:   the same, keeping only the links MusicBrainz (or a tag or a person) backs
//   Sounds alike: the songs whose audio is closest (when the server has similarity)
// The layout is a small force simulation: linked nodes pull together, all nodes push
// apart, the centre stays put. Wheel to zoom, drag the background to pan, click a node
// for its details, double-click a song to play it or anything else to expand it.
// Expanding a node adds its neighbours to the graph on screen; "Centre here" starts afresh.
Item {
    id: root
    property string seed: ""         // node id, e.g. "song:abc"
    property string seedLabel: ""
    property string mode: "related"  // related | sure | similar

    property var nodes: []
    property var edges: []
    property string error: ""
    property bool loading: false
    property bool truncated: false
    property string selected: ""
    property var expanding: ({})     // node id -> true while its neighbours load

    // Positions live in a plain array (world coordinates, centre at 0,0); `revision`
    // tells the bindings when they moved.
    property var pos: []
    property int revision: 0
    property var indexOf: ({})
    property real zoom: 1
    property real panX: 0
    property real panY: 0

    readonly property bool canSimilar: Session.serverFeatures.indexOf("similarity") >= 0 && seed.startsWith("song:")

    function request() {
        if (!seed)
            return
        loading = true
        error = ""
        expanding = {}
        Library.loadGraph(seed, mode)
    }

    // Adds `node`'s neighbourhood to the graph on screen.
    function expand(node) {
        if (!node || expanding[node.id])
            return
        const e = Object.assign({}, expanding)
        e[node.id] = true
        expanding = e
        error = ""
        Library.loadGraph(node.id, mode)
    }
    // Seed and mode arrive one after the other when the page opens: ask once.
    onSeedChanged: Qt.callLater(request)
    onModeChanged: Qt.callLater(request)
    Component.onCompleted: Qt.callLater(request)

    function centreOn(node) {
        Nav.go({ page: "graph", seed: node.id, label: node.label,
                 mode: node.type === "song" || root.mode !== "similar" ? root.mode : "related" })
    }

    function nodeById(id) {
        const i = indexOf[id]
        return i === undefined ? null : nodes[i]
    }

    Connections {
        target: Library
        function onGraphLoaded(seed, mode, data) {
            if (mode !== root.mode)
                return
            if (root.expanding[seed]) {
                const e = Object.assign({}, root.expanding)
                delete e[seed]
                root.expanding = e
                if (data.error)
                    root.error = data.error
                else
                    root.merge(seed, data.nodes || [], data.edges || [])
                return
            }
            if (seed !== root.seed)
                return
            root.loading = false
            root.error = data.error || ""
            root.truncated = !!data.truncated
            root.place(data.nodes || [], data.edges || [])
        }
    }

    // ---- layout --------------------------------------------------------------------

    property int step: 0
    readonly property int steps: 320

    function place(newNodes, newEdges) {
        const index = {}
        newNodes.forEach((n, i) => index[n.id] = i)
        // Start on rings by distance, so the simulation only has to tidy up.
        const rings = {}
        newNodes.forEach(n => (rings[n.distance] = (rings[n.distance] || 0) + 1))
        const seen = {}
        const p = newNodes.map(n => {
            const k = seen[n.distance] = (seen[n.distance] || 0) + 1
            const a = 2 * Math.PI * k / rings[n.distance] + n.distance * 0.7
            const r = n.distance * 150
            return { x: r * Math.cos(a), y: r * Math.sin(a), dx: 0, dy: 0 }
        })
        indexOf = index
        pos = p
        nodes = newNodes
        edges = newEdges.filter(e => index[e.from] !== undefined && index[e.to] !== undefined)
        selected = nodes.length > 0 ? nodes[0].id : ""
        zoom = 1
        panX = 0
        panY = 0
        step = 0
        if (nodes.length > 1)
            ticker.start()
        revision++
    }

    // The same link found from either end: undirected ones are keyed with their ends sorted.
    function edgeKey(e) {
        const ends = e.directed || e.from < e.to ? [e.from, e.to] : [e.to, e.from]
        return ends.concat([e.type, e.label || ""]).join("|")
    }

    // Adds an expansion around `anchorId`: the nodes already there stay where they are, the
    // new ones start on an arc around the anchor, opening away from the centre.
    function merge(anchorId, newNodes, newEdges) {
        const a = indexOf[anchorId]
        if (a === undefined)
            return
        const index = Object.assign({}, indexOf)
        const list = nodes.slice()
        const p = pos
        const ax = p[a].x, ay = p[a].y
        const added = newNodes.filter(n => index[n.id] === undefined)
        const atCentre = Math.abs(ax) + Math.abs(ay) < 1
        const base = Math.atan2(ay, ax)
        added.forEach((n, k) => {
            const ang = atCentre ? 2 * Math.PI * k / added.length
                      : added.length === 1 ? base : base - 1.3 + 2.6 * k / (added.length - 1)
            const r = 100 + 80 * Math.max(0, n.distance - 1)
            index[n.id] = list.length
            list.push(n)
            p.push({ x: ax + r * Math.cos(ang), y: ay + r * Math.sin(ang), dx: 0, dy: 0 })
        })
        // A node is expanded once any answer had all its neighbours; the anchor now has.
        for (const n of newNodes) {
            const i = index[n.id]
            if ((n.expanded || n.id === anchorId) && !list[i].expanded)
                list[i] = Object.assign({}, list[i], { expanded: true })
        }
        const seen = {}
        for (const e of edges)
            seen[edgeKey(e)] = true
        const es = edges.slice()
        for (const e of newEdges) {
            const k = edgeKey(e)
            if (index[e.from] !== undefined && index[e.to] !== undefined && !seen[k]) {
                seen[k] = true
                es.push(e)
            }
        }
        indexOf = index
        pos = p
        nodes = list
        edges = es
        selected = anchorId
        // Settle gently: the layout on screen should mostly stay as it was.
        if (added.length > 0) {
            step = steps - 160
            ticker.start()
        }
        revision++
    }

    function relax(iterations) {
        const n = pos.length
        // The length an edge settles at. Similar songs are linked to each other as well
        // as to the centre, so they get more room and the side links pull less.
        const similar = mode === "similar"
        const k = similar ? 170 : 110
        const side = similar ? 0.25 : 1
        for (let it = 0; it < iterations && step < steps; ++it, ++step) {
            const t = 40 * (1 - step / steps) + 1  // how far a node may move this step
            for (let i = 0; i < n; ++i) {
                pos[i].dx = -pos[i].x * 0.015      // a little pull to the centre
                pos[i].dy = -pos[i].y * 0.015
            }
            for (let i = 0; i < n; ++i) {
                for (let j = i + 1; j < n; ++j) {
                    let dx = pos[i].x - pos[j].x, dy = pos[i].y - pos[j].y
                    let d2 = dx * dx + dy * dy
                    if (d2 < 1) { dx = Math.random() - 0.5; dy = Math.random() - 0.5; d2 = 1 }
                    const f = k * k / d2
                    pos[i].dx += dx * f; pos[i].dy += dy * f
                    pos[j].dx -= dx * f; pos[j].dy -= dy * f
                }
            }
            for (const e of edges) {
                const a = pos[indexOf[e.from]], b = pos[indexOf[e.to]]
                const dx = b.x - a.x, dy = b.y - a.y
                const d = Math.sqrt(dx * dx + dy * dy) + 0.01
                const f = d / k * (e.from === seed || e.to === seed ? 1 : side)
                a.dx += dx * f; a.dy += dy * f
                b.dx -= dx * f; b.dy -= dy * f
            }
            for (let i = 1; i < n; ++i) {  // node 0 is the seed: it stays in the middle
                const d = Math.sqrt(pos[i].dx * pos[i].dx + pos[i].dy * pos[i].dy) + 0.01
                const m = Math.min(d, t)
                pos[i].x += pos[i].dx / d * m
                pos[i].y += pos[i].dy / d * m
            }
        }
        revision++
    }

    Timer {
        id: ticker
        interval: 16
        repeat: true
        onTriggered: {
            root.relax(8)
            if (root.step >= root.steps) {
                stop()
                root.fit()
            }
        }
    }

    // Zoom and pan so that every node is in view below the header (never above 1:1).
    function fit() {
        if (pos.length < 2)
            return
        let x0 = Infinity, x1 = -Infinity, y0 = Infinity, y1 = -Infinity
        for (const p of pos) {
            x0 = Math.min(x0, p.x); x1 = Math.max(x1, p.x)
            y0 = Math.min(y0, p.y); y1 = Math.max(y1, p.y)
        }
        const top = headerBar.height + 24, bottom = 48, margin = 110  // half a label each side
        const w = view.width - 2 * margin, h = view.height - top - bottom - 30
        const z = Math.max(0.3, Math.min(1, w / Math.max(1, x1 - x0), h / Math.max(1, y1 - y0)))
        zoom = z
        panX = -(x0 + x1) / 2 * z
        panY = top + h / 2 + 15 - view.height / 2 - (y0 + y1) / 2 * z
    }

    function screenX(i) { return view.width / 2 + panX + pos[i].x * zoom }
    function screenY(i) { return view.height / 2 + panY + pos[i].y * zoom }

    function typeColor(type) {
        if (type === "song") return Theme.raised
        if (type === "composition") return Theme.accentDim
        if (type === "title") return "#2f4a72"
        if (type === "artist") return "#4d4766"
        if (type === "album") return "#5a4a30"
        return Theme.hover
    }
    function typeName(type) {
        return { song: "Song", composition: "Composition", title: "Work", artist: "Person", album: "Album" }[type] || type
    }

    // ---- view ----------------------------------------------------------------------

    Item {
        id: view
        anchors.fill: parent
        clip: true

        // Background: pan by dragging, zoom with the wheel around the cursor.
        DragHandler {
            id: pan
            target: null
            property real startX: 0
            property real startY: 0
            onActiveChanged: if (active) { startX = root.panX; startY = root.panY }
            onTranslationChanged: if (active) {
                root.panX = startX + translation.x
                root.panY = startY + translation.y
            }
        }
        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => {
                const old = root.zoom
                const z = Math.max(0.3, Math.min(3, old * Math.pow(1.0015, event.angleDelta.y)))
                // Keep the point under the cursor where it is.
                const cx = event.x - view.width / 2, cy = event.y - view.height / 2
                root.panX = cx - (cx - root.panX) * z / old
                root.panY = cy - (cy - root.panY) * z / old
                root.zoom = z
            }
        }
        TapHandler {
            onTapped: root.selected = ""
        }

        Canvas {
            id: lines
            anchors.fill: parent
            property int revision: root.revision
            property real zoom: root.zoom
            property real panX: root.panX
            property real panY: root.panY
            property string selected: root.selected
            onRevisionChanged: requestPaint()
            onZoomChanged: requestPaint()
            onPanXChanged: requestPaint()
            onPanYChanged: requestPaint()
            onSelectedChanged: requestPaint()
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()

            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                for (const e of root.edges) {
                    const a = root.indexOf[e.from], b = root.indexOf[e.to]
                    if (a === undefined || b === undefined)
                        continue
                    const x1 = root.screenX(a), y1 = root.screenY(a), x2 = root.screenX(b), y2 = root.screenY(b)
                    const lit = root.selected === e.from || root.selected === e.to
                    let color = Theme.line, width = 1.5
                    if (e.type === "similar") {
                        // Wider and brighter the closer the two songs sound.
                        const s = Math.max(0, Math.min(1, (e.score - 0.6) / 0.35))
                        color = Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.25 + 0.6 * s)
                        width = 1 + 3 * s
                    } else if (e.directed) {
                        color = Theme.estimated
                    } else if (e.type === "performance") {
                        color = Theme.accentDim
                    }
                    if (lit)
                        color = Theme.accentStrong
                    ctx.strokeStyle = color
                    ctx.lineWidth = lit ? width + 1 : width
                    ctx.setLineDash(e.estimated ? [5, 4] : [])
                    ctx.beginPath()
                    ctx.moveTo(x1, y1)
                    ctx.lineTo(x2, y2)
                    ctx.stroke()
                    if (e.directed) {  // a small arrow head half way
                        const mx = (x1 + x2) / 2, my = (y1 + y2) / 2, ang = Math.atan2(y2 - y1, x2 - x1)
                        ctx.setLineDash([])
                        ctx.fillStyle = color
                        ctx.beginPath()
                        ctx.moveTo(mx + 7 * Math.cos(ang), my + 7 * Math.sin(ang))
                        ctx.lineTo(mx + 7 * Math.cos(ang + 2.5), my + 7 * Math.sin(ang + 2.5))
                        ctx.lineTo(mx + 7 * Math.cos(ang - 2.5), my + 7 * Math.sin(ang - 2.5))
                        ctx.closePath()
                        ctx.fill()
                    }
                }
            }
        }

        Repeater {
            model: root.nodes
            delegate: Rectangle {
                id: chip
                required property var modelData
                required property int index
                readonly property bool isSeed: index === 0
                readonly property bool isSelected: root.selected === modelData.id
                x: { root.revision; return root.screenX(index) - width / 2 }
                y: { root.revision; return root.screenY(index) - height / 2 }
                z: isSelected ? 2 : 1
                width: Math.min(label.implicitWidth, 180) + 22
                height: 26
                radius: 13
                color: root.typeColor(modelData.type)
                border.width: isSeed || isSelected ? 2 : 1
                border.color: isSelected ? Theme.accentStrong : isSeed ? Theme.accent : Theme.line

                Text {
                    id: label
                    anchors.centerIn: parent
                    width: Math.min(implicitWidth, 180)
                    text: chip.modelData.label
                    elide: Text.ElideRight
                    color: Theme.text
                    font.pixelSize: Theme.fontSmall
                    font.weight: chip.isSeed ? Font.DemiBold : Font.Normal
                }
                // More behind this node: a small dot, centre on it to see.
                Rectangle {
                    visible: !chip.modelData.expanded && !chip.isSeed
                    width: 6; height: 6; radius: 3
                    anchors.right: parent.right
                    anchors.top: parent.top
                    color: Theme.textDim
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: mouse => {
                        root.selected = chip.modelData.id
                        if (mouse.button === Qt.RightButton && chip.modelData.track) {
                            menu.tracks = [chip.modelData.track]
                            menu.popup()
                        }
                    }
                    onDoubleClicked: {
                        if (chip.modelData.track)
                            Player.playTracks([chip.modelData.track], null, 0)
                        else if (!chip.modelData.expanded)
                            root.expand(chip.modelData)
                    }
                }
            }
        }
    }

    TrackMenu {
        id: menu
        showGraph: track => root.expand(root.nodeById("song:" + track.id))
    }

    // ---- header ---------------------------------------------------------------------

    Rectangle {
        id: headerBar
        anchors.left: parent.left
        anchors.right: parent.right
        height: header.implicitHeight + 28
        color: Qt.rgba(Theme.panel.r, Theme.panel.g, Theme.panel.b, 0.92)

        RowLayout {
            id: header
            x: 24
            y: 16
            width: parent.width - 48
            spacing: 16

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                Text {
                    text: root.mode === "similar" ? "SOUNDS LIKE" : root.mode === "sure" ? "SURELY RELATED TO" : "RELATED TO"
                    color: Theme.textDim
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0.6
                }
                Text {
                    Layout.fillWidth: true
                    text: root.seedLabel || (root.nodes.length > 0 ? root.nodes[0].label : "")
                    color: Theme.text
                    font.pixelSize: Theme.fontTitle
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Text {
                    text: root.loading ? "Loading…"
                        : Object.keys(root.expanding).length > 0 ? "Adding…"
                        : root.error ? root.error
                        : root.nodes.length <= 1 ? (root.mode === "similar" ? "No similar songs are known for this one yet."
                                                                            : "Nothing is linked to this yet.")
                        : root.truncated ? root.nodes.length + " items, the nearest ones; expand one to see further."
                        : root.nodes.length + " items"
                    color: root.error ? Theme.estimated : Theme.textFaint
                    font.pixelSize: Theme.fontSmall
                }
            }

            Segmented {
                visible: !!root.seed
                Layout.alignment: Qt.AlignTop
                options: [{ key: "related", label: "Related" }, { key: "sure", label: "Sure links" }]
                         .concat(root.canSimilar ? [{ key: "similar", label: "Sounds alike" }] : [])
                current: root.mode
                onPicked: key => root.mode = key
            }
        }
    }

    // ---- details of the selected node ----------------------------------------------

    Rectangle {
        id: details
        readonly property var node: { root.revision; return root.nodeById(root.selected) }
        readonly property var links: {
            if (!node)
                return []
            return root.edges.filter(e => e.from === node.id || e.to === node.id).map(e => {
                const other = root.nodeById(e.from === node.id ? e.to : e.from)
                return { other: other, label: e.label, type: e.type }
            }).filter(l => l.other).slice(0, 5)
        }
        visible: !!node
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 16
        width: 300
        height: detailsColumn.implicitHeight + 24
        color: Theme.raised
        border.color: Theme.line
        radius: Theme.radius

        ColumnLayout {
            id: detailsColumn
            x: 12
            y: 12
            width: parent.width - 24
            spacing: 6

            Text {
                text: details.node ? root.typeName(details.node.type).toUpperCase() : ""
                color: Theme.textDim
                font.pixelSize: 11
                font.weight: Font.DemiBold
                font.letterSpacing: 0.6
            }
            Text {
                Layout.fillWidth: true
                text: details.node ? details.node.label : ""
                color: Theme.text
                font.pixelSize: Theme.fontBody
                font.weight: Font.DemiBold
                wrapMode: Text.Wrap
            }
            Text {
                Layout.fillWidth: true
                visible: text.length > 0
                text: details.node ? (details.node.subtitle || "") : ""
                color: Theme.textDim
                font.pixelSize: Theme.fontSmall
                elide: Text.ElideRight
            }
            Repeater {
                model: details.links
                delegate: Text {
                    required property var modelData
                    Layout.fillWidth: true
                    text: (modelData.label ? modelData.label + " · " : "") + modelData.other.label
                    color: Theme.textFaint
                    font.pixelSize: Theme.fontSmall
                    elide: Text.ElideRight
                }
            }
            Flow {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 6
                Repeater {
                    model: {
                        const n = details.node
                        if (!n)
                            return []
                        const out = []
                        if (n.track) {
                            out.push({ text: "Play", run: () => Player.playTracks([n.track], null, 0) })
                            out.push({ text: "Play next", run: () => Player.playNextMany([n.track], null) })
                        }
                        if (!n.expanded)
                            out.push({ text: "Expand", run: () => root.expand(n) })
                        if (n.id !== root.seed)
                            out.push({ text: "Centre here", run: () => root.centreOn(n) })
                        if (n.type === "composition")
                            out.push({ text: "Open", run: () => Nav.go({ page: "composition", composition: { id: n.itemId, name: n.label } }) })
                        else if (n.type === "title")
                            out.push({ text: "Open", run: () => Nav.go({ page: "work", work: { id: n.itemId, name: n.label } }) })
                        else if (n.type === "album")
                            out.push({ text: "Open", run: () => Nav.openAlbumId(n.itemId, n.label) })
                        return out
                    }
                    delegate: AbstractButton {
                        id: action
                        required property var modelData
                        implicitWidth: actionLabel.implicitWidth + 20
                        implicitHeight: 26
                        hoverEnabled: true
                        onClicked: modelData.run()
                        background: Rectangle {
                            color: action.hovered ? Theme.hover : Theme.panel
                            border.color: Theme.line
                            radius: Theme.radius
                        }
                        contentItem: Text {
                            id: actionLabel
                            text: action.modelData.text
                            color: Theme.text
                            font.pixelSize: Theme.fontSmall
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }
        }
    }

    // ---- legend --------------------------------------------------------------------

    Row {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 16
        spacing: 12
        Repeater {
            model: root.mode === "similar" ? ["song"] : ["song", "composition", "title"]
            delegate: Row {
                required property var modelData
                spacing: 6
                Rectangle {
                    width: 12; height: 12; radius: 6
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.typeColor(modelData)
                    border.color: Theme.line
                }
                Text {
                    text: root.typeName(modelData)
                    color: Theme.textDim
                    font.pixelSize: Theme.fontSmall
                }
            }
        }
    }
}
