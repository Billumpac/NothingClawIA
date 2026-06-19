import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.modules.theme
import qs.modules.components
import qs.modules.globals
import qs.config

FloatingWindow {
    id: root

    property string sourceScreenName: GlobalStates.desktopMirrorSourceScreenName
    property bool paused: false
    property bool fullscreen: false
    property int windowWidth: 640
    property int windowHeight: 360
    property int minSize: 160

    readonly property var selectedScreen: {
        if (!Quickshell.screens || Quickshell.screens.length === 0) return null;
        if (root.sourceScreenName) {
            for (let i = 0; i < Quickshell.screens.length; i++) {
                if (Quickshell.screens[i].name === root.sourceScreenName) return Quickshell.screens[i];
            }
        }
        return Quickshell.screens[0];
    }

    visible: true
    color: "transparent"
    width: root.windowWidth
    height: root.windowHeight
    screen: root.selectedScreen || (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)

    Component.onCompleted: {
        if (screen) {
            x = Math.max(0, (screen.width - width) / 2);
            y = Math.max(0, (screen.height - height) / 2);
        }
    }

    onFullscreenChanged: {
        if (fullscreen && screen) {
            x = 0;
            y = 0;
            width = screen.width;
            height = screen.height;
        } else if (screen) {
            width = windowWidth;
            height = windowHeight;
            x = Math.max(0, (screen.width - width) / 2);
            y = Math.max(0, (screen.height - height) / 2);
        }
    }

    StyledRect {
        id: container
        anchors.fill: parent
        variant: "bg"
        radius: root.fullscreen ? 0 : Styling.radius(0)
        clip: true

        ScreencopyView {
            id: screencopy
            anchors.fill: parent
            captureSource: root.selectedScreen
            live: !root.paused
            paintCursor: true
            visible: root.selectedScreen !== null
        }

        Rectangle {
            anchors.fill: parent
            visible: root.selectedScreen === null
            color: "black"

            Column {
                anchors.centerIn: parent
                spacing: 8
                Text {
                    text: Icons.monitor
                    font.family: Icons.font
                    font.pixelSize: 48
                    color: Colors.outline
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                Text {
                    text: "No screen selected"
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-1)
                    color: Colors.outline
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }

        Rectangle {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 12
            visible: root.selectedScreen !== null && root.screen === root.selectedScreen
            color: Qt.rgba(Colors.error.r, Colors.error.g, Colors.error.b, 0.85)
            radius: 6
            width: warningRow.implicitWidth + 16
            height: warningRow.implicitHeight + 8

            RowLayout {
                id: warningRow
                anchors.centerIn: parent
                spacing: 6
                Text {
                    text: Icons.warningCircle
                    font.family: Icons.font
                    font.pixelSize: 12
                    color: Colors.onError
                }
                Text {
                    text: "Mirroring the same screen causes feedback"
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-3)
                    color: Colors.onError
                }
            }
        }

        MouseArea {
            id: dragArea
            anchors.fill: parent
            hoverEnabled: true
            enabled: !root.fullscreen

            property point globalStartPoint: Qt.point(0, 0)
            property int startX: 0
            property int startY: 0

            onPressed: mouse => {
                globalStartPoint = mapToItem(null, mouse.x, mouse.y);
                startX = root.x;
                startY = root.y;
            }

            onPositionChanged: mouse => {
                if (pressed) {
                    const p = mapToItem(null, mouse.x, mouse.y);
                    root.x = startX + (p.x - globalStartPoint.x);
                    root.y = startY + (p.y - globalStartPoint.y);
                }
            }

            Row {
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottomMargin: 16
                spacing: 12
                z: 10

                opacity: dragArea.containsMouse || controlHover.containsMouse ? 1.0 : 0.0
                Behavior on opacity {
                    enabled: Anim.animationsEnabled
                    AnimatedBehavior { type: "standard"; size: "small" }
                }

                HoverHandler {
                    id: controlHover
                }

                StyledRect {
                    width: 36
                    height: 36
                    radius: 18
                    variant: "common"

                    Text {
                        anchors.centerIn: parent
                        text: root.paused ? Icons.play : Icons.pause
                        font.family: Icons.font
                        font.pixelSize: 16
                        color: Colors.overBackground
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.paused = !root.paused
                    }
                }

                StyledRect {
                    width: 36
                    height: 36
                    radius: 18
                    variant: "common"

                    Text {
                        anchors.centerIn: parent
                        text: root.fullscreen ? Icons.arrowsOut : Icons.arrowsOut
                        font.family: Icons.font
                        font.pixelSize: 16
                        color: Colors.overBackground
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.fullscreen = !root.fullscreen
                    }
                }

                StyledRect {
                    width: 36
                    height: 36
                    radius: 18
                    variant: "common"

                    Text {
                        anchors.centerIn: parent
                        text: Icons.sync
                        font.family: Icons.font
                        font.pixelSize: 16
                        color: Colors.overBackground
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.cycleSource()
                    }

                    ToolTip.visible: parent.containsMouse
                    ToolTip.delay: 500
                    ToolTip.text: "Switch source"
                }

                StyledRect {
                    width: 36
                    height: 36
                    radius: 18
                    variant: "error"

                    Text {
                        anchors.centerIn: parent
                        text: Icons.cancel
                        font.family: Icons.font
                        font.pixelSize: 16
                        color: Styling.srItem("error")
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: GlobalStates.desktopMirrorWindowVisible = false
                    }
                }
            }
        }

        ResizeHandle {
            id: resizeBR
            mode: 0
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            visible: !root.fullscreen
        }
    }

    function cycleSource() {
        if (!Quickshell.screens || Quickshell.screens.length <= 1) return;
        let idx = 0;
        for (let i = 0; i < Quickshell.screens.length; i++) {
            if (Quickshell.screens[i] === root.selectedScreen) {
                idx = i;
                break;
            }
        }
        const next = (idx + 1) % Quickshell.screens.length;
        GlobalStates.desktopMirrorSourceScreenName = Quickshell.screens[next].name;
    }

    component ResizeHandle: MouseArea {
        property int mode: 0
        width: 18
        height: 18
        hoverEnabled: true
        preventStealing: true
        cursorShape: (mode === 0 || mode === 3) ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor
        z: 11

        property point startPoint: Qt.point(0, 0)
        property int startW: 0
        property int startH: 0
        property int startX: 0
        property int startY: 0

        onPressed: mouse => {
            startPoint = mapToItem(null, mouse.x, mouse.y);
            startW = root.width;
            startH = root.height;
            startX = root.x;
            startY = root.y;
            mouse.accepted = true;
        }

        onPositionChanged: mouse => {
            if (pressed) {
                const p = mapToItem(null, mouse.x, mouse.y);
                const dx = p.x - startPoint.x;
                const dy = p.y - startPoint.y;

                let newW = startW;
                let newH = startH;
                let newX = startX;
                let newY = startY;

                if (mode === 0) {
                    newW = Math.max(root.minSize, startW + dx);
                    newH = Math.max(root.minSize, startH + dy);
                } else if (mode === 1) {
                    newW = Math.max(root.minSize, startW - dx);
                    newH = Math.max(root.minSize, startH + dy);
                    newX = startX + (startW - newW);
                } else if (mode === 2) {
                    newW = Math.max(root.minSize, startW + dx);
                    newH = Math.max(root.minSize, startH - dy);
                    newY = startY + (startH - newH);
                } else if (mode === 3) {
                    newW = Math.max(root.minSize, startW - dx);
                    newH = Math.max(root.minSize, startH - dy);
                    newX = startX + (startW - newW);
                    newY = startY + (startH - newH);
                }

                root.windowWidth = newW;
                root.windowHeight = newH;
                root.width = newW;
                root.height = newH;
                root.x = newX;
                root.y = newY;
            }
        }

        Text {
            anchors.centerIn: parent
            text: mode === 0 || mode === 3 ? Icons.caretDoubleDown : Icons.caretDoubleUp
            rotation: mode === 0 ? -45 : mode === 1 ? 45 : mode === 2 ? -135 : 135
            font.family: Icons.font
            color: Styling.srItem("overprimary")
            font.pixelSize: 10
            opacity: (dragArea.containsMouse || parent.containsMouse) ? 0.8 : 0
        }
    }

    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_F) {
            root.fullscreen = !root.fullscreen;
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape) {
            if (root.fullscreen) {
                root.fullscreen = false;
            } else {
                GlobalStates.desktopMirrorWindowVisible = false;
            }
            event.accepted = true;
        } else if (event.key === Qt.Key_Space) {
            root.paused = !root.paused;
            event.accepted = true;
        }
    }
}
