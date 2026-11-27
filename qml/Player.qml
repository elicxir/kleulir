pragma Singleton
import QtQuick
import Kleulir

// The queue and the transport. Sound comes from Audio (the Windows media player).
// The queue is replaceable as a whole (replaceQueue) because it will later be
// overwritten by the server's `state` message.
QtObject {
    id: root

    property bool playing: false
    property real position: 0          // seconds
    property real volume: 0.8          // 0..1
    property bool muted: false
    property int currentIndex: -1
    property string playbackDeviceId: "d1"
    property int revision: 0           // bumped on every queue change

    // Shuffle reorders what is still to come; turning it off puts the queue back
    // in the order it had. Repeat: "off", "all" (the queue) or "one" (the track).
    property bool shuffle: false
    property string repeat: "off"
    property var unshuffled: []        // the queue's order from before shuffle
    property int nextUid: 1

    property ListModel queue: ListModel {}

    readonly property var current: {
        revision
        return currentIndex >= 0 && currentIndex < queue.count ? queue.get(currentIndex) : null
    }
    readonly property real duration: current ? current.duration : 0

    onVolumeChanged: Audio.setVolume(Math.round(volume * 100))
    onMutedChanged: Audio.setMuted(muted)

    // ---- entries -----------------------------------------------------------

    function entryFor(track, album) {
        return {
            uid: nextUid++,
            trackId: track.id, title: track.title, artist: track.artist,
            duration: track.duration,
            album: track.album || (album ? album.title : "") || "",
            albumId: track.albumId || (album ? album.id : "") || "",
            coverArt: track.coverArt || (album ? album.coverArt : "") || "",
            gain: track.gain || 0
        }
    }

    function copyOf(e) {
        return {
            uid: e.uid, trackId: e.trackId, title: e.title, artist: e.artist,
            duration: e.duration, album: e.album, albumId: e.albumId,
            coverArt: e.coverArt, gain: e.gain
        }
    }

    function entries() {
        const out = []
        for (let i = 0; i < queue.count; ++i)
            out.push(copyOf(queue.get(i)))
        return out
    }

    function setEntries(list) {
        queue.clear()
        for (let i = 0; i < list.length; ++i)
            queue.append(list[i])
    }

    // ---- playback ----------------------------------------------------------

    // Starts the current queue entry from the top.
    function start() {
        position = 0
        if (currentIndex < 0 || currentIndex >= queue.count) {
            playing = false
            Audio.stop()
            return
        }
        playing = true
        const e = queue.get(currentIndex)
        Audio.play(e.trackId, 0, false, {
            title: e.title, artist: e.artist, album: e.album, coverArt: e.coverArt, gain: e.gain
        })
    }

    function toggle() {
        if (!current)
            return
        playing = !playing
        Audio.setPaused(!playing)
    }

    function next() {
        if (currentIndex + 1 < queue.count) {
            jump(currentIndex + 1)
        } else if (repeat === "all" && queue.count > 0) {
            jump(0)
        } else {
            playing = false
            position = 0
            Audio.stop()
        }
    }

    function previous() {
        if (position > 3 || currentIndex <= 0)
            seek(0)
        else
            jump(currentIndex - 1)
    }

    function seek(seconds) {
        position = Math.max(0, Math.min(seconds, duration))
        Audio.seek(position)
    }

    function jump(index) {
        if (index < 0 || index >= queue.count)
            return
        currentIndex = index
        ++revision
        start()
    }

    // ---- shuffle and repeat ------------------------------------------------

    function shuffleUpcoming() {
        const all = entries()
        const head = all.slice(0, currentIndex + 1)
        const tail = all.slice(currentIndex + 1)
        for (let i = tail.length - 1; i > 0; --i) {
            const j = Math.floor(Math.random() * (i + 1))
            const swap = tail[i]
            tail[i] = tail[j]
            tail[j] = swap
        }
        setEntries(head.concat(tail))
        ++revision
    }

    function toggleShuffle() {
        if (!shuffle) {
            shuffle = true
            unshuffled = entries()
            shuffleUpcoming()
            return
        }
        shuffle = false
        // Back to the earlier order, keeping the current track current. Entries
        // added while shuffled go to the end.
        const now = entries()
        const playingUid = current ? current.uid : -1
        const present = {}
        now.forEach(e => present[e.uid] = true)
        const order = unshuffled.filter(e => present[e.uid])
        const known = {}
        order.forEach(e => known[e.uid] = true)
        now.forEach(e => { if (!known[e.uid]) order.push(e) })
        unshuffled = []
        setEntries(order)
        currentIndex = order.findIndex(e => e.uid === playingUid)
        ++revision
    }

    function cycleRepeat() {
        repeat = repeat === "off" ? "all" : repeat === "all" ? "one" : "off"
    }

    // ---- queue edits -------------------------------------------------------

    function replaceQueue(list, startIndex) {
        setEntries(list)
        currentIndex = list.length > 0 ? Math.max(0, Math.min(startIndex, list.length - 1)) : -1
        unshuffled = shuffle ? list.slice() : []
        if (shuffle)
            shuffleUpcoming()
        ++revision
        start()
    }

    function playTracks(tracks, album, startIndex) {
        replaceQueue(tracks.map(t => entryFor(t, album)), startIndex || 0)
    }

    function playAlbum(album, startIndex) {
        playTracks(album.tracks, album, startIndex)
    }

    // Appends; starts playing if nothing was queued.
    function enqueueMany(tracks, album) {
        const added = tracks.map(t => entryFor(t, album))
        if (added.length === 0)
            return
        const first = currentIndex < 0
        added.forEach(e => queue.append(e))
        if (shuffle)
            unshuffled = unshuffled.concat(added)
        if (first)
            currentIndex = 0
        ++revision
        if (first)
            start()
    }

    // Inserts right after the current track, in the given order.
    function playNextMany(tracks, album) {
        const added = tracks.map(t => entryFor(t, album))
        if (added.length === 0)
            return
        const first = currentIndex < 0
        for (let i = 0; i < added.length; ++i)
            queue.insert(currentIndex + 1 + i, added[i])
        if (shuffle)
            unshuffled = unshuffled.concat(added)
        if (first)
            currentIndex = 0
        ++revision
        if (first)
            start()
    }

    function enqueue(track, album) { enqueueMany([track], album) }
    function playNext(track, album) { playNextMany([track], album) }

    function removeAt(index) {
        if (index < 0 || index >= queue.count)
            return
        const wasCurrent = index === currentIndex
        const uid = queue.get(index).uid
        queue.remove(index)
        if (shuffle)
            unshuffled = unshuffled.filter(e => e.uid !== uid)
        if (index < currentIndex) {
            --currentIndex
        } else if (wasCurrent && currentIndex >= queue.count) {
            currentIndex = queue.count - 1
        }
        ++revision
        if (wasCurrent) {
            // The entry that moved into this place plays next; nothing left stops.
            if (playing && currentIndex >= 0) {
                start()
            } else {
                playing = false
                position = 0
                Audio.stop()
            }
        }
    }

    function move(from, to) {
        if (from === to || from < 0 || to < 0 || from >= queue.count || to >= queue.count)
            return
        queue.move(from, to, 1)
        if (currentIndex === from)
            currentIndex = to
        else if (from < currentIndex && to >= currentIndex)
            --currentIndex
        else if (from > currentIndex && to <= currentIndex)
            ++currentIndex
        ++revision
    }

    function clear() {
        queue.clear()
        unshuffled = []
        currentIndex = -1
        position = 0
        playing = false
        ++revision
        Audio.stop()
    }

    // ---- events from the audio backend -------------------------------------

    property Connections audioEvents: Connections {
        target: Audio
        function onPositionChanged() {
            if (root.current)
                root.position = Audio.position
        }
        // Media keys and the system flyout.
        function onPausedChanged(paused) {
            if (root.current)
                root.playing = !paused
        }
        function onNextRequested() { root.next() }
        function onPreviousRequested() { root.previous() }
        function onFinished(trackId) {
            if (!root.current || root.current.trackId !== trackId)
                return
            if (root.repeat === "one")
                root.start()
            else
                root.next()
        }
        function onFailed(trackId, reason) {
            console.warn("playback failed:", reason)
            if (root.current && root.current.trackId === trackId)
                root.next()
        }
    }
}
