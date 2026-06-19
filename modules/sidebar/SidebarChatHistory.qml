import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.config
import qs.modules.components
import qs.modules.services
import qs.modules.theme

/*!
    Chat-history overlay. Drops down inside the chat area whenever
    the parent toggles `expanded`. Shows the list of saved chats
    (from `Ai.chatHistory`), lets the user load or delete one, and
    gracefully renders an empty state when there are no chats yet.

    The delete button is implemented as a sibling `MouseArea` with
    `preventStealing: true` so its click never falls through to the
    row's "load chat" handler — that was the bug behind "no deja
    borrar chats" in the previous implementation.
*/
StyledRect {
    id: root

    variant: "bg"

    property bool expanded: false

    visible: opacity > 0
    opacity: expanded ? 1 : 0
    z: 10

    Behavior on opacity {
        AnimatedBehavior { type: "standard"; size: "normal" }
    }

    signal closeRequested()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 8

        // Header row
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: "Chat History"
                color: Colors.overSurface
                font.family: Config.theme.font
                font.pixelSize: 18
                font.weight: Font.Bold
                Layout.fillWidth: true
            }

            Text {
                visible: Ai.chatHistory && Ai.chatHistory.length > 0
                text: (Ai.chatHistory ? Ai.chatHistory.length : 0)
                      + " chat" + ((Ai.chatHistory && Ai.chatHistory.length === 1) ? "" : "s")
                color: Colors.outline
                font.family: Config.theme.font
                font.pixelSize: 11
            }

            Item {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28

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
                    text: Icons.cancel
                    font.family: Icons.font
                    font.pixelSize: 14
                    color: Colors.overSurface
                }
                MouseArea {
                    id: closeMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.closeRequested()
                }
            }
        }

        // Empty state
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !Ai.chatHistory || Ai.chatHistory.length === 0

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 8

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: Icons.robot
                    font.family: Icons.font
                    font.pixelSize: 48
                    color: Colors.outline
                    opacity: 0.3
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "No chats yet"
                    color: Colors.outline
                    font.family: Config.theme.font
                    font.pixelSize: 14
                    font.weight: Font.Medium
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Start a conversation to see it here."
                    color: Colors.outline
                    opacity: 0.7
                    font.family: Config.theme.font
                    font.pixelSize: 11
                }
            }
        }

        // Chat list
        ListView {
            id: historyList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            visible: Ai.chatHistory && Ai.chatHistory.length > 0
            model: Ai.chatHistory
            spacing: 4

            delegate: Item {
                id: chatRow
                required property var modelData
                required property int index

                width: historyList.width
                height: 56

                readonly property bool isCurrent: Ai.currentChatId === modelData.id

                StyledRect {
                    anchors.fill: parent
                    radius: Styling.radius(6)
                    variant: chatRow.isCurrent
                        ? "focus"
                        : (rowMa.containsMouse ? "common" : "transparent")
                }

                MouseArea {
                    id: rowMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Ai.loadChat(chatRow.modelData.id)
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 8
                    spacing: 8

                    Column {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 2

                        Text {
                            text: chatRow.modelData.title || "New Chat"
                            color: chatRow.isCurrent ? Styling.srItem("primary") : Colors.overSurface
                            font.family: Config.theme.font
                            font.pixelSize: 14
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                            width: parent.width
                        }

                        Row {
                            width: parent.width
                            spacing: 6

                            Text {
                                text: {
                                    let raw = chatRow.modelData.updatedAt || parseInt(chatRow.modelData.id) || 0;
                                    if (!raw) return "";
                                    let date = new Date(raw);
                                    return Qt.formatDateTime(date, "MMM dd, hh:mm");
                                }
                                color: chatRow.isCurrent ? Styling.srItem("primary") : Colors.outline
                                font.family: Config.theme.font
                                font.pixelSize: 11
                            }

                            Text {
                                visible: chatRow.modelData.messageCount > 0
                                text: "· " + chatRow.modelData.messageCount + " msg"
                                color: Colors.outline
                                font.family: Config.theme.font
                                font.pixelSize: 11
                            }

                            Text {
                                visible: !!(chatRow.modelData && chatRow.modelData.model && chatRow.modelData.model.length > 0)
                                text: "· " + (chatRow.modelData && chatRow.modelData.model || "")
                                color: Colors.outline
                                font.family: Config.theme.font
                                font.pixelSize: 11
                                opacity: 0.7
                                elide: Text.ElideRight
                            }
                        }
                    }

                    // Trash button. Always visible so users can discover it;
                    // highlights on hover. preventStealing + accepted=true keep
                    // the click from bubbling up to the row's load handler.
                    Item {
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: 32

                        StyledRect {
                            anchors.fill: parent
                            radius: Styling.radius(4)
                            variant: trashMa.containsMouse ? "errorfocus" : "transparent"
                            opacity: trashMa.containsMouse ? 0.6 : 0
                            Behavior on opacity {
                                AnimatedBehavior { type: "standard"; size: "small" }
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: Icons.trash
                            font.family: Icons.font
                            color: trashMa.containsMouse ? Colors.error : Colors.outline
                            font.pixelSize: 14
                            opacity: trashMa.containsMouse ? 1 : 0.6
                        }

                        MouseArea {
                            id: trashMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            preventStealing: true
                            onClicked: mouse => {
                                mouse.accepted = true;
                                console.log("SidebarChatHistory: deleting chat", chatRow.modelData.id);
                                Ai.deleteChat(chatRow.modelData.id);
                            }
                        }
                    }
                }
            }
        }
    }
}
