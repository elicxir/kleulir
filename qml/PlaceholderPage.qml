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
            text: "Not built yet"
            color: Theme.textFaint
            font.pixelSize: Theme.fontBody
        }
    }
}
