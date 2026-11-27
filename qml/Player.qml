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

    property ListModel queue: ListModel {}

    readonly property var current: {
        revision
        return currentIndex >= 0 && currentIndex < queue.count ? queue.get(currentIndex) : null
    }
    readonly property real duration: current ? current.duration : 0

    onVolumeChanged: Audio.setVolume(Math.round(volume * 100))
    onMutedChanged: Audio.setMuted(muted)

    function entryFor(track, album) {
        return {
            trackId: track.id, title: track.title, artist: track.artist,
            duration: track.duration, album: album ? album.title : "",
            coverArt: track.coverArt || (album ? album.coverArt : "") || "",
            gain: track.gain || 0
        }
    }

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

    function replaceQueue(entries, startIndex) {
        queue.clear()
        for (let i = 0; i < entries.length; ++i)
            queue.append(entries[i])
        currentIndex = entries.length > 0 ? Math.min(startIndex, entries.length - 1) : -1
        ++revision
        start()
    }

    function playAlbum(album, startIndex) {
        replaceQueue(album.tracks.map(t => entryFor(t, album)), startIndex)
    }

    function enqueue(track, album) {
        queue.append(entryFor(track, album))
        const first = currentIndex < 0
        if (first)
            currentIndex = 0
        ++revision
        if (first)
            start()
    }

    function playNext(track, album) {
        queue.insert(currentIndex + 1, entryFor(track, album))
        const first = currentIndex < 0
        if (first)
            currentIndex = 0
        ++revision
        if (first)
            start()
    }

    function jump(index) {
        if (index < 0 || index >= queue.count)
            return
        currentIndex = index
        ++revision
        start()
    }

    function removeAt(index) {
        if (index < 0 || index >= queue.count)
            return
        const wasCurrent = index === currentIndex
        queue.remove(index)
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
        currentIndex = -1
        position = 0
        playing = false
        ++revision
        Audio.stop()
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
            if (root.current && root.current.trackId === trackId)
                root.next()
        }
        function onFailed(trackId, reason) {
            console.warn("playback failed:", reason)
            if (root.current && root.current.trackId === trackId)
                root.next()
        }
    }

}
