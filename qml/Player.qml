pragma Singleton
import QtCore
import QtQuick
import Kleulir

// The queue and the transport. Sound comes from Audio (mpv, or the Windows media
// player when there is no mpv).
// The queue is replaceable as a whole (replaceQueue) because it will later be
// overwritten by the server's `state` message.
QtObject {
    id: root

    property bool playing: false
    property real position: 0          // seconds
    property real volume: 0.8          // 0..1
    property bool muted: false
    property int currentIndex: -1
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
        resumePending = false
        stalled = false
        retriedAt = -1
        position = 0
        if (currentIndex < 0 || currentIndex >= queue.count) {
            playing = false
            Audio.stop()
            return
        }
        playing = true
        const e = queue.get(currentIndex)
        if (!Audio.play(e.trackId, 0, false, {
            title: e.title, artist: e.artist, album: e.album, coverArt: e.coverArt, gain: e.gain
        })) {
            hold()
            return
        }
        syncNext()
    }

    // ---- interruptions -----------------------------------------------------

    // Nothing can be played right now (no session yet, the server out of reach,
    // the audio backend gone): the track waits at its position instead of being
    // skipped. It goes on by itself when that is over, or on Play.
    property bool stalled: false
    // Tracks in a row that the server would not play. After a few, stop instead
    // of running through the whole queue.
    property int failures: 0
    // Where a track that ended early was last started again, so one whose length
    // is simply wrong is not restarted for ever.
    property real retriedAt: -1

    function hold() {
        playing = false
        resumePending = true
        stalled = true
    }

    // ---- gapless ----------------------------------------------------------

    // The entry that follows the current one when it ends by itself, or -1.
    // Repeat-one is not handed to the player: the track is restarted instead.
    function followingIndex() {
        if (currentIndex < 0 || repeat === "one")
            return -1
        if (currentIndex + 1 < queue.count)
            return currentIndex + 1
        return repeat === "all" && queue.count > 0 ? 0 : -1
    }

    // Keeps the audio player's "next" in step with the queue, so the change of
    // track happens inside the player, without a gap.
    function syncNext() {
        if (resumePending || !current)
            return
        const index = followingIndex()
        if (index < 0) {
            Audio.setNext("", {})
            return
        }
        const e = queue.get(index)
        Audio.setNext(e.trackId, {
            title: e.title, artist: e.artist, album: e.album, coverArt: e.coverArt, gain: e.gain
        })
    }

    function toggle() {
        if (!current)
            return
        if (resumePending) {
            resume()
            return
        }
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
        if (resumePending)
            return      // nothing loaded yet; Play starts from here
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
        resumePending = false
        stalled = false
        ++revision
        Audio.stop()
    }

    // ---- remembered between runs -------------------------------------------

    property Settings saved: Settings {
        category: "player"
        property alias volume: root.volume
        property alias muted: root.muted
        property alias repeat: root.repeat
    }

    property bool restored: false      // the saved queue has been read
    property bool resumePending: false // a restored track still has to be loaded

    function saveQueue() {
        if (!restored)
            return
        App.writeState("queue", JSON.stringify({
            server: Session.serverUrl, entries: entries(), index: currentIndex, position: Math.floor(position),
            shuffle: shuffle, unshuffled: unshuffled
        }))
    }

    // A restored queue is only shown at first: nothing is loaded into the audio
    // player, so starting the app never makes a sound. The first press of Play
    // loads the track at the position it had.
    function resume() {
        resumePending = false
        stalled = false
        if (currentIndex < 0 || currentIndex >= queue.count)
            return
        const e = queue.get(currentIndex)
        playing = true
        if (!Audio.play(e.trackId, position, false, {
            title: e.title, artist: e.artist, album: e.album, coverArt: e.coverArt, gain: e.gain
        })) {
            hold()
            return
        }
        syncNext()
    }

    Component.onCompleted: {
        Audio.setVolume(Math.round(volume * 100))
        Audio.setMuted(muted)
        try {
            const state = JSON.parse(App.readState("queue") || "null")
            // Track ids only mean something to the server they came from.
            const here = state && (!state.server || state.server === Session.serverUrl)
            if (here && state.entries && state.entries.length > 0) {
                setEntries(state.entries)
                nextUid = state.entries.reduce((top, e) => Math.max(top, e.uid || 0), 0) + 1
                currentIndex = Math.max(0, Math.min(state.index, state.entries.length - 1))
                position = state.position || 0
                shuffle = !!state.shuffle
                unshuffled = state.unshuffled || []
                resumePending = true
                ++revision
            }
        } catch (error) {
            console.warn("saved queue could not be read:", error)
        }
        queueServer = Session.serverUrl
        restored = true
    }

    // The server the queue's tracks are on.
    property string queueServer: ""
    property Connections sessionEvents: Connections {
        target: Session
        function onChanged() {
            if (Session.state !== Session.Ready)
                return
            if (Session.serverUrl !== root.queueServer) {
                if (root.queueServer !== "")
                    root.clear()
                root.queueServer = Session.serverUrl
            } else if (root.stalled) {
                root.resume()     // asked to play before the session was ready
            }
        }
    }

    onRevisionChanged: {
        queueSaver.restart()
        syncNext()
    }
    onRepeatChanged: syncNext()
    onPlayingChanged: queueSaver.restart()
    property Timer queueSaver: Timer {
        interval: 1500
        onTriggered: root.saveQueue()
    }
    // While playing, the position is written now and then, so a crash loses little.
    property Timer positionSaver: Timer {
        interval: 15000
        repeat: true
        running: root.playing
        onTriggered: root.saveQueue()
    }
    property Connections appEvents: Connections {
        target: Qt.application
        function onAboutToQuit() { root.saveQueue() }
    }

    // ---- events from the audio backend -------------------------------------

    property Connections audioEvents: Connections {
        target: Audio
        function onPositionChanged() {
            if (!root.current || root.resumePending)
                return
            // The Windows player's position runs a little ahead of the sound and
            // goes a second or two past the end before it changes track. Shown
            // as is, the clock would read past the track's length; hold it there.
            root.position = root.duration > 0 ? Math.min(Audio.position, root.duration) : Audio.position
            if (Audio.position > 2)
                root.failures = 0     // this one plays
        }
        // Media keys and the system flyout.
        function onPausedChanged(paused) {
            if (root.current)
                root.playing = !paused
        }
        function onNextRequested() { root.next() }
        function onPreviousRequested() { root.previous() }
        // The player went on to the track it was given, without a gap: follow it.
        function onAdvanced(trackId) {
            const index = root.followingIndex()
            if (index >= 0 && root.queue.get(index).trackId === trackId) {
                root.currentIndex = index
                root.position = 0
                ++root.revision
            } else {
                // The queue changed under it; play what the queue says instead.
                root.next()
            }
        }
        function onFinished(trackId) {
            if (!root.current || root.current.trackId !== trackId)
                return
            // Ended well before its end: the stream broke off. Go on from there
            // (once per place; a second early end there is taken as the end).
            if (root.duration > 0 && root.position < root.duration - 5
                    && Math.abs(root.position - root.retriedAt) > 1) {
                root.retriedAt = root.position
                root.resume()
                return
            }
            if (root.repeat === "one")
                root.start()
            else
                root.next()
        }
        // This track cannot be played, though the server is there: go on to the
        // next, but not through the whole queue (or round and round with repeat).
        function onFailed(trackId, reason) {
            console.warn("playback failed:", reason)
            if (!root.current || root.current.trackId !== trackId)
                return
            if (++root.failures >= 3) {
                root.failures = 0
                root.playing = false
                root.resumePending = true
                Audio.stop()
                return
            }
            root.next()
        }
        // Not the track's fault: keep the place and wait.
        function onInterrupted(trackId) {
            if (root.current && root.current.trackId === trackId)
                root.hold()
        }
        function onRecovered() {
            if (root.stalled)
                root.resume()
        }
    }
}
