import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.modules.globals
import qs.modules.services
import qs.config
import qs.modules.sidebar

PanelWindow {
    id: root

    required property ShellScreen targetScreen
    screen: targetScreen

    property bool active: false

    readonly property string sidebarPosition: GlobalStates.assistantPosition

    function _updateActive() {
        active = GlobalStates.assistantVisible
                && screen.name === GlobalStates.assistantScreenName;
    }

    Connections {
        target: GlobalStates
        function onAssistantVisibleChanged() { root._updateActive(); }
        function onAssistantScreenNameChanged() { root._updateActive(); }
    }

    Component.onCompleted: root._updateActive()

    // Force the Ai singleton to load at startup. The sidebar content
    // references Ai.currentChat, Ai.currentModel, etc., but those
    // bindings only evaluate when the sidebar becomes visible. By
    // touching Ai here, we guarantee models are fetched at boot.
    Timer {
        interval: 500
        repeat: false
        running: true
        onTriggered: {
            let _ = Ai.currentModel;
            _ = Ai.currentChat;
            _ = Ai.chatHistory;
            _ = KeyStore.initialized;
        }
    }

    readonly property int sidebarWidth: GlobalStates.assistantWidth
    readonly property bool sidebarPinned: GlobalStates.assistantPinned

    readonly property bool frameEnabled: Config.bar?.frameEnabled ?? false
    readonly property int frameThickness: Config.bar?.frameThickness ?? 6
    readonly property bool frameWrapped: frameEnabled && sidebarPinned
    readonly property int sidebarMargin: frameWrapped ? 0 : 4

    readonly property var bar: Visibilities.getBarForScreen(screen.name)
    readonly property var dock: Visibilities.getDockForScreen(screen.name)

    readonly property bool barEnabled: bar !== null
    readonly property string barPosition: bar ? bar.barPosition : "top"
    readonly property bool barPinned: bar ? bar.pinned : true
    readonly property int barTargetHeight: bar ? bar.barTargetHeight : 0
    readonly property int barTargetWidth: bar ? bar.barTargetWidth : 0
    readonly property int barOuterMargin: bar ? bar.baseOuterMargin : 0

    readonly property bool dockEnabled: dock !== null
    readonly property string dockPosition: dock ? dock.position : "bottom"
    readonly property bool dockPinned: dock ? dock.pinned : true
    readonly property int dockHeight: dock ? (dock.dockSize + dock.totalMargin) : 0

    visible: active
    color: "transparent"

    anchors {
        top: true
        bottom: true
        left: sidebarPosition === "left"
        right: sidebarPosition === "right"
    }

    implicitWidth: active ? (sidebarWidth + sidebarMargin + 8) : 0

    readonly property int topReservedMargin: {
        let margin = frameEnabled && !frameWrapped ? frameThickness : 0;
        if (barEnabled && barPosition === "top" && barPinned) {
            margin += barTargetHeight + barOuterMargin;
        }
        return margin;
    }
    readonly property int bottomReservedMargin: {
        let margin = frameEnabled && !frameWrapped ? frameThickness : 0;
        if (barEnabled && barPosition === "bottom" && barPinned) {
            margin += barTargetHeight + barOuterMargin;
        } else if (dockEnabled && dockPosition === "bottom" && dockPinned) {
            margin += dockHeight;
        }
        return margin;
    }

    AssistantSidebar {
        id: sidebarContent
        anchors.fill: parent
        anchors.topMargin: root.topReservedMargin
        anchors.bottomMargin: root.bottomReservedMargin
        targetScreen: root.targetScreen
    }

    // Overlay layer so the sidebar renders above tiled windows,
    // but with ExclusionMode.Ignore so clicks on transparent areas
    // pass through to windows behind. KeyboardFocus is OnDemand
    // so the input field only grabs focus when clicked.
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "nothingless:sidebar"
    WlrLayershell.keyboardFocus: active ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
}
