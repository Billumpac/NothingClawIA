import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.config
import qs.modules.components
import qs.modules.services
import qs.modules.theme

/*!
    Mode + agent selector row. Sits below the header and exposes:
      • A pill toggle between "Chat" (no tools) and "Agent" (with tools).
      • An agent picker dropdown that appears only when in agent mode
        and there is at least one configured agent.

    The dropdown lists every connection with status (connected/connecting/
    error), tool counts and an "Add agent…" entry at the bottom that
    opens the quick-add popup via the `openQuickAddAgent` signal.
*/
Item {
    id: root

    implicitHeight: 36

    signal openQuickAddAgent()

    // Local state for the dropdown — exposed so a parent click-elsewhere
    // handler can dismiss it.
    property alias dropdownOpen: agentDropdown.expanded

    RowLayout {
        id: modeRow
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        spacing: 6

        // ── Segmented mode selector (Chat | Agent) ─────────────────
        Row {
            spacing: 6
            Layout.preferredHeight: 28

            Repeater {
                model: [
                    { id: "chat",  label: "Chat",  icon: Icons.user },
                    { id: "agent", label: "Agent", icon: Icons.robot }
                ]

                delegate: Item {
                    id: modeBtn
                    required property var modelData
                    width: 64
                    height: 28

                    property bool isSelected: Ai.currentMode === modelData.id

                    StyledRect {
                        anchors.fill: parent
                        radius: Styling.radius(4)
                        variant: modeBtn.isSelected
                            ? "primary"
                            : (modeMa.containsMouse ? "focus" : "common")
                        enableShadow: modeBtn.isSelected
                    }

                    Row {
                        anchors.centerIn: parent
                        spacing: 4

                        Text {
                            text: modeBtn.modelData.icon
                            font.family: Icons.font
                            font.pixelSize: 12
                            color: modeBtn.isSelected ? Colors.overPrimary : Colors.overSurface
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: modeBtn.modelData.label
                            font.family: Config.theme.font
                            font.pixelSize: 11
                            font.weight: modeBtn.isSelected ? Font.Bold : Font.Normal
                            color: modeBtn.isSelected ? Colors.overPrimary : Colors.overSurface
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        id: modeMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Ai.setMode(modeBtn.modelData.id)
                    }
                }
            }
        }

        // ── Agent picker (visible only in agent mode AND with agents) ──
        Item {
            id: agentPicker
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            visible: Ai.currentMode === "agent"
                     && Ai.agentManager
                     && Ai.agentManager.connections.length > 0

            StyledRect {
                anchors.fill: parent
                radius: Styling.radius(4)
                variant: agentDropdown.expanded
                    ? "focus"
                    : (pickerMa.containsMouse ? "focus" : "common")
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 6

                Text {
                    text: Icons.robot
                    font.family: Icons.font
                    font.pixelSize: 12
                    color: (Ai.agentToolRegistry && Ai.agentToolRegistry.tools.length > 0)
                        ? Styling.srItem("overprimary") : Colors.outline
                }
                Text {
                    Layout.fillWidth: true
                    text: agentPicker._currentLabel()
                    font.family: Config.theme.font
                    font.pixelSize: 11
                    color: Colors.overSurface
                    elide: Text.ElideRight
                }
                Text {
                    text: agentDropdown.expanded ? Icons.caretUp : Icons.caretDown
                    font.family: Icons.font
                    font.pixelSize: 10
                    color: Colors.outline
                }
            }

            MouseArea {
                id: pickerMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: agentDropdown.expanded = !agentDropdown.expanded
            }

            function _currentLabel() {
                let id = Ai.currentAgentId || "";
                if (id === "") {
                    let n = Ai.agentToolRegistry ? Ai.agentToolRegistry.tools.length : 0;
                    return "All agents (" + n + " tool" + (n === 1 ? "" : "s") + ")";
                }
                let conns = Ai.agentManager ? Ai.agentManager.connections : [];
                for (let i = 0; i < conns.length; i++) {
                    if (conns[i] && conns[i].id === id) return conns[i].name;
                }
                return "All agents";
            }
        }
    }

    // ── Dropdown ────────────────────────────────────────────────────
    Item {
        id: agentDropdown
        anchors.top: parent.bottom
        anchors.topMargin: 4
        x: modeRow.width + 8
        width: 220
        z: 100
        visible: opacity > 0
        opacity: expanded ? 1 : 0
        height: dropdownColumn.height + 8

        property bool expanded: false

        Behavior on opacity {
            AnimatedBehavior { type: "standard"; size: "small" }
        }

        StyledRect {
            anchors.fill: parent
            radius: Styling.radius(6)
            variant: "popup"
            enableShadow: true
        }

        ColumnLayout {
            id: dropdownColumn
            anchors.fill: parent
            anchors.margins: 4
            spacing: 0

            // All agents
            DropdownRow {
                Layout.fillWidth: true
                label: "All agents"
                iconText: Icons.list
                selected: Ai.currentAgentId === ""
                onActivated: {
                    Ai.setAgent("");
                    agentDropdown.expanded = false;
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: 8
                Layout.rightMargin: 8
                height: 1
                color: Colors.outline
                opacity: 0.15
                visible: Ai.agentManager && Ai.agentManager.connections.length > 0
            }

            Repeater {
                model: Ai.agentManager ? Ai.agentManager.connections : []
                delegate: DropdownRow {
                    required property var modelData
                    Layout.fillWidth: true
                    label: modelData.name
                    sublabel: {
                        if (modelData.status === "error")
                            return modelData.statusMessage || "Error";
                        let tools = modelData.discoveredTools ? modelData.discoveredTools.length : 0;
                        return tools > 0
                            ? tools + " tool" + (tools === 1 ? "" : "s") + " · " + modelData.type
                            : modelData.type;
                    }
                    sublabelColor: modelData.status === "error" ? Colors.error : Colors.outline
                    iconText: modelData.status === "error" ? Icons.alert
                        : (modelData.status === "connecting" ? Icons.circleNotch
                        : (modelData.status === "connected" ? Icons.accept : Icons.circle))
                    iconColor: modelData.status === "error" ? Colors.error
                        : (modelData.status === "connected" ? Colors.success : Colors.outline)
                    iconSpinning: modelData.status === "connecting"
                    selected: Ai.currentAgentId === modelData.id
                    onActivated: {
                        Ai.setAgent(modelData.id);
                        agentDropdown.expanded = false;
                    }
                }
            }

            // Add agent…
            DropdownRow {
                Layout.fillWidth: true
                label: "Add agent…"
                iconText: Icons.plus
                iconColor: Styling.srItem("overprimary")
                labelColor: Styling.srItem("overprimary")
                onActivated: {
                    agentDropdown.expanded = false;
                    root.openQuickAddAgent();
                }
            }
        }
    }

    // Click-outside-to-close overlay that lives inside the sidebar instead
    // of expanding across the whole screen, so it never blocks clicks on
    // windows outside the sidebar.
    MouseArea {
        z: 99
        visible: agentDropdown.expanded
        anchors.fill: parent
        propagateComposedEvents: true
        onPressed: mouse => {
            // If the press is inside the dropdown, let the dropdown handle it.
            let local = agentDropdown.mapFromItem(parent, mouse.x, mouse.y);
            if (local.x >= 0 && local.x <= agentDropdown.width &&
                local.y >= 0 && local.y <= agentDropdown.height) {
                mouse.accepted = false;
                return;
            }
            agentDropdown.expanded = false;
            mouse.accepted = false;
        }
    }

    // ── Inline dropdown row component ──────────────────────────────
    component DropdownRow: Item {
        id: rowRoot
        height: sublabel.length > 0 ? 36 : 28

        property string label: ""
        property string sublabel: ""
        property string iconText: ""
        property color iconColor: Colors.overSurface
        property bool iconSpinning: false
        property color labelColor: Colors.overSurface
        property color sublabelColor: Colors.outline
        property bool selected: false

        signal activated()

        StyledRect {
            anchors.fill: parent
            anchors.margins: 2
            radius: Styling.radius(4)
            variant: rowRoot.selected
                ? "primaryfocus"
                : (rowMa.containsMouse ? "focus" : "transparent")
            opacity: rowRoot.selected ? 0.5 : (rowMa.containsMouse ? 1 : 0)
            Behavior on opacity {
                AnimatedBehavior { type: "standard"; size: "small" }
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 8

            Item {
                Layout.preferredWidth: 14
                Layout.preferredHeight: 14
                Text {
                    id: iconLabel
                    anchors.centerIn: parent
                    text: rowRoot.iconText
                    font.family: Icons.font
                    font.pixelSize: 12
                    color: rowRoot.iconColor

                    RotationAnimator on rotation {
                        target: iconLabel
                        running: rowRoot.iconSpinning
                        from: 0; to: 360
                        duration: 900
                        loops: Animation.Infinite
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Text {
                    Layout.fillWidth: true
                    text: rowRoot.label
                    color: rowRoot.selected ? Styling.srItem("overprimary") : rowRoot.labelColor
                    font.family: Config.theme.font
                    font.pixelSize: 11
                    font.weight: rowRoot.selected ? Font.Bold : Font.Normal
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    visible: rowRoot.sublabel.length > 0
                    text: rowRoot.sublabel
                    color: rowRoot.sublabelColor
                    font.family: Config.theme.font
                    font.pixelSize: 9
                    elide: Text.ElideRight
                }
            }

            Text {
                visible: rowRoot.selected
                text: Icons.accept
                font.family: Icons.font
                font.pixelSize: 11
                color: Styling.srItem("overprimary")
            }
        }

        MouseArea {
            id: rowMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: rowRoot.activated()
        }
    }
}
