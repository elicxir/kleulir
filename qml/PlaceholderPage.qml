import QtQuick
import Kleulir

Item {
    property string title: ""

    Column {
        anchors.centerIn: parent
        spacing: Theme.gap

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: title
            color: Theme.text
            font.pixelSize: Theme.fontTitle
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "この画面はまだ作っていません"
            color: Theme.textFaint
            font.pixelSize: Theme.fontBody
        }
    }
}
