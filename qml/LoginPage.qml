import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Kleulir

// Shown over the whole window until a session is ready.
Rectangle {
    id: root
    color: Theme.bg

    readonly property bool busy: Session.state === Session.Connecting
    readonly property bool offline: Session.state === Session.Offline

    function submit() {
        if (!root.busy)
            Session.login(server.text, user.text, password.text)
    }

    component Field: TextField {
        Layout.fillWidth: true
        implicitHeight: 36
        color: Theme.text
        placeholderTextColor: Theme.textFaint
        font.pixelSize: Theme.fontBody
        leftPadding: 10
        selectByMouse: true
        enabled: !root.busy
        onAccepted: root.submit()
        background: Rectangle {
            color: Theme.raised
            border.color: parent.activeFocus ? Theme.accent : Theme.line
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: 340
        spacing: 10

        Text {
            text: "kleulir"
            color: Theme.text
            font.pixelSize: 28
            font.weight: Font.Bold
            font.letterSpacing: 0.5
        }
        Text {
            Layout.bottomMargin: 12
            text: root.offline ? "Saved server: " + Session.serverUrl : "Connect to your eos server"
            color: Theme.textDim
            font.pixelSize: Theme.fontBody
        }

        Field {
            id: server
            visible: !root.offline
            placeholderText: "Server address  (http://host:4540)"
            text: Session.serverUrl
            inputMethodHints: Qt.ImhUrlCharactersOnly
        }
        Field {
            id: user
            visible: !root.offline
            placeholderText: "Username"
            text: Session.username
        }
        Field {
            id: password
            visible: !root.offline
            placeholderText: "Password"
            echoMode: TextInput.Password
        }

        Text {
            Layout.fillWidth: true
            visible: Session.error.length > 0
            text: Session.error
            color: Theme.estimated
            font.pixelSize: Theme.fontSmall
            wrapMode: Text.Wrap
        }

        AbstractButton {
            id: go
            Layout.fillWidth: true
            Layout.topMargin: 6
            implicitHeight: 38
            hoverEnabled: true
            enabled: !root.busy
            onClicked: root.offline ? Session.retry() : root.submit()
            background: Rectangle {
                color: !go.enabled ? Theme.raised : go.down ? Theme.textDim : go.hovered ? "#ffffff" : Theme.text
            }
            contentItem: Text {
                text: root.busy ? "Connecting…" : root.offline ? "Retry" : "Log in"
                color: go.enabled ? Theme.bg : Theme.textFaint
                font.pixelSize: Theme.fontBody
                font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }
        IconButton {
            Layout.fillWidth: true
            visible: root.offline
            text: "Use a different server"
            onClicked: Session.logout()
        }

        Text {
            Layout.fillWidth: true
            Layout.topMargin: 8
            visible: !root.offline
            text: "The password is exchanged for a key for this device. Only the key is stored, in the Windows Credential Manager."
            color: Theme.textFaint
            font.pixelSize: 11
            wrapMode: Text.Wrap
        }
    }
}
