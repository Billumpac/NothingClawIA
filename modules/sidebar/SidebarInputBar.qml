import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.config
import qs.modules.components
import qs.modules.services
import qs.modules.theme

/*!
    Input bar at the bottom of the sidebar. Handles:

      • Multi-line text input with slash-command suggestions popup.
      • Attachment chips (drag-and-drop, Ctrl+V paste from clipboard,
        file picker via zenity) with per-attachment remove.
      • Send button + Enter (without Shift) submit, Shift+Enter newline.
      • Forwarding submitted text + attachments to `Ai.sendMessage`.

    The supported slash commands are passed in as `slashCommands`,
    keeping this component agnostic of which commands are available.
*/
StyledRect {
    id: root

    /*! Whether to render in the welcome/empty layout (slightly bigger
        placeholder text). */
    property bool isWelcome: false

    /*! List of `{name, description}` commands shown in the suggestions
        popup when the user starts typing `/`. */
    property var slashCommands: []

    variant: "pane"
    radius: Styling.radius(4)
    enableShadow: true

    implicitHeight: attachmentPreview.implicitHeight + inputRow.implicitHeight + 16

    // ── Attachment state ──────────────────────────────────────────
    property var pendingAttachments: []

    function focusInput() {
        Qt.callLater(inputField.forceActiveFocus);
    }

    function _addAttachment(mimeType, base64Data, fileName) {
        let list = pendingAttachments.slice();
        list.push({
            type: "image",
            mimeType: mimeType,
            base64: base64Data,
            name: fileName
        });
        pendingAttachments = list;
    }

    function _removeAttachment(index) {
        let list = pendingAttachments.slice();
        list.splice(index, 1);
        pendingAttachments = list;
    }

    function _clearAttachments() {
        pendingAttachments = [];
    }

    function _normalizeFilePath(path) {
        let p = path ? String(path).trim() : "";
        if (p.startsWith("file://")) p = p.substring(7);
        try { p = decodeURIComponent(p); } catch (e) { }
        return p;
    }

    function _fileMimeForPath(path) {
        let ext = path.split(".").pop().toLowerCase();
        let map = {
            png: "image/png", jpg: "image/jpeg", jpeg: "image/jpeg",
            gif: "image/gif", webp: "image/webp", bmp: "image/bmp"
        };
        return map[ext] || "";
    }

    function _addAttachmentFromFile(path) {
        let filePath = _normalizeFilePath(path);
        if (!filePath) return;
        let mimeType = _fileMimeForPath(filePath);
        if (!mimeType) {
            Ai.pushSystemMessage("Only image files are supported for attachments.");
            return;
        }
        attachmentReader.run(filePath, mimeType, filePath.split("/").pop());
    }

    function _addAttachmentsFromUriList(text) {
        let lines = String(text).split("\n");
        for (let i = 0; i < lines.length; i++) {
            let line = lines[i].trim();
            if (line === "" || line.startsWith("#")) continue;
            _addAttachmentFromFile(line);
        }
    }

    function _submit() {
        let txt = inputField.text;
        if (txt.trim().length === 0 && pendingAttachments.length === 0) return;
        Ai.sendMessage(txt.trim(), pendingAttachments.length > 0 ? pendingAttachments : undefined);
        inputField.text = "";
        _clearAttachments();
    }

    DropArea {
        anchors.fill: parent
        onDropped: drop => {
            if (drop.urls && drop.urls.length > 0) {
                for (let i = 0; i < drop.urls.length; i++)
                    root._addAttachmentFromFile(drop.urls[i]);
                drop.accepted = true;
                return;
            }
            if (drop.text && drop.text.length > 0) {
                root._addAttachmentsFromUriList(drop.text);
                drop.accepted = true;
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 0
        spacing: 4

        // ── Attachments preview strip ────────────────────────────
        Flickable {
            id: attachmentPreview
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            Layout.topMargin: visible ? 8 : 0
            visible: root.pendingAttachments.length > 0
            implicitHeight: visible ? Math.min(contentHeight, 120) : 0
            Layout.preferredHeight: implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height

            contentWidth: width
            contentHeight: attachmentsFlow.height

            Flow {
                id: attachmentsFlow
                width: attachmentPreview.width
                spacing: 6

                Repeater {
                    model: root.pendingAttachments

                    delegate: Item {
                        id: attRoot
                        required property var modelData
                        required property int index
                        width: 52
                        height: 52

                        StyledRect {
                            anchors.fill: parent
                            anchors.margins: 2
                            variant: "common"
                            radius: Styling.radius(6)

                            Image {
                                anchors.fill: parent
                                anchors.margins: 2
                                source: "data:" + attRoot.modelData.mimeType + ";base64," + attRoot.modelData.base64
                                fillMode: Image.PreserveAspectCrop
                                sourceSize.width: 48
                                sourceSize.height: 48
                            }
                        }

                        Rectangle {
                            anchors.top: parent.top
                            anchors.right: parent.right
                            width: 16
                            height: 16
                            radius: 8
                            color: Colors.surfaceBright
                            z: 2

                            Text {
                                anchors.centerIn: parent
                                text: Icons.cancel
                                font.family: Icons.font
                                font.pixelSize: 9
                                color: Colors.overSurface
                            }

                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -2
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root._removeAttachment(attRoot.index)
                            }
                        }
                    }
                }
            }
        }

        // ── Input row ────────────────────────────────────────────
        RowLayout {
            id: inputRow
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 8
            Layout.topMargin: attachmentPreview.visible ? 4 : 8
            Layout.bottomMargin: 8
            spacing: 4

            ScrollView {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(120, Math.max(28, inputField.contentHeight + 12))

                TextArea {
                    id: inputField
                    focus: true
                    activeFocusOnTab: true
                    placeholderText: root.isWelcome ? "Ask AI or type /help..." : "Message AI..."
                    placeholderTextColor: Colors.outline
                    font.family: Config.theme.font
                    font.pixelSize: 14
                    color: Colors.overSurface
                    wrapMode: TextEdit.Wrap
                    background: null

                    onTextChanged: suggestionsModel.refresh(text)

                    Keys.onPressed: event => {
                        if (suggestionsPopup.visible) {
                            if (event.key === Qt.Key_Up) {
                                suggestionsPopup.selectPrevious();
                                event.accepted = true;
                                return;
                            }
                            if (event.key === Qt.Key_Down) {
                                suggestionsPopup.selectNext();
                                event.accepted = true;
                                return;
                            }
                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Tab) {
                                suggestionsPopup.applySelection();
                                event.accepted = true;
                                return;
                            }
                        }
                        if (event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier)) {
                            clipboardReader.tryPaste();
                            return;
                        }
                        if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier)) {
                            root._submit();
                            event.accepted = true;
                        }
                    }
                }
            }

            // Attach file
            Item {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32

                StyledRect {
                    anchors.fill: parent
                    radius: Styling.radius(16)
                    variant: attachMa.containsMouse ? "focus" : "transparent"
                }
                Text {
                    anchors.centerIn: parent
                    text: Icons.plus
                    font.family: Icons.font
                    font.pixelSize: 18
                    color: Colors.outline
                }
                MouseArea {
                    id: attachMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: filePicker.open()
                    StyledToolTip {
                        visible: parent.containsMouse
                        tooltipText: "Attach image"
                    }
                }
            }

            // Send
            Item {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                visible: inputField.text.length > 0 || root.pendingAttachments.length > 0

                StyledRect {
                    anchors.fill: parent
                    radius: Styling.radius(16)
                    variant: sendMa.containsMouse ? "primaryfocus" : "primary"
                }
                Text {
                    anchors.centerIn: parent
                    text: Icons.paperPlane
                    font.family: Icons.font
                    font.pixelSize: 16
                    color: Colors.overPrimary
                }
                MouseArea {
                    id: sendMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root._submit()
                }
            }
        }
    }

    // ── Suggestions popup (slash commands) ─────────────────────────
    Popup {
        id: suggestionsPopup
        parent: root
        y: -height - 8
        x: 0
        width: root.width
        height: Math.min(suggestionsList.contentHeight + 8, root.isWelcome ? 130 : 220)
        padding: 0
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        visible: inputField.text.startsWith("/") && suggestionsModel.count > 0

        background: StyledRect {
            variant: "popup"
            radius: Styling.radius(8)
            enableShadow: true
        }

        function selectNext() {
            suggestionsList.currentIndex = (suggestionsList.currentIndex + 1) % Math.max(1, suggestionsModel.count);
        }
        function selectPrevious() {
            let n = Math.max(1, suggestionsModel.count);
            suggestionsList.currentIndex = (suggestionsList.currentIndex - 1 + n) % n;
        }
        function applySelection() {
            if (suggestionsList.currentIndex < 0 || suggestionsList.currentIndex >= suggestionsModel.count)
                return;
            let item = suggestionsModel.get(suggestionsList.currentIndex);
            inputField.text = "/" + item.name + " ";
            inputField.cursorPosition = inputField.text.length;
            inputField.forceActiveFocus();
        }

        ListView {
            id: suggestionsList
            anchors.fill: parent
            anchors.margins: 4
            clip: true
            currentIndex: 0
            highlightMoveDuration: 0
            model: ListModel { id: suggestionsModel
                function refresh(text) {
                    suggestionsModel.clear();
                    if (!text.startsWith("/")) return;
                    let q = text.substring(1).toLowerCase();
                    for (let i = 0; i < root.slashCommands.length; i++) {
                        let cmd = root.slashCommands[i];
                        if (cmd.name.startsWith(q))
                            suggestionsModel.append({ name: cmd.name, description: cmd.description });
                    }
                    suggestionsList.currentIndex = 0;
                }
            }
            delegate: Item {
                id: sgRow
                required property int index
                required property string name
                required property string description
                width: suggestionsList.width
                height: 36

                readonly property bool isCurrent: ListView.isCurrentItem

                StyledRect {
                    anchors.fill: parent
                    anchors.margins: 2
                    radius: Styling.radius(4)
                    variant: sgRow.isCurrent ? "focus" : (sgMa.containsMouse ? "common" : "transparent")
                    opacity: sgRow.isCurrent || sgMa.containsMouse ? 1 : 0
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 8

                    Text {
                        text: "/" + sgRow.name
                        font.family: Config.theme.font
                        font.weight: Font.Bold
                        color: sgRow.isCurrent ? Styling.srItem("overprimary") : Colors.overSurface
                    }
                    Text {
                        text: sgRow.description
                        font.family: Config.theme.font
                        color: Colors.outline
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                }
                MouseArea {
                    id: sgMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        suggestionsList.currentIndex = sgRow.index;
                        suggestionsPopup.applySelection();
                    }
                }
            }
        }
    }

    // ── Subprocess helpers ────────────────────────────────────────

    QtObject {
        id: filePicker
        function open() { proc.running = true; }
        property Process proc: Process {
            command: ["zenity", "--file-selection",
                      "--file-filter=Images | *.png *.jpg *.jpeg *.gif *.webp *.bmp",
                      "--file-filter=All files | *"]
            stdout: StdioCollector {
                onStreamFinished: {
                    let path = String(text).trim();
                    if (path.length > 0) root._addAttachmentFromFile(path);
                }
            }
        }
    }

    QtObject {
        id: attachmentReader
        property string _filePath: ""
        property string _mimeType: ""
        property string _fileName: ""

        function run(filePath, mimeType, fileName) {
            _filePath = filePath;
            _mimeType = mimeType;
            _fileName = fileName;
            // Build the base64 command. We single-quote the path with
            // shell-escape rules to avoid breaking on filenames with
            // spaces or special characters.
            let escaped = filePath.replace(/'/g, "'\\''");
            proc.command = ["bash", "-c", "/usr/bin/base64 -w 0 '" + escaped + "'"];
            proc.running = true;
        }

        property Process proc: Process {
            stdout: StdioCollector {
                onStreamFinished: {
                    let data = String(text).trim();
                    if (data.length > 0)
                        root._addAttachment(attachmentReader._mimeType,
                                            data,
                                            attachmentReader._fileName);
                    else if (attachmentReader._filePath.length > 0)
                        Ai.pushSystemMessage("Failed to read attachment data.");
                }
            }
            stderr: StdioCollector { id: attErr }
            onExited: exitCode => {
                if (exitCode !== 0) {
                    let err = String(attErr.text).trim();
                    Ai.pushSystemMessage("Failed to read attachment: " + (err.length > 0 ? err : "unknown error"));
                }
            }
        }
    }

    QtObject {
        id: clipboardReader

        function tryPaste() { typesProc.running = true; }

        property Process typesProc: Process {
            command: ["wl-paste", "--list-types"]
            stdout: StdioCollector {
                onStreamFinished: {
                    let types = String(text).trim().split("\n");
                    let img = "";
                    for (let i = 0; i < types.length; i++) {
                        if (types[i].startsWith("image/")) {
                            img = types[i].trim();
                            break;
                        }
                    }
                    if (img.length > 0) {
                        clipboardReader._mimeType = img;
                        imgProc.command = ["bash", "-c",
                            "wl-paste --type \"" + img + "\" 2>/dev/null | /usr/bin/base64 -w 0"];
                        imgProc.running = true;
                        return;
                    }
                    if (types.indexOf("text/uri-list") !== -1) {
                        uriProc.running = true;
                        return;
                    }
                    // Plain text on the clipboard: let the user paste
                    // it normally (Qt's TextArea already handles that
                    // automatically). Don't show an error.
                }
            }
        }

        property string _mimeType: ""

        property Process imgProc: Process {
            stdout: StdioCollector {
                onStreamFinished: {
                    let data = String(text).trim();
                    if (data.length === 0) {
                        Ai.pushSystemMessage("Clipboard image read returned no data.");
                        return;
                    }
                    let ext = clipboardReader._mimeType.split("/")[1] || "png";
                    root._addAttachment(clipboardReader._mimeType, data, "clipboard." + ext);
                }
            }
        }

        property Process uriProc: Process {
            command: ["wl-paste", "--type", "text/uri-list"]
            stdout: StdioCollector {
                onStreamFinished: {
                    let data = String(text).trim();
                    if (data.length > 0) root._addAttachmentsFromUriList(data);
                }
            }
        }
    }
}
