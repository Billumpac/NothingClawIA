import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.config
import qs.modules.components
import qs.modules.services
import qs.modules.globals
import qs.modules.theme

/*!
    Sidebar header. Houses the hamburger / current-chat title,
    the "new chat" action, the pin toggle, the agent-status badge
    (with tool count and quick-add shortcut), the position toggle
    and the close button. Emits intentions via signals so the parent
    decides what to do (toggle history, open quick-add, close…).
*/
Item {
    id: root

    implicitHeight: 40

    /*! true when the chat-history overlay is open; the hamburger
        and the title both render as “active” in that state. */
    property bool historyOpen: false

    signal toggleHistory()
    signal newChat()
    signal openQuickAddAgent()
    signal openSettings()
    signal closeRequested()

    function _currentTitle() {
        let id = Ai.currentChatId;
        let list = Ai.chatHistory || [];
        for (let i = 0; i < list.length; i++) {
            if (list[i] && list[i].id === id) {
                let t = list[i].title || "New chat";
                return t.length > 0 ? t : "New chat";
            }
        }
        return "New chat";
    }

    QtObject {
        id: agentSummary
        property int total: Ai.agentManager ? Ai.agentManager.connections.length : 0
        property int connected: {
            if (!Ai.agentManager) return 0;
            let c = 0;
            let conns = Ai.agentManager.connections;
            for (let i = 0; i < conns.length; i++) {
                if (conns[i] && conns[i].status === "connected") c++;
            }
            return c;
        }
        property int errors: {
            if (!Ai.agentManager) return 0;
            let c = 0;
            let conns = Ai.agentManager.connections;
            for (let i = 0; i < conns.length; i++) {
                if (conns[i] && conns[i].status === "error") c++;
            }
            return c;
        }
        property int toolCount: Ai.agentToolRegistry ? Ai.agentToolRegistry.tools.length : 0
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        spacing: 4

        // ── Hamburger (toggles the chat-history overlay) ────────────
        Item {
            Layout.preferredWidth: 32
            Layout.preferredHeight: 32

            StyledRect {
                anchors.fill: parent
                radius: Styling.radius(4)
                variant: hamburgerMa.containsMouse ? "focus" : "transparent"

                Behavior on opacity {
                    AnimatedBehavior { type: "standard"; size: "small" }
                }
            }

            Text {
                anchors.centerIn: parent
                text: Icons.list
                font.family: Icons.font
                font.pixelSize: 16
                color: root.historyOpen ? Styling.srItem("overprimary") : Colors.overSurface
            }

            MouseArea {
                id: hamburgerMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleHistory()
            }
        }

        // ── Current chat title (also opens history) ─────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            StyledRect {
                anchors.fill: parent
                anchors.margins: 4
                radius: Styling.radius(4)
                variant: titleMa.containsMouse ? "common" : "transparent"
                opacity: titleMa.containsMouse ? 0.5 : 0
                Behavior on opacity {
                    AnimatedBehavior { type: "standard"; size: "small" }
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                text: root._currentTitle()
                color: titleMa.containsMouse ? Colors.overPrimary : Colors.overSurface
                font.family: Config.theme.font
                font.pixelSize: 13
                font.weight: Font.Medium
                elide: Text.ElideRight
            }

            MouseArea {
                id: titleMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleHistory()
            }
        }

        // ── New chat ────────────────────────────────────────────────
        Item {
            Layout.preferredWidth: 32
            Layout.preferredHeight: 32

            StyledRect {
                anchors.fill: parent
                radius: Styling.radius(4)
                variant: newMa.containsMouse ? "focus" : "transparent"
                opacity: newMa.containsMouse ? 1 : 0
                Behavior on opacity {
                    AnimatedBehavior { type: "standard"; size: "small" }
                }
            }
            Text {
                anchors.centerIn: parent
                text: Icons.edit
                font.family: Icons.font
                font.pixelSize: 16
                color: Colors.overSurface
            }
            MouseArea {
                id: newMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.newChat()
                StyledToolTip {
                    visible: parent.containsMouse
                    tooltipText: "New chat"
                }
            }
        }

        // ── Pin toggle ──────────────────────────────────────────────
        Item {
            Layout.preferredWidth: 32
            Layout.preferredHeight: 32

            StyledRect {
                anchors.fill: parent
                radius: Styling.radius(4)
                variant: pinMa.containsMouse ? "focus" : "transparent"
                opacity: pinMa.containsMouse ? 1 : 0
                Behavior on opacity {
                    AnimatedBehavior { type: "standard"; size: "small" }
                }
            }
            Text {
                anchors.centerIn: parent
                text: Icons.pin
                font.family: Icons.font
                font.pixelSize: 16
                color: GlobalStates.assistantPinned ? Styling.srItem("overprimary") : Colors.overSurface
            }
            MouseArea {
                id: pinMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    GlobalStates.assistantPinned = !GlobalStates.assistantPinned;
                    Config.ai.sidebarPinnedOnStartup = GlobalStates.assistantPinned;
                }
                StyledToolTip {
                    visible: parent.containsMouse
                    tooltipText: GlobalStates.assistantPinned ? "Unpin sidebar" : "Pin sidebar"
                }
            }
        }

        Item { Layout.fillWidth: false; Layout.preferredWidth: 4 }

        // ── Agent indicator with tool-count badge ──────────────────
        Item {
            id: agentBadge
            Layout.preferredWidth: 32
            Layout.preferredHeight: 32

            StyledRect {
                anchors.fill: parent
                radius: Styling.radius(16)
                variant: {
                    if (agentSummary.total === 0) return "common";
                    if (agentSummary.errors > 0 && agentSummary.connected === 0) return "error";
                    if (agentSummary.connected > 0) return "primary";
                    return "secondary";
                }
            }
            Text {
                anchors.centerIn: parent
                text: agentSummary.total === 0 ? Icons.plus : Icons.robot
                font.family: Icons.font
                font.pixelSize: 14
                color: {
                    if (agentSummary.total === 0) return Colors.overSurface;
                    if (agentSummary.errors > 0 && agentSummary.connected === 0) return Colors.overError;
                    if (agentSummary.connected > 0) return Colors.overPrimary;
                    return Colors.overSecondary;
                }
            }
            Rectangle {
                visible: agentSummary.toolCount > 0
                width: 14
                height: 14
                radius: 7
                color: Colors.success
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.rightMargin: -2
                anchors.topMargin: -2

                Text {
                    anchors.centerIn: parent
                    text: agentSummary.toolCount > 9 ? "9+" : agentSummary.toolCount.toString()
                    color: "#000"
                    font.family: Config.theme.font
                    font.pixelSize: 8
                    font.weight: Font.Bold
                }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                hoverEnabled: true
                onClicked: {
                    if (agentSummary.total === 0)
                        root.openQuickAddAgent();
                    else
                        root.openSettings();
                }
                StyledToolTip {
                    visible: parent.containsMouse
                    tooltipText: {
                        if (agentSummary.total === 0)
                            return "No agents — click to add";
                        let parts = [];
                        parts.push(agentSummary.connected + "/" + agentSummary.total + " connected");
                        parts.push(agentSummary.toolCount + " tool" + (agentSummary.toolCount === 1 ? "" : "s"));
                        if (agentSummary.errors > 0)
                            parts.push(agentSummary.errors + " error(s)");
                        return parts.join(" · ") + " — click to manage";
                    }
                }
            }
        }

        // ── Position toggle (left/right) acts as a close trigger ────
        Item {
            Layout.preferredWidth: 32
            Layout.preferredHeight: 32

            StyledRect {
                anchors.fill: parent
                radius: Styling.radius(4)
                variant: closeMa.containsMouse ? "focus" : "transparent"
                opacity: closeMa.containsMouse ? 1 : 0
                Behavior on opacity {
                    AnimatedBehavior { type: "standard"; size: "small" }
                }
            }
            Text {
                anchors.centerIn: parent
                text: GlobalStates.assistantPosition === "right" ? Icons.caretRight : Icons.caretLeft
                font.family: Icons.font
                font.pixelSize: 16
                color: Colors.overSurface
            }
            MouseArea {
                id: closeMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.closeRequested()
                StyledToolTip {
                    visible: parent.containsMouse
                    tooltipText: "Hide sidebar"
                }
            }
        }
    }

    // Subtle bottom divider
    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: Colors.outline
        opacity: 0.15
    }
}
