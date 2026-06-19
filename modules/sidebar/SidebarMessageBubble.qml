import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.config
import qs.modules.components
import qs.modules.services
import qs.modules.theme

/*!
    Delegate for a single chat message. Renders four distinct
    shapes depending on the message role:

      * user      → primary-coloured bubble on the right with the
                    user avatar (or Icons.user fallback).
      * assistant → secondary-coloured bubble on the left with the
                    robot avatar. Supports markdown + code blocks,
                    chain-of-thought collapse, tool-call cards,
                    edit / copy / regenerate actions.
      * system    → narrow surface card centred under the avatar.
      * function  → a "tool result" panel containing the captured
                    output of the previous tool call.

    Heavy logic is delegated to `Ai.qml` (approve / reject / edit
    / regenerate / model selection); this component is purely
    presentational.
*/
Item {
    id: root

    required property var modelData
    required property int index
    required property real listWidth

    // Where in the chat array does this delegate live? Used to
    // forward edit / regenerate / approve / reject calls to Ai.
    readonly property bool isUser: modelData && modelData.role === "user"
    readonly property bool isAssistant: modelData && modelData.role === "assistant"
    readonly property bool isSystem: modelData && modelData.role === "system"
    readonly property bool isFunctionResult: modelData && modelData.role === "function"

    property bool isEditing: false
    property bool retryMode: false

    signal modelPickerRequested(int messageIndex)

    width: listWidth
    height: layout.height + 8

    // ── Avatar (left for assistant/system, right for user) ─────────
    Item {
        id: avatar
        width: 32
        height: 32
        visible: !root.isSystem && !root.isFunctionResult
        anchors.top: parent.top
        anchors.topMargin: 4

        anchors.left: root.isUser ? undefined : parent.left
        anchors.right: root.isUser ? parent.right : undefined
        anchors.leftMargin: root.isUser ? 0 : 10
        anchors.rightMargin: root.isUser ? 10 : 0

        StyledRect {
            anchors.fill: parent
            radius: Styling.radius(16)
            variant: "primary"
            visible: !root.isUser

            Text {
                anchors.centerIn: parent
                text: Icons.robot
                font.family: Icons.font
                color: Colors.overPrimary
                font.pixelSize: 18
            }
        }

        ClippingRectangle {
            anchors.fill: parent
            radius: Styling.radius(16)
            color: Colors.surfaceDim
            visible: root.isUser

            Image {
                anchors.fill: parent
                mipmap: true
                source: "file://" + Quickshell.env("HOME") + "/.face.icon"
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: 32
                sourceSize.height: 32
                onStatusChanged: {
                    if (status === Image.Error) source = "";
                }

                Text {
                    anchors.centerIn: parent
                    text: Icons.user
                    font.family: Icons.font
                    color: Colors.overPrimary
                    visible: parent.status !== Image.Ready
                }
            }
        }
    }

    // ── Bubble layout ──────────────────────────────────────────────
    Item {
        id: layout
        anchors.top: parent.top
        anchors.left: root.isUser ? parent.left : (avatar.right)
        anchors.right: root.isUser ? avatar.left : parent.right
        anchors.leftMargin: root.isUser ? 10 : 12
        anchors.rightMargin: root.isUser ? 12 : 10
        height: childrenRect.height

        // Action toolbar (hover-revealed). Sits *next to* the bubble
        // on the user side and on the right side for the assistant.
        Row {
            id: actionsRow
            spacing: 4
            opacity: bubbleHoverMa.containsMouse || root.isEditing ? 1 : 0
            visible: opacity > 0
            anchors.verticalCenter: bubble.verticalCenter

            anchors.left: root.isUser ? undefined : bubble.right
            anchors.right: root.isUser ? bubble.left : undefined
            anchors.leftMargin: 6
            anchors.rightMargin: 6

            Behavior on opacity {
                AnimatedBehavior { type: "standard"; size: "small" }
            }

            ActionIcon {
                visible: !root.isFunctionResult
                icon: root.isEditing ? Icons.accept : Icons.edit
                onClicked: {
                    if (root.isEditing) {
                        Ai.updateMessage(root.index, editArea.text);
                        root.isEditing = false;
                    } else {
                        root.isEditing = true;
                        editArea.forceActiveFocus();
                        editArea.cursorPosition = editArea.text.length;
                    }
                }
            }

            ActionIcon {
                visible: !root.isEditing
                icon: Icons.copy
                onClicked: {
                    copyHelper.copy(root.modelData.content || "");
                }
            }

            ActionIcon {
                visible: root.isAssistant && !root.isEditing
                icon: Icons.arrowCounterClockwise
                onClicked: Ai.regenerateResponse(root.index)
            }
        }

        MouseArea {
            id: bubbleHoverMa
            anchors.fill: bubble
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
        }

        // Function results render with a plain panel.
        StyledRect {
            id: bubble
            anchors.left: root.isUser ? undefined : parent.left
            anchors.right: root.isUser ? parent.right : undefined
            width: {
                if (root.isFunctionResult) return parent.width;
                let avail = root.listWidth * (root.isSystem ? 0.9 : 0.7);
                return Math.min(Math.max(bubbleContent.implicitWidth + 32, 140), avail);
            }
            height: bubbleContent.implicitHeight + 24

            variant: {
                if (root.isFunctionResult) return "internalbg";
                if (root.isSystem) return "common";
                return root.isUser ? "primary" : "secondary";
            }
            radius: Styling.radius(4)
            border.width: root.isSystem || root.isEditing ? 1 : 0
            border.color: root.isEditing ? Styling.srItem("overprimary") : Colors.surfaceDim

            ColumnLayout {
                id: bubbleContent
                anchors.centerIn: parent
                width: parent.width - 32
                spacing: 8

                // Function result header (only for role=function)
                RowLayout {
                    Layout.fillWidth: true
                    visible: root.isFunctionResult
                    spacing: 6

                    Text {
                        text: root.modelData.is_error ? Icons.alert : Icons.accept
                        font.family: Icons.font
                        font.pixelSize: 12
                        color: root.modelData.is_error ? Colors.error : Colors.success
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.modelData.is_error
                            ? ("Tool error" + (root.modelData.name ? ": " + root.modelData.name : ""))
                            : ("Tool result" + (root.modelData.name ? ": " + root.modelData.name : ""))
                        font.family: Config.theme.font
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        color: root.modelData.is_error ? Colors.error : Colors.success
                        elide: Text.ElideRight
                    }
                }

                // Markdown / code segmented content
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: !root.isEditing
                    spacing: 8

                    Repeater {
                        model: root._splitContent(root.modelData.content || "")

                        delegate: Loader {
                            Layout.fillWidth: true
                            required property var modelData
                            sourceComponent: modelData.type === "code" ? codeComponent : textComponent

                            Component {
                                id: textComponent
                                TextEdit {
                                    width: bubbleContent.width
                                    text: parent.modelData.content
                                    textFormat: root.isFunctionResult ? Text.PlainText : Text.MarkdownText
                                    color: root._contentColor()
                                    font.family: root.isFunctionResult ? Config.theme.monoFont : Config.theme.font
                                    font.pixelSize: root.isFunctionResult ? 11 : 14
                                    wrapMode: Text.Wrap
                                    readOnly: true
                                    selectByMouse: true
                                    onLinkActivated: link => Qt.openUrlExternally(link)
                                }
                            }

                            Component {
                                id: codeComponent
                                CodeBlock {
                                    width: bubbleContent.width
                                    code: parent.modelData.content
                                    language: parent.modelData.language
                                }
                            }
                        }
                    }
                }

                // Edit area
                TextEdit {
                    id: editArea
                    Layout.fillWidth: true
                    visible: root.isEditing
                    text: root.modelData.content || ""
                    textFormat: Text.PlainText
                    color: root._contentColor()
                    font.family: Config.theme.font
                    font.pixelSize: 14
                    wrapMode: Text.Wrap
                    selectByMouse: true
                }

                // Chain of thought (reasoning_content for DeepSeek/R1)
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    visible: !!root.modelData.reasoningContent

                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Colors.outline
                        opacity: 0.2
                    }

                    Text {
                        text: "Chain of Thought"
                        color: Colors.outline
                        font.family: Config.theme.font
                        font.weight: Font.Bold
                        font.pixelSize: 11
                    }

                    StyledRect {
                        Layout.fillWidth: true
                        variant: "internalbg"
                        radius: Styling.radius(4)

                        TextEdit {
                            padding: 8
                            width: parent.width
                            text: root.modelData.reasoningContent || ""
                            font.family: Config.theme.monoFont
                            color: Colors.outline
                            readOnly: true
                            wrapMode: Text.Wrap
                            font.pixelSize: 12
                        }
                    }
                }

                // Tool call (function call card)
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    visible: root.modelData.functionCall !== undefined && !!root.modelData.functionCall

                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Colors.outline
                        opacity: 0.2
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            text: (root.modelData.functionCall && root.modelData.functionCall.name === "run_shell_command")
                                ? Icons.terminal : Icons.robot
                            font.family: Icons.font
                            font.pixelSize: 12
                            color: Styling.srItem("overprimary")
                        }
                        Text {
                            text: (root.modelData.functionCall && root.modelData.functionCall.name === "run_shell_command")
                                ? "Run Command"
                                : ("Tool: " + (root.modelData.functionCall ? root.modelData.functionCall.name : ""))
                            color: Styling.srItem("overprimary")
                            font.family: Config.theme.font
                            font.weight: Font.Bold
                            font.pixelSize: 12
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }

                    StyledRect {
                        Layout.fillWidth: true
                        variant: "internalbg"
                        radius: Styling.radius(4)

                        TextEdit {
                            padding: 8
                            width: parent.width
                            text: {
                                if (!root.modelData.functionCall) return "";
                                let n = root.modelData.functionCall.name;
                                let a = root.modelData.functionCall.args || {};
                                if (n === "run_shell_command" && a.command) return a.command;
                                try { return JSON.stringify(a, null, 2); }
                                catch (e) { return String(a); }
                            }
                            font.family: Config.theme.monoFont
                            color: Colors.overSurface
                            readOnly: true
                            wrapMode: Text.WrapAnywhere
                            selectByMouse: true
                        }
                    }

                    RowLayout {
                        visible: root.modelData.functionPending === true
                        Layout.alignment: Qt.AlignRight
                        spacing: 8

                        ApprovalButton {
                            label: "Reject"
                            danger: true
                            onClicked: Ai.rejectCommand(root.index)
                        }
                        ApprovalButton {
                            label: "Approve"
                            danger: false
                            onClicked: Ai.approveCommand(root.index)
                        }
                    }

                    Text {
                        visible: root.modelData.functionApproved === true
                        text: (root.modelData.functionCall && root.modelData.functionCall.name === "run_shell_command")
                            ? "Command approved" : "Tool approved"
                        color: Colors.success
                        font.family: Config.theme.font
                        font.pixelSize: 11
                    }
                    Text {
                        visible: root.modelData.functionApproved === false && root.modelData.functionPending !== true
                        text: (root.modelData.functionCall && root.modelData.functionCall.name === "run_shell_command")
                            ? "Command rejected" : "Tool rejected"
                        color: Colors.error
                        font.family: Config.theme.font
                        font.pixelSize: 11
                    }
                }
            }
        }

        // Model indicator beneath assistant bubbles
        Text {
            id: modelIndicator
            anchors.top: bubble.bottom
            anchors.topMargin: 4
            anchors.left: bubble.left
            anchors.leftMargin: 4
            visible: root.isAssistant && !!root.modelData.model
            text: root.retryMode ? ("Retry with another model " + Icons.caretRight) : (root.modelData.model || "")
            color: Colors.outline
            font.family: Config.theme.font
            font.pixelSize: Styling.fontSize(-2)
            font.weight: Font.Medium

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (root.retryMode) {
                        root.modelPickerRequested(root.index);
                        root.retryMode = false;
                    } else {
                        root.retryMode = true;
                        retryTimer.restart();
                    }
                }
            }

            Timer {
                id: retryTimer
                interval: 5000
                onTriggered: root.retryMode = false
            }
        }
    }

    // ── Helpers ────────────────────────────────────────────────────

    function _splitContent(txt) {
        let parts = [];
        if (!txt) {
            parts.push({ type: "text", content: "(no output)", language: "" });
            return parts;
        }
        let regex = /```(\w*)\n([\s\S]*?)```/g;
        let lastIndex = 0;
        let match;
        while ((match = regex.exec(txt)) !== null) {
            if (match.index > lastIndex) {
                parts.push({
                    type: "text",
                    content: txt.substring(lastIndex, match.index),
                    language: ""
                });
            }
            parts.push({
                type: "code",
                content: match[2].trim(),
                language: match[1] || "text"
            });
            lastIndex = regex.lastIndex;
        }
        if (lastIndex < txt.length) {
            parts.push({
                type: "text",
                content: txt.substring(lastIndex),
                language: ""
            });
        }
        if (parts.length === 0)
            parts.push({ type: "text", content: txt, language: "" });
        return parts;
    }

    function _contentColor() {
        if (isFunctionResult) {
            return modelData && modelData.is_error ? Colors.error : Colors.overSurface;
        }
        if (isSystem) return Colors.outline;
        if (isUser) return Styling.srItem("primary");
        return Styling.srItem("secondary");
    }

    // ── Tiny embedded helpers ──────────────────────────────────────

    component ActionIcon: Item {
        id: btn
        width: 24
        height: 24
        property string icon: ""
        signal clicked()

        StyledRect {
            anchors.fill: parent
            radius: Styling.radius(4)
            variant: btnMa.containsMouse ? "focus" : "common"
            opacity: btnMa.containsMouse ? 1 : 0.3
            Behavior on opacity {
                AnimatedBehavior { type: "standard"; size: "small" }
            }
        }
        Text {
            anchors.centerIn: parent
            text: btn.icon
            font.family: Icons.font
            font.pixelSize: 12
            color: Colors.overSurface
        }
        MouseArea {
            id: btnMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }

    component ApprovalButton: Item {
        id: appr
        width: label.implicitWidth + 28
        height: 30
        property string label: ""
        property bool danger: false
        signal clicked()

        StyledRect {
            anchors.fill: parent
            radius: Styling.radius(4)
            variant: appr.danger
                ? (apprMa.containsMouse ? "errorfocus" : "error")
                : (apprMa.containsMouse ? "primaryfocus" : "primary")
            opacity: appr.danger && !apprMa.containsMouse ? 0.7 : 1
        }
        Text {
            id: label
            anchors.centerIn: parent
            text: appr.label
            color: appr.danger ? Colors.overError : Colors.overPrimary
            font.family: Config.theme.font
            font.pixelSize: 12
            font.weight: Font.Bold
        }
        MouseArea {
            id: apprMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: appr.clicked()
        }
    }

    // ── Clipboard helper ───────────────────────────────────────────
    QtObject {
        id: copyHelper

        function copy(text) {
            copyProc.command = ["wl-copy", "--", text];
            copyProc.running = true;
        }

        property Process copyProc: Process {
            running: false
        }
    }
}
