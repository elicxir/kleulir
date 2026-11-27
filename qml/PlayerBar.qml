import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Kleulir

Rectangle {
    id: root
    property bool queueOpen: true
    signal toggleQueue()

    color: Theme.panel
    implicitHeight: 84

    readonly property var device: MockData.devices.find(d => d.id === Player.playbackDeviceId)
    readonly property bool remote: Player.playbackDeviceId !== "d1"
    readonly property int sideWidth: 300   // equal sides keep the transport centred

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.pad
        anchors.rightMargin: Theme.pad
        spacing: Theme.pad

        // Now playing
        RowLayout {
            Layout.preferredWidth: root.sideWidth
            Layout.maximumWidth: root.sideWidth
            spacing: 12

            Cover {
                Layout.preferredWidth: 52
                Layout.preferredHeight: 52
                title: Player.current ? Player.current.album : ""
                visible: Player.current !== null
                shadow: true
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3
                Text {
                    Layout.fillWidth: true
                    text: Player.current ? Player.current.title : "Nothing playing"
                    color: Player.current ? Theme.text : Theme.textFaint
                    font.pixelSize: 14
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    visible: Player.current !== null
                    text: Player.current ? Player.current.artist + " · " + Player.current.album : ""
                    color: Theme.textDim
                    font.pixelSize: Theme.fontSmall
                    elide: Text.ElideRight
                }
            }
        }

        // Transport and seek
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 12

                IconButton {
                    glyph: "previous"
                    tip: "Previous"
                    enabled: Player.current !== null
                    onClicked: Player.previous()
                }
                AbstractButton {
                    id: playButton
                    implicitWidth: 38
                    implicitHeight: 38
                    hoverEnabled: true
                    enabled: Player.current !== null
                    Accessible.name: Player.playing ? "Pause" : "Play"
                    onClicked: Player.toggle()
                    background: Rectangle {
                        radius: width / 2   // the one round control in the UI
                        color: !playButton.enabled ? Theme.raised
                               : playButton.down ? Theme.textDim
                               : playButton.hovered ? "#ffffff" : Theme.text
                    }
                    contentItem: Item {
                        Icon {
                            anchors.centerIn: parent
                            // The play triangle looks off-centre unless nudged right.
                            anchors.horizontalCenterOffset: Player.playing ? 0 : 1
                            name: Player.playing ? "pause" : "play"
                            size: 20
                            color: playButton.enabled ? Theme.bg : Theme.textFaint
                        }
                    }
                }
                IconButton {
                    glyph: "next"
                    tip: "Next"
                    enabled: Player.current !== null
                    onClicked: Player.next()
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.maximumWidth: 640
                Layout.alignment: Qt.AlignHCenter
                spacing: Theme.gap

                Text {
                    Layout.preferredWidth: 40
                    text: Theme.time(seek.pressed ? seek.value : Player.position)
                    color: Theme.textDim
                    font.pixelSize: Theme.fontSmall
                    font.features: { "tnum": 1 }
                    horizontalAlignment: Text.AlignRight
                }
                Slider {
                    id: seek
                    Layout.fillWidth: true
                    implicitHeight: 20
                    enabled: Player.current !== null
                    from: 0
                    to: Math.max(1, Player.duration)
                    // While dragging, the handle follows the pointer, not the clock.
                    Binding on value {
                        value: Player.position
                        when: !seek.pressed
                    }
                    onPressedChanged: if (!pressed) Player.seek(value)

                    background: Rectangle {
                        x: seek.leftPadding
                        y: seek.topPadding + seek.availableHeight / 2 - height / 2
                        width: seek.availableWidth
                        height: 3
                        color: Theme.hover
                        Rectangle {
                            width: seek.visualPosition * parent.width
                            height: parent.height
                            color: seek.enabled ? Theme.text : Theme.textFaint
                        }
                    }
                    handle: Rectangle {
                        x: seek.leftPadding + seek.visualPosition * (seek.availableWidth - width)
                        y: seek.topPadding + seek.availableHeight / 2 - height / 2
                        width: 3
                        height: 13
                        color: Theme.text
                        visible: seek.enabled && (seek.hovered || seek.pressed)
                    }
                }
                Text {
                    Layout.preferredWidth: 40
                    text: Theme.time(Player.duration)
                    color: Theme.textDim
                    font.pixelSize: Theme.fontSmall
                    font.features: { "tnum": 1 }
                }
            }
        }

        // Volume, device, queue
        RowLayout {
            Layout.preferredWidth: root.sideWidth
            Layout.maximumWidth: root.sideWidth
            spacing: 4

            Item { Layout.fillWidth: true }

            IconButton {
                id: deviceButton
                visible: MockData.eosFeatures
                glyph: "device"
                tip: "Play on: " + (root.device ? root.device.name : "")
                active: root.remote
                onClicked: deviceMenu.open()

                Menu {
                    id: deviceMenu
                    y: -implicitHeight - 6
                    padding: 4
                    background: Rectangle {
                        implicitWidth: 220
                        color: Theme.raised
                        border.color: Theme.line
                    }
                    Repeater {
                        model: MockData.devices
                        delegate: MenuItem {
                            id: deviceItem
                            required property var modelData
                            readonly property bool current: modelData.id === Player.playbackDeviceId
                            enabled: modelData.online
                            implicitHeight: 32
                            onTriggered: Player.playbackDeviceId = modelData.id
                            background: Rectangle {
                                color: deviceItem.highlighted ? Theme.hover : "transparent"
                            }
                            contentItem: Text {
                                text: deviceItem.modelData.name + (deviceItem.modelData.online ? "" : " (offline)")
                                color: !deviceItem.enabled ? Theme.textFaint
                                       : deviceItem.current ? Theme.accent : Theme.text
                                font.pixelSize: Theme.fontBody
                                leftPadding: Theme.gap
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }
                }
            }
            IconButton {
                glyph: Player.muted || Player.volume === 0 ? "mute" : "volume"
                tip: Player.muted ? "Unmute" : "Mute"
                onClicked: Player.muted = !Player.muted
            }
            Slider {
                id: volume
                Layout.preferredWidth: 96
                implicitHeight: 20
                from: 0
                to: 1
                value: Player.volume
                onMoved: {
                    Player.volume = value
                    Player.muted = false
                }
                background: Rectangle {
                    x: volume.leftPadding
                    y: volume.topPadding + volume.availableHeight / 2 - height / 2
                    width: volume.availableWidth
                    height: 3
                    color: Theme.hover
                    Rectangle {
                        width: volume.visualPosition * parent.width
                        height: parent.height
                        color: Player.muted ? Theme.textFaint
                               : volume.hovered || volume.pressed ? Theme.text : Theme.textDim
                    }
                }
                handle: Rectangle {
                    x: volume.leftPadding + volume.visualPosition * (volume.availableWidth - width)
                    y: volume.topPadding + volume.availableHeight / 2 - height / 2
                    width: 3
                    height: 13
                    color: Theme.text
                    visible: volume.hovered || volume.pressed
                }
            }
            IconButton {
                Layout.leftMargin: 4
                glyph: "queue"
                tip: root.queueOpen ? "Hide queue" : "Show queue"
                active: root.queueOpen
                onClicked: root.toggleQueue()
            }
        }
    }
}
