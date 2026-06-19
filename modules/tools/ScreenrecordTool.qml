import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.modules.globals
import qs.config

PanelWindow {
    id: screenrecordPopup

    required property var targetScreen
    screen: targetScreen

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    visible: state !== "idle"
    exclusionMode: ExclusionMode.Ignore

    property string state: "idle" // idle, loading, active, processing
    property string currentMode: "region" // region, window, monitor, screen, portal
    property var activeWindows: []

    property bool recordAudioOutput: false
    property bool recordAudioInput: false

    property var focusedMonitor: null // List of monitor objects from compositor
    property string selectedMonitorName: "" // Pre-selected monitor (defaults to focused)

    function getModes() {
        return [
            {
                name: "audio",
                icon: recordAudioOutput ? Icons.speakerHigh : Icons.speakerSlash,
                tooltip: "Toggle Audio Output",
                type: "toggle",
                variant: recordAudioOutput ? "primary" : "focus"
            },
            {
                name: "mic",
                icon: recordAudioInput ? Icons.mic : Icons.micSlash,
                tooltip: "Toggle Microphone",
                type: "toggle",
                variant: recordAudioInput ? "primary" : "focus"
            },
            {
                type: "separator"
            },
            {
                name: "region",
                icon: Icons.regionScreenshot,
                tooltip: ScreenRecorder.canRecordDirectly ? "Region" : "Region (Unavailable on NixOS without config)",
                enabled: ScreenRecorder.canRecordDirectly
            },
            {
                name: "window",
                icon: Icons.windowScreenshot,
                tooltip: ScreenRecorder.canRecordDirectly ? "Window" : "Window (Unavailable on NixOS without config)",
                enabled: ScreenRecorder.canRecordDirectly
            },
            {
                name: "monitor",
                icon: Icons.recordScreen,
                tooltip: ScreenRecorder.canRecordDirectly ? "Monitor (click screen = focused, click btn = all)" : "Monitor (Unavailable on NixOS without config)",
                enabled: ScreenRecorder.canRecordDirectly
            },
            {
                name: "screen",
                icon: Icons.fullScreenshot,
                tooltip: ScreenRecorder.canRecordDirectly ? "All Monitors" : "All Monitors (Unavailable on NixOS without config)",
                enabled: ScreenRecorder.canRecordDirectly
            },
            {
                name: "portal",
                icon: Icons.aperture,
                tooltip: "Portal"
            }
        ];
    }

    function open() {
        if (modeGrid)
            modeGrid.currentIndex = ScreenRecorder.canRecordDirectly ? 3 : 7; // Default to region (3) or portal (7)
        screenrecordPopup.currentMode = ScreenRecorder.canRecordDirectly ? "region" : "portal";
        screenrecordPopup.recordAudioOutput = false;
        screenrecordPopup.recordAudioInput = false;
        screenrecordPopup.selectedMonitorName = "";
        ScreenRecorder.globalSelecting = false;

        // Fetch windows and monitors for window/monitor mode
        Screenshot.fetchWindows();

        // Go directly to active state (no freeze needed)
        screenrecordPopup.state = "active";

        // Request focus grab
        if (modeGrid)
            FocusGrabManager.requestGrab("screenrecordToolGrab");
    }

    function close() {
        screenrecordPopup.state = "idle";
        GlobalStates.screenRecordToolVisible = false;
        ScreenRecorder.globalSelecting = false;
        // Release the manual focus grab using the stable string ID.
        // Using a QML object reference (modeGrid) as grab ID is unsafe
        // because the object may be destroyed by the time close() runs,
        // causing releaseGrab to silently fail and hasActiveGrab to
        // stay true permanently.
        FocusGrabManager.releaseGrab("screenrecordToolGrab");
        Visibilities.setActiveModule("");
    }

    function executeCapture() {
        if (screenrecordPopup.currentMode === "screen") {
            // Default to "screen" (all monitors) for backwards compat
            ScreenRecorder.startRecording(screenrecordPopup.recordAudioOutput, screenrecordPopup.recordAudioInput, "screen", "");
            screenrecordPopup.close();
        } else if (screenrecordPopup.currentMode === "monitor") {
            // Specific monitor — set properties BEFORE calling startRecording
            let monName = screenrecordPopup.selectedMonitorName || "";
            ScreenRecorder.selectedMonitor = monName;
            ScreenRecorder.recordAllMonitors = (monName === "");
            ScreenRecorder.startRecording(
                screenrecordPopup.recordAudioOutput,
                screenrecordPopup.recordAudioInput,
                "monitor",
                ""
            );
            screenrecordPopup.close();
        } else if (screenrecordPopup.currentMode === "region") {
            if (ScreenRecorder.globalSelecting) {
                // Finalize the cross-monitor selection
                ScreenRecorder.globalSelecting = false;
                var gw = Math.abs(ScreenRecorder.globalCurrentX - ScreenRecorder.globalStartX);
                var gh = Math.abs(ScreenRecorder.globalCurrentY - ScreenRecorder.globalStartY);
                if (gw > 5 && gh > 5) {
                    var regionStr = gw + "x" + gh + "+"
                        + Math.min(ScreenRecorder.globalStartX, ScreenRecorder.globalCurrentX) + "+"
                        + Math.min(ScreenRecorder.globalStartY, ScreenRecorder.globalCurrentY);
                    ScreenRecorder.startRecording(screenrecordPopup.recordAudioOutput, screenrecordPopup.recordAudioInput, "region", regionStr);
                }
            }
            screenrecordPopup.close();
        } else if (screenrecordPopup.currentMode === "window") {
            // In window mode, capture handled by click
        } else if (screenrecordPopup.currentMode === "portal") {
            ScreenRecorder.startRecording(screenrecordPopup.recordAudioOutput, screenrecordPopup.recordAudioInput, "portal", "");
            screenrecordPopup.close();
        }
    }

    // Build monitor list from Screenshot's monitor list (already populated)
    // combined with ScreenRecorder's gpu-screen-recorder list as a fallback
    function getMonitorList() {
        // Prefer Screenshot's monitor list (has position, scale, focus info)
        if (screenrecordPopup.focusedMonitor &&
            Screenshot.monitors && Screenshot.monitors.length > 0) {
            return Screenshot.monitors;
        }
        // Fall back to ScreenRecorder's list (just name/resolution)
        return ScreenRecorder.monitors || [];
    }

    Connections {
        target: Screenshot
        function onMonitorsListReady(monitors) {
            screenrecordPopup.focusedMonitor = monitors.find(m => m.focused);
            // Pre-select the focused monitor by default
            if (!screenrecordPopup.selectedMonitorName && screenrecordPopup.focusedMonitor) {
                screenrecordPopup.selectedMonitorName = screenrecordPopup.focusedMonitor.name;
            }
        }
        function onWindowListReady(windows) {
            screenrecordPopup.activeWindows = windows;
        }
    }

    mask: Region {
        item: screenrecordPopup.visible ? fullMask : emptyMask
    }

    Item {
        id: fullMask
        anchors.fill: parent
    }

    Item {
        id: emptyMask
        width: 0
        height: 0
    }

    FocusGrab {
        id: focusGrab
        windows: [screenrecordPopup]
        active: screenrecordPopup.visible
    }

    FocusScope {
        id: mainFocusScope
        anchors.fill: parent
        focus: true

        Keys.onEscapePressed: screenrecordPopup.close()

        // Dimmer overlay (semi-transparent)
        Rectangle {
            anchors.fill: parent
            color: "black"
            opacity: screenrecordPopup.state === "active" ? 0.4 : 0
            visible: opacity > 0

            Behavior on opacity {
                enabled: Anim.animationsEnabled
                AnimatedBehavior {
                    type: "standard"
                    size: "normal"
                }
            }
        }

        Item {
            anchors.fill: parent
            visible: screenrecordPopup.state === "active" && screenrecordPopup.currentMode === "window"

            // Close when clicking outside any window
            TapHandler {
                onTapped: screenrecordPopup.close()
            }

            Repeater {
                model: screenrecordPopup.activeWindows
                delegate: Rectangle {
                    x: modelData.at[0] - screenrecordPopup.screen.x
                    y: modelData.at[1] - screenrecordPopup.screen.y
                    width: modelData.size[0]
                    height: modelData.size[1]
                    color: "transparent"
                    border.color: hoverHandler.hovered ? Styling.srItem("overprimary") : "transparent"
                    border.width: 2

                    Rectangle {
                        anchors.fill: parent
                        color: Styling.srItem("overprimary")
                        opacity: hoverHandler.hovered ? 0.2 : 0
                    }

                    HoverHandler {
                        id: hoverHandler
                    }

                    TapHandler {
                        onTapped: {
                            var w = Math.round(modelData.size[0]);
                            var h = Math.round(modelData.size[1]);
                            var x = Math.round(modelData.at[0]);
                            var y = Math.round(modelData.at[1]);

                            var regionStr = w + "x" + h + "+" + x + "+" + y;

                            ScreenRecorder.startRecording(screenrecordPopup.recordAudioOutput, screenrecordPopup.recordAudioInput, "region", regionStr);
                            screenrecordPopup.close();
                        }
                    }
                }
            }
        }

        MouseArea {
            id: regionArea
            anchors.fill: parent
            enabled: screenrecordPopup.state === "active" && (screenrecordPopup.currentMode === "region" || screenrecordPopup.currentMode === "screen" || screenrecordPopup.currentMode === "portal" || screenrecordPopup.currentMode === "monitor")
            hoverEnabled: true
            cursorShape: screenrecordPopup.currentMode === "region" ? Qt.CrossCursor : Qt.ArrowCursor

            onPressed: mouse => {
                if (screenrecordPopup.currentMode === "screen" || screenrecordPopup.currentMode === "portal" || screenrecordPopup.currentMode === "monitor") {
                    return;
                }

                // Global start point (screen-local → global)
                var gx = mouse.x + screenrecordPopup.screen.x;
                var gy = mouse.y + screenrecordPopup.screen.y;
                ScreenRecorder.globalStartX = gx;
                ScreenRecorder.globalStartY = gy;
                ScreenRecorder.globalCurrentX = gx;
                ScreenRecorder.globalCurrentY = gy;
                ScreenRecorder.globalSelecting = true;
            }

            onPositionChanged: mouse => {
                if (!ScreenRecorder.globalSelecting) return;
                var gx = mouse.x + screenrecordPopup.screen.x;
                var gy = mouse.y + screenrecordPopup.screen.y;
                ScreenRecorder.globalCurrentX = gx;
                ScreenRecorder.globalCurrentY = gy;
            }

            onReleased: {
                if (!ScreenRecorder.globalSelecting) return;
                ScreenRecorder.globalSelecting = false;
                
                var gw = Math.abs(ScreenRecorder.globalCurrentX - ScreenRecorder.globalStartX);
                var gh = Math.abs(ScreenRecorder.globalCurrentY - ScreenRecorder.globalStartY);
                
                if (gw > 5 && gh > 5) {
                    var regionStr = gw + "x" + gh + "+"
                        + Math.min(ScreenRecorder.globalStartX, ScreenRecorder.globalCurrentX) + "+"
                        + Math.min(ScreenRecorder.globalStartY, ScreenRecorder.globalCurrentY);

                    ScreenRecorder.startRecording(screenrecordPopup.recordAudioOutput, screenrecordPopup.recordAudioInput, "region", regionStr);
                    screenrecordPopup.close();
                } else {
                    screenrecordPopup.close();
                }
            }

            onClicked: {
                if (screenrecordPopup.currentMode === "screen") {
                    ScreenRecorder.startRecording(screenrecordPopup.recordAudioOutput, screenrecordPopup.recordAudioInput, "screen", "");
                    screenrecordPopup.close();
                } else if (screenrecordPopup.currentMode === "portal") {
                    ScreenRecorder.startRecording(screenrecordPopup.recordAudioOutput, screenrecordPopup.recordAudioInput, "portal", "");
                    screenrecordPopup.close();
                } else if (screenrecordPopup.currentMode === "monitor") {
                    if (screenrecordPopup.focusedMonitor && screenrecordPopup.focusedMonitor.name) {
                        ScreenRecorder.selectedMonitor = screenrecordPopup.focusedMonitor.name;
                        ScreenRecorder.recordAllMonitors = false;
                    } else {
                        ScreenRecorder.recordAllMonitors = true;
                    }
                    ScreenRecorder.startRecording(screenrecordPopup.recordAudioOutput, screenrecordPopup.recordAudioInput, "monitor", "");
                    screenrecordPopup.close();
                }
            }
        }

        // Global selection rectangle — clipped to current screen
        Rectangle {
            id: selectionRect
            visible: ScreenRecorder.globalSelecting && screenrecordPopup.state === "active" && screenrecordPopup.currentMode === "region"
            color: "transparent"
            border.color: Styling.srItem("overprimary")
            border.width: 2

            // Compute the global rect bounds
            readonly property int gLeft: Math.min(ScreenRecorder.globalStartX, ScreenRecorder.globalCurrentX)
            readonly property int gTop: Math.min(ScreenRecorder.globalStartY, ScreenRecorder.globalCurrentY)
            readonly property int gRight: Math.max(ScreenRecorder.globalStartX, ScreenRecorder.globalCurrentX)
            readonly property int gBottom: Math.max(ScreenRecorder.globalStartY, ScreenRecorder.globalCurrentY)

            // Screen bounds in global coords
            readonly property int sLeft: screenrecordPopup.screen.x
            readonly property int sTop: screenrecordPopup.screen.y
            readonly property int sRight: screenrecordPopup.screen.x + screenrecordPopup.screen.width
            readonly property int sBottom: screenrecordPopup.screen.y + screenrecordPopup.screen.height

            // Clip global rect to this screen — only draw the intersection
            readonly property int clipLeft: Math.max(gLeft, sLeft)
            readonly property int clipTop: Math.max(gTop, sTop)
            readonly property int clipRight: Math.min(gRight, sRight)
            readonly property int clipBottom: Math.min(gBottom, sBottom)

            x: clipLeft - sLeft
            y: clipTop - sTop
            width: Math.max(0, clipRight - clipLeft)
            height: Math.max(0, clipBottom - clipTop)

            Rectangle {
                anchors.fill: parent
                color: Styling.srItem("overprimary")
                opacity: 0.2
            }
        }

        AnimatedPopup {
            id: controlsPopup
            isOpen: screenrecordPopup.state === "active"
            transformOrigin: Item.Bottom
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottomMargin: 50

            width: modeGrid.width + 32
            height: modeGrid.height + 32

            Rectangle {
                id: controlsBar
                anchors.fill: parent

                radius: Styling.radius(20)
                color: Colors.background
                border.color: Colors.surface
                border.width: 1

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    preventStealing: true
                }

                ActionGrid {
                    id: modeGrid
                    anchors.centerIn: parent
                    actions: screenrecordPopup.getModes()
                    buttonSize: 48
                    iconSize: 24
                    spacing: 10

                    onCurrentIndexChanged: {
                        if (currentIndex > 2) {
                            var captureIndex = currentIndex - 3;
                            var captureOptions = ["region", "window", "monitor", "screen", "portal"];
                            if (captureIndex >= 0 && captureIndex < captureOptions.length) {
                                screenrecordPopup.currentMode = captureOptions[captureIndex];
                            }
                        }
                    }

                    onActionTriggered: action => {
                        if (action.tooltip === "Toggle Audio Output") {
                            screenrecordPopup.recordAudioOutput = !screenrecordPopup.recordAudioOutput;
                        } else if (action.tooltip === "Toggle Microphone") {
                            screenrecordPopup.recordAudioInput = !screenrecordPopup.recordAudioInput;
                        } else {
                            screenrecordPopup.executeCapture();
                        }
                    }
                }
            }
        }

    }

    // Safety net: release grab if the tool is destroyed without close()
    Component.onDestruction: {
        FocusGrabManager.releaseGrab("screenrecordToolGrab");
    }
}
