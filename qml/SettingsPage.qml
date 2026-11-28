import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Kleulir

Flickable {
    id: root
    contentWidth: width
    contentHeight: body.implicitHeight + 40
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar {}

    // ---- small building blocks ------------------------------------------------

    component SectionTitle: Text {
        color: Theme.text
        font.pixelSize: 15
        font.weight: Font.DemiBold
    }
    component Hint: Text {
        Layout.fillWidth: true
        color: Theme.textDim
        font.pixelSize: Theme.fontBody
        wrapMode: Text.Wrap
    }
    component Divider: Rectangle {
        Layout.fillWidth: true
        implicitHeight: 1
        color: Theme.line
    }
    component OutlineButton: AbstractButton {
        id: outline
        implicitHeight: 34
        implicitWidth: outlineLabel.implicitWidth + 32
        hoverEnabled: true
        background: Rectangle {
            color: outline.hovered ? Qt.rgba(1, 1, 1, 0.10) : "transparent"
            border.color: Qt.rgba(1, 1, 1, 0.28)
        }
        contentItem: Text {
            id: outlineLabel
            text: outline.text
            color: Theme.text
            font.pixelSize: Theme.fontBody
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }
    // A labelled on/off row.
    component Toggle: AbstractButton {
        id: toggle
        checkable: true
        implicitHeight: 28
        implicitWidth: toggleRow.implicitWidth
        hoverEnabled: true
        contentItem: Row {
            id: toggleRow
            spacing: 10
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 18
                height: 18
                color: toggle.checked ? Theme.text : "transparent"
                border.color: toggle.checked ? Theme.text : toggle.hovered ? Theme.text : Theme.textFaint
                opacity: toggle.enabled ? 1 : 0.4
                Rectangle {
                    visible: toggle.checked
                    anchors.centerIn: parent
                    width: 8
                    height: 8
                    color: Theme.bg
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: toggle.text
                color: toggle.enabled ? Theme.text : Theme.textFaint
                font.pixelSize: Theme.fontBody
            }
        }
    }

    ColumnLayout {
        id: body
        x: 24
        y: 20
        width: Math.min(root.width - 48, 760)
        spacing: 20

        Text {
            text: "Settings"
            color: Theme.text
            font.pixelSize: Theme.fontTitle
            font.weight: Font.Bold
        }

        // ---- Display ---------------------------------------------------------
        ColumnLayout {
            spacing: 10

            SectionTitle { text: "Display" }
            Hint { text: "Size of everything in the window, on top of Windows' own display scaling." }

            Rectangle {
                implicitWidth: scaleRow.implicitWidth + 6
                implicitHeight: 32
                color: Theme.raised
                border.color: Theme.line

                Row {
                    id: scaleRow
                    anchors.centerIn: parent
                    Repeater {
                        model: [0.8, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75]
                        delegate: AbstractButton {
                            id: step
                            required property real modelData
                            readonly property bool selected: Math.abs(App.uiScale - modelData) < 0.001
                            implicitWidth: 64
                            implicitHeight: 26
                            hoverEnabled: true
                            onClicked: App.uiScale = modelData
                            background: Rectangle { color: step.selected ? Theme.hover : "transparent" }
                            contentItem: Text {
                                text: Math.round(step.modelData * 100) + "%"
                                color: step.selected ? Theme.text : step.hovered ? Theme.text : Theme.textDim
                                font.pixelSize: Theme.fontSmall
                                font.weight: step.selected ? Font.DemiBold : Font.Normal
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }
                }
            }

            RowLayout {
                spacing: Theme.gap
                Layout.topMargin: 6

                Text {
                    text: "Artist column"
                    color: Theme.textDim
                    font.pixelSize: Theme.fontBody
                }
                Segmented {
                    options: [{ key: "110", label: "Narrow" }, { key: "170", label: "Normal" },
                              { key: "240", label: "Wide" }, { key: "320", label: "Wider" }]
                    current: String(App.artistColumnWidth)
                    onPicked: key => App.artistColumnWidth = Number(key)
                }
                Text {
                    text: "In song lists; the title takes the rest. Narrow windows give it less."
                    color: Theme.textFaint
                    font.pixelSize: Theme.fontSmall
                }
            }

            RowLayout {
                spacing: Theme.gap
                Layout.topMargin: 6

                Text {
                    text: "Font"
                    color: Theme.textDim
                    font.pixelSize: Theme.fontBody
                    Layout.rightMargin: 8
                }
                ComboBox {
                    id: fontBox
                    implicitWidth: 280
                    implicitHeight: 32
                    model: ["System default"].concat(App.fontFamilies)
                    currentIndex: Math.max(0, model.indexOf(App.fontFamily))
                    onActivated: index => App.fontFamily = index === 0 ? "" : model[index]
                    font.pixelSize: Theme.fontBody

                    background: Rectangle {
                        color: Theme.raised
                        border.color: fontBox.activeFocus || fontBox.popup.visible ? Theme.accent : Theme.line
                    }
                    contentItem: Text {
                        leftPadding: 10
                        text: fontBox.displayText
                        color: Theme.text
                        font.pixelSize: Theme.fontBody
                        font.family: fontBox.currentIndex > 0 ? fontBox.displayText : Qt.application.font.family
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }
                    indicator: Icon {
                        x: fontBox.width - width - 8
                        y: (fontBox.height - height) / 2
                        name: "down"
                        size: 16
                        color: Theme.textDim
                    }
                    delegate: ItemDelegate {
                        id: fontItem
                        required property string modelData
                        required property int index
                        width: fontBox.width
                        implicitHeight: 30
                        highlighted: fontBox.highlightedIndex === index
                        background: Rectangle { color: fontItem.highlighted ? Theme.hover : "transparent" }
                        contentItem: Text {
                            leftPadding: 4
                            text: fontItem.modelData
                            color: fontItem.index === fontBox.currentIndex ? Theme.accent : Theme.text
                            font.pixelSize: Theme.fontBody
                            font.family: fontItem.index > 0 ? fontItem.modelData : Qt.application.font.family
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }
                    }
                    popup: Popup {
                        y: fontBox.height
                        width: fontBox.width
                        implicitHeight: Math.min(contentItem.implicitHeight + 2, 320)
                        padding: 1
                        contentItem: ListView {
                            clip: true
                            implicitHeight: contentHeight
                            model: fontBox.popup.visible ? fontBox.delegateModel : null
                            currentIndex: fontBox.highlightedIndex
                            ScrollBar.vertical: ScrollBar {}
                        }
                        background: Rectangle {
                            color: Theme.raised
                            border.color: Theme.line
                        }
                    }
                }
            }

            RowLayout {
                spacing: Theme.gap
                Layout.topMargin: 6

                Text {
                    text: "Mouse wheel"
                    color: Theme.textDim
                    font.pixelSize: Theme.fontBody
                }
                Segmented {
                    options: [{ key: "0", label: "Windows (" + App.systemWheelLines + ")" },
                              { key: "1", label: "1" }, { key: "2", label: "2" }, { key: "3", label: "3" },
                              { key: "5", label: "5" }, { key: "8", label: "8" }, { key: "12", label: "12" },
                              { key: "20", label: "20" }]
                    current: String(App.wheelLines)
                    onPicked: key => App.wheelLines = Number(key)
                }
                Text {
                    text: "Lines a list moves for each notch of the wheel."
                    color: Theme.textFaint
                    font.pixelSize: Theme.fontSmall
                }
            }

            // Scale and font are read when the app starts.
            RowLayout {
                visible: App.restartRequired
                spacing: 12
                Layout.topMargin: 4
                Text {
                    text: "Restart kleulir to apply the new size or font."
                    color: Theme.estimated
                    font.pixelSize: Theme.fontBody
                }
                OutlineButton {
                    text: "Restart now"
                    onClicked: App.restart()
                }
            }
        }

        Divider {}

        // ---- Playback --------------------------------------------------------
        ColumnLayout {
            id: playback
            spacing: 10
            readonly property bool mpv: Audio.backend === "mpv"

            SectionTitle { text: "Playback" }

            GridLayout {
                columns: 2
                columnSpacing: 24
                rowSpacing: 12
                Layout.topMargin: 4

                Text { text: "Volume levelling"; color: Theme.textDim; font.pixelSize: Theme.fontBody }
                Segmented {
                    options: [
                        { key: "track", label: "Per track" },
                        { key: "album", label: "Per album" },
                        { key: "off", label: "Off" }
                    ]
                    current: Audio.replayGain
                    onPicked: key => Audio.replayGain = key
                }

                Text {
                    text: "Pre-amp"
                    color: Audio.replayGain === "off" ? Theme.textFaint : Theme.textDim
                    font.pixelSize: Theme.fontBody
                }
                RowLayout {
                    spacing: 12
                    enabled: Audio.replayGain !== "off"
                    opacity: enabled ? 1 : 0.4

                    Slider {
                        id: preamp
                        implicitWidth: 220
                        implicitHeight: 24
                        from: -12
                        to: 12
                        stepSize: 1
                        snapMode: Slider.SnapAlways
                        value: Audio.preamp
                        onMoved: Audio.preamp = value
                        background: Rectangle {
                            x: preamp.leftPadding
                            y: preamp.topPadding + (preamp.availableHeight - height) / 2
                            width: preamp.availableWidth
                            height: 3
                            color: Theme.hover
                            // Filled from the middle: 0 dB is the neutral point.
                            Rectangle {
                                readonly property real zero: parent.width / 2
                                readonly property real at: preamp.visualPosition * parent.width
                                x: Math.min(zero, at)
                                width: Math.abs(at - zero)
                                height: parent.height
                                color: Theme.text
                            }
                        }
                        handle: Rectangle {
                            x: preamp.leftPadding + preamp.visualPosition * (preamp.availableWidth - width)
                            y: preamp.topPadding + (preamp.availableHeight - height) / 2
                            width: 10
                            height: 16
                            color: Theme.text
                        }
                    }
                    Text {
                        text: (Audio.preamp > 0 ? "+" : "") + Audio.preamp.toFixed(0) + " dB"
                        color: Theme.text
                        font.pixelSize: Theme.fontBody
                        font.features: { "tnum": 1 }
                        Layout.preferredWidth: 48
                    }
                    IconButton {
                        text: "Reset"
                        visible: Audio.preamp !== 0
                        onClicked: Audio.preamp = 0
                    }
                }

                Text {
                    text: "Output device"
                    color: playback.mpv ? Theme.textDim : Theme.textFaint
                    font.pixelSize: Theme.fontBody
                }
                ComboBox {
                    id: deviceBox
                    // The chosen device stays listed while it is unplugged.
                    readonly property bool missing: Audio.outputDevice !== "auto"
                                                    && !Audio.outputDevices.some(d => d.id === Audio.outputDevice)
                    implicitWidth: 380
                    implicitHeight: 32
                    enabled: playback.mpv
                    opacity: enabled ? 1 : 0.4
                    textRole: "name"
                    valueRole: "id"
                    model: [{ id: "auto", name: "System default" }]
                        .concat(Audio.outputDevices)
                        .concat(missing ? [{ id: Audio.outputDevice, name: "Not connected (using system default)" }] : [])
                    currentIndex: Math.max(0, model.findIndex(d => d.id === Audio.outputDevice))
                    onActivated: index => Audio.outputDevice = model[index].id
                    font.pixelSize: Theme.fontBody

                    // `--demo-devices`: show the list, for a screenshot run.
                    Timer {
                        interval: 2500
                        running: Qt.application.arguments.indexOf("--demo-devices") >= 0
                        onTriggered: deviceBox.popup.open()
                    }

                    background: Rectangle {
                        color: Theme.raised
                        border.color: deviceBox.activeFocus || deviceBox.popup.visible ? Theme.accent : Theme.line
                    }
                    contentItem: Text {
                        leftPadding: 10
                        rightPadding: 28
                        text: deviceBox.displayText
                        color: Theme.text
                        font.pixelSize: Theme.fontBody
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }
                    indicator: Icon {
                        x: deviceBox.width - width - 8
                        y: (deviceBox.height - height) / 2
                        name: "down"
                        size: 16
                        color: Theme.textDim
                    }
                    delegate: ItemDelegate {
                        id: deviceItem
                        required property var modelData
                        required property int index
                        width: deviceBox.width
                        implicitHeight: 30
                        highlighted: deviceBox.highlightedIndex === index
                        background: Rectangle { color: deviceItem.highlighted ? Theme.hover : "transparent" }
                        contentItem: Text {
                            leftPadding: 4
                            text: deviceItem.modelData.name
                            color: deviceItem.index === deviceBox.currentIndex ? Theme.accent : Theme.text
                            font.pixelSize: Theme.fontBody
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }
                    }
                    popup: Popup {
                        y: deviceBox.height
                        width: deviceBox.width
                        implicitHeight: Math.min(contentItem.implicitHeight + 2, 320)
                        padding: 1
                        contentItem: ListView {
                            clip: true
                            implicitHeight: contentHeight
                            model: deviceBox.popup.visible ? deviceBox.delegateModel : null
                            currentIndex: deviceBox.highlightedIndex
                            ScrollBar.vertical: ScrollBar {}
                        }
                        background: Rectangle {
                            color: Theme.raised
                            border.color: Theme.line
                        }
                    }
                }
            }

            Hint {
                text: playback.mpv
                      ? "Levelling uses the ReplayGain values stored in the files, so tracks and albums play at a similar loudness."
                      : "mpv was not found, so the Windows media player is used: it cannot choose a device, and levels per track only."
            }
        }

        Divider {}

        // ---- Accent ----------------------------------------------------------
        ColumnLayout {
            spacing: 10

            SectionTitle { text: "Accent colour" }
            Hint { text: "Marks the current selection and the playing track." }

            Row {
                spacing: 8
                Layout.topMargin: 4

                Repeater {
                    model: Theme.accentPresets
                    delegate: AbstractButton {
                        id: swatch
                        required property var modelData
                        readonly property bool selected: Qt.colorEqual(Theme.accent, modelData.color)
                        implicitWidth: 64
                        implicitHeight: 64
                        hoverEnabled: true
                        Accessible.name: modelData.name
                        onClicked: Theme.setAccent(modelData.color)
                        background: Rectangle {
                            color: swatch.modelData.color
                            border.width: swatch.selected ? 2 : swatch.hovered ? 1 : 0
                            border.color: Theme.text
                        }
                        contentItem: Text {
                            text: swatch.modelData.name
                            color: Qt.color(swatch.modelData.color).hslLightness > 0.5 ? "#101010" : "#ffffff"
                            font.pixelSize: Theme.fontSmall
                            font.weight: Font.DemiBold
                            leftPadding: 6
                            bottomPadding: 4
                            verticalAlignment: Text.AlignBottom
                        }
                    }
                }
            }

            RowLayout {
                spacing: Theme.gap
                Layout.topMargin: 4

                Text {
                    text: "Hex"
                    color: Theme.textDim
                    font.pixelSize: Theme.fontBody
                }
                TextField {
                    id: hex
                    implicitWidth: 110
                    implicitHeight: 32
                    text: Theme.accent.toString()
                    color: Theme.text
                    font.pixelSize: Theme.fontBody
                    font.family: "Consolas"
                    maximumLength: 7
                    validator: RegularExpressionValidator { regularExpression: /^#[0-9a-fA-F]{6}$/ }
                    selectByMouse: true
                    onAccepted: Theme.setAccent(text)
                    background: Rectangle {
                        color: Theme.raised
                        border.color: hex.activeFocus ? Theme.accent : Theme.line
                    }
                }
                Rectangle {
                    implicitWidth: 32
                    implicitHeight: 32
                    color: hex.acceptableInput ? hex.text : Theme.accent
                    border.color: Theme.line
                }
                IconButton {
                    text: "Apply"
                    enabled: hex.acceptableInput && !Qt.colorEqual(Theme.accent, hex.text)
                    onClicked: Theme.setAccent(hex.text)
                }
                IconButton {
                    text: "Reset"
                    enabled: !Qt.colorEqual(Theme.accent, Theme.defaultAccent)
                    onClicked: Theme.setAccent(Theme.defaultAccent)
                }
            }
        }

        Divider {}

        // ---- Library ---------------------------------------------------------
        ColumnLayout {
            spacing: 8

            SectionTitle { text: "Library" }
            Hint { text: "Albums, artists and playlists are read from the server when kleulir starts. Read them again after something changed there." }

            RowLayout {
                spacing: Theme.gap
                Layout.topMargin: 4
                OutlineButton {
                    text: "Refresh"
                    enabled: !Library.loading
                    onClicked: Library.refreshAll()
                }
                Text {
                    text: Library.loading ? "Reading…"
                          : Library.error.length > 0 ? Library.error
                          : Library.albums.length + " albums"
                    color: Library.error.length > 0 ? Theme.estimated : Theme.textFaint
                    font.pixelSize: Theme.fontSmall
                }
            }
        }

        Divider {}

        // ---- Tray ------------------------------------------------------------
        ColumnLayout {
            spacing: 8

            SectionTitle { text: "System tray" }
            Hint { text: "Keeps kleulir running, and the music playing, without a window on the taskbar." }

            Toggle {
                Layout.topMargin: 4
                text: "Closing the window hides kleulir in the tray"
                checked: App.closeToTray
                onToggled: App.closeToTray = checked
            }
            Toggle {
                text: "Start kleulir with Windows" + (App.closeToTray ? ", hidden in the tray" : "")
                checked: App.startWithWindows
                onToggled: App.startWithWindows = checked
            }
        }

        Divider {}

        // ---- Account ---------------------------------------------------------
        ColumnLayout {
            spacing: 10

            SectionTitle { text: "Account" }

            GridLayout {
                columns: 2
                columnSpacing: 24
                rowSpacing: 6

                Text { text: "Server"; color: Theme.textDim; font.pixelSize: Theme.fontBody }
                Text { text: Session.serverUrl; color: Theme.text; font.pixelSize: Theme.fontBody }

                Text { text: "User"; color: Theme.textDim; font.pixelSize: Theme.fontBody }
                Text {
                    text: Session.username + (Session.admin ? "  (admin)" : "")
                    color: Theme.text
                    font.pixelSize: Theme.fontBody
                }

                Text { text: "Playback"; color: Theme.textDim; font.pixelSize: Theme.fontBody }
                Text {
                    text: Audio.backend === "mpv" ? "mpv" : "Windows media player (mpv not found)"
                    color: Theme.text
                    font.pixelSize: Theme.fontBody
                }

                Text { text: "Server type"; color: Theme.textDim; font.pixelSize: Theme.fontBody }
                Text {
                    text: Session.eosFeatures ? "eos (extended API available)" : "OpenSubsonic (standard API only)"
                    color: Theme.text
                    font.pixelSize: Theme.fontBody
                }
            }

            OutlineButton {
                Layout.topMargin: 4
                text: "Log out"
                // Forgets this device's key and returns to the login screen.
                onClicked: {
                    Player.clear()
                    Session.logout()
                }
            }
        }
    }
}
