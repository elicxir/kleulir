pragma Singleton
import QtQuick

// Stand-in for libeos' QueueModel + Controller. No sound: a timer advances
// the position so the transport, the queue and the seek bar can be exercised.
// The queue is replaceable as a whole (replaceQueue) because the real one
// will be overwritten by the server's `state` message.
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

    function entryFor(track, album) {
        return {
            trackId: track.id, title: track.title, artist: track.artist,
            duration: track.duration, album: album ? album.title : ""
        }
    }

    function replaceQueue(entries, startIndex) {
        queue.clear()
        for (let i = 0; i < entries.length; ++i)
            queue.append(entries[i])
        currentIndex = entries.length > 0 ? Math.min(startIndex, entries.length - 1) : -1
        position = 0
        playing = currentIndex >= 0
        ++revision
    }

    function playAlbum(album, startIndex) {
        replaceQueue(album.tracks.map(t => entryFor(t, album)), startIndex)
    }

    function enqueue(track, album) {
        queue.append(entryFor(track, album))
        if (currentIndex < 0)
            currentIndex = 0
        ++revision
    }

    function playNext(track, album) {
        queue.insert(currentIndex + 1, entryFor(track, album))
        if (currentIndex < 0)
            currentIndex = 0
        ++revision
    }

    function jump(index) {
        if (index < 0 || index >= queue.count)
            return
        currentIndex = index
        position = 0
        playing = true
        ++revision
    }

    function removeAt(index) {
        if (index < 0 || index >= queue.count)
            return
        queue.remove(index)
        if (index < currentIndex) {
            --currentIndex
        } else if (index === currentIndex) {
            position = 0
            if (currentIndex >= queue.count) {
                currentIndex = queue.count - 1
                playing = false
            }
        }
        ++revision
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
    }

    function toggle() {
        if (current)
            playing = !playing
    }

    function next() {
        if (currentIndex + 1 < queue.count) {
            jump(currentIndex + 1)
        } else {
            playing = false
            position = 0
        }
    }

    function previous() {
        if (position > 3 || currentIndex <= 0)
            position = 0
        else
            jump(currentIndex - 1)
    }

    function seek(seconds) {
        position = Math.max(0, Math.min(seconds, duration))
    }

    property Timer ticker: Timer {
        interval: 250
        repeat: true
        running: root.playing
        onTriggered: {
            root.position += interval / 1000
            if (root.position >= root.duration)
                root.next()
        }
    }
}
