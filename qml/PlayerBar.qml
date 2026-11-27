import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Kleulir

Rectangle {
    id: root
    property bool queueOpen: true
    signal toggleQueue()

    color: Theme.panel
    implicitHeight: 76

    readonly property var device: MockData.devices.find(d => d.id === Player.playbackDeviceId)

    Rectangle {
        anchors.top: parent.top
        width: parent.width
        height: 1
        color: Theme.line
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.pad
        anchors.rightMargin: Theme.pad
        spacing: Theme.pad

        // Now playing
        RowLayout {
            Layout.preferredWidth: 260
            Layout.maximumWidth: 260
            spacing: Theme.gap

            Cover {
                Layout.preferredWidth: 48
                Layout.preferredHeight: 48
                title: Player.current ? Player.current.album : ""
                opacity: Player.current ? 1 : 0.3
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text {
                    Layout.fillWidth: true
                    text: Player.current ? Player.current.title : "再生していません"
                    color: Player.current ? Theme.text : Theme.textFaint
                    font.pixelSize: Theme.fontBody
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    visible: Player.current !== null
                    text: Player.current ? Player.current.artist : ""
                    color: Theme.textDim
                    font.pixelSize: Theme.fontSmall
                    elide: Text.ElideRight
                }
            }
        }

        // Transport and seek
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 4
                IconButton {
                    text: "⏮"
                    tip: "前の曲"
                    enabled: Player.current !== null
                    onClicked: Player.previous()
                }
                IconButton {
                    text: Player.playing ? "⏸" : "▶"
                    tip: Player.playing ? "一時停止" : "再生"
                    glyphSize: 20
                    implicitWidth: 40
                    enabled: Player.current !== null
                    onClicked: Player.toggle()
                }
                IconButton {
                    text: "⏭"
                    tip: "次の曲"
                    enabled: Player.current !== null
                    onClicked: Player.next()
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.gap
                Text {
                    Layout.preferredWidth: 40
                    text: Theme.time(seek.pressed ? seek.value : Player.position)
                    color: Theme.textDim
                    font.pixelSize: Theme.fontSmall
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
                        height: 4
                        radius: 2
                        color: Theme.raised
                        Rectangle {
                            width: seek.visualPosition * parent.width
                            height: parent.height
                            radius: 2
                            color: Theme.accent
                        }
                    }
                    handle: Rectangle {
                        x: seek.leftPadding + seek.visualPosition * (seek.availableWidth - width)
                        y: seek.topPadding + seek.availableHeight / 2 - height / 2
                        width: 12
                        height: 12
                        radius: 6
                        color: Theme.text
                        visible: seek.hovered || seek.pressed
                    }
                }
                Text {
                    Layout.preferredWidth: 40
                    text: Theme.time(Player.duration)
                    color: Theme.textDim
                    font.pixelSize: Theme.fontSmall
                }
            }
        }

        // Volume, device, queue
        RowLayout {
            Layout.preferredWidth: 300
            Layout.maximumWidth: 300
            spacing: 4

            IconButton {
                text: Player.muted || Player.volume === 0 ? "🔇" : "🔊"
                tip: Player.muted ? "ミュート解除" : "ミュート"
                onClicked: Player.muted = !Player.muted
            }
            Slider {
                id: volume
                Layout.preferredWidth: 90
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
                    height: 4
                    radius: 2
                    color: Theme.raised
                    Rectangle {
                        width: volume.visualPosition * parent.width
                        height: parent.height
                        radius: 2
                        color: Player.muted ? Theme.textFaint : Theme.textDim
                    }
                }
                handle: Rectangle {
                    x: volume.leftPadding + volume.visualPosition * (volume.availableWidth - width)
                    y: volume.topPadding + volume.availableHeight / 2 - height / 2
                    width: 10
                    height: 10
                    radius: 5
                    color: Theme.text
                }
            }

            Item { Layout.fillWidth: true }

            IconButton {
                id: deviceButton
                visible: MockData.eosFeatures
                text: root.device ? root.device.name : "端末"
                tip: "再生する端末"
                glyphSize: Theme.fontSmall
                active: Player.playbackDeviceId !== "d1"
                onClicked: deviceMenu.open()

                Menu {
                    id: deviceMenu
                    y: -implicitHeight - 4
                    Repeater {
                        model: MockData.devices
                        delegate: MenuItem {
                            required property var modelData
                            text: modelData.name + (modelData.online ? "" : "（切断中）")
                            enabled: modelData.online
                            checkable: true
                            checked: modelData.id === Player.playbackDeviceId
                            onTriggered: Player.playbackDeviceId = modelData.id
                        }
                    }
                }
            }
            IconButton {
                text: "キュー"
                glyphSize: Theme.fontSmall
                active: root.queueOpen
                onClicked: root.toggleQueue()
            }
        }
    }
}
