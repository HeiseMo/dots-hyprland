import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.sidebarLeft.aiChat
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

/**
 * Message bubble for the Agents tab.
 * - User messages: right-aligned rounded bubble
 * - Assistant messages: transparent content flow with tool call rows + typewriter streaming
 * No dependency on the Ai singleton.
 */
Item {
    id: root

    required property var messageData   // AiMessageData instance
    required property string modelId    // "claude-cli" | "codex" | "gemini-cli" | "kimi-cli"
    property bool renderMarkdown: true

    property bool copied: false

    readonly property var providerMeta: ({
        "claude-cli":  { name: "Claude Code", color: Appearance.colors.colTertiary },
        "codex":       { name: "Codex",       color: Appearance.colors.colPrimary },
        "gemini-cli":  { name: "Gemini",      color: Appearance.colors.colSecondary },
        "kimi-cli":    { name: "Kimi",        color: Appearance.colors.colSuccess },
    })
    readonly property var meta: providerMeta[root.modelId] ?? providerMeta["claude-cli"]

    readonly property var toolActionColors: ({
        "Edit":      Appearance.colors.colTertiary,
        "Write":     Appearance.colors.colTertiary,
        "Read":      Appearance.colors.colSecondary,
        "Glob":      Appearance.colors.colSecondary,
        "Grep":      Appearance.colors.colSecondary,
        "Bash":      Appearance.colors.colError,
        "WebFetch":  Appearance.colors.colPrimary,
        "WebSearch": Appearance.colors.colPrimary,
    })

    // ── Typewriter state ──────────────────────────────────────────────────
    readonly property string liveContent: root.messageData?.content ?? ""
    readonly property bool   isDone:      root.messageData?.done ?? false

    property string typewriterText: ""
    property int    typewriterPos:  0

    // What the content blocks render from
    readonly property string displayedContent: root.isDone ? root.liveContent : root.typewriterText
    property list<var> messageBlocks: StringUtils.splitMarkdownBlocks(root.displayedContent)

    Timer {
        id: typewriterTimer
        interval: 16   // ~60 fps
        repeat: true
        onTriggered: {
            const full = root.liveContent;
            if (root.typewriterPos >= full.length) { stop(); return; }
            const remaining = full.length - root.typewriterPos;
            // Adaptive batch: proportional to remaining so we naturally catch up
            const batch = Math.max(2, Math.min(remaining, Math.ceil(remaining * 0.15) + 2));
            root.typewriterPos = Math.min(root.typewriterPos + batch, full.length);
            root.typewriterText = full.substring(0, root.typewriterPos);
        }
    }

    onLiveContentChanged: {
        if (!root.isDone && !typewriterTimer.running)
            typewriterTimer.start();
    }

    onIsDoneChanged: {
        if (root.isDone) {
            typewriterTimer.stop();
            root.typewriterPos = root.liveContent.length;
            root.typewriterText = root.liveContent;
        }
    }

    implicitHeight: root.messageData?.role === "user" ? userBubble.implicitHeight : assistantRoot.implicitHeight

    // ── USER MESSAGE ──────────────────────────────────────────────────────
    Item {
        id: userBubble
        visible: root.messageData?.role === "user"
        anchors.right: parent.right
        implicitWidth: Math.min(userText.implicitWidth + 20, parent.width * 0.82)
        implicitHeight: userText.implicitHeight + 16

        Rectangle {
            anchors.fill: parent
            color: Qt.alpha(Appearance.m3colors.m3primaryContainer, 0.9)
            radius: Appearance.rounding.large

            StyledText {
                id: userText
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    leftMargin: 10
                    rightMargin: 10
                    topMargin: 8
                    bottomMargin: 8
                }
                text: root.messageData?.content ?? ""
                color: Appearance.m3colors.m3onPrimaryContainer
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.normal
            }
        }
    }

    // ── ASSISTANT MESSAGE ─────────────────────────────────────────────────
    Item {
        id: assistantRoot
        visible: root.messageData?.role === "assistant"
        anchors.left: parent.left
        anchors.right: parent.right
        implicitHeight: assistantCol.implicitHeight

        HoverHandler { id: hoverHandler }

        // Floating copy button — top-right, hover-reveal
        RippleButton {
            id: copyBtn
            anchors { top: parent.top; right: parent.right; topMargin: 2 }
            visible: hoverHandler.hovered || root.copied
            implicitWidth: 28
            implicitHeight: 28
            buttonRadius: Appearance.rounding.small
            colBackground: "transparent"
            colBackgroundHover: Appearance.colors.colLayer1Hover
            colRipple: Appearance.colors.colLayer1Active
            releaseAction: () => {
                Quickshell.clipboardText = root.messageData?.content ?? "";
                root.copied = true;
                copyResetTimer.restart();
            }

            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                text: root.copied ? "inventory" : "content_copy"
                iconSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }
        }

        Timer {
            id: copyResetTimer
            interval: 1500
            onTriggered: root.copied = false
        }

        ColumnLayout {
            id: assistantCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.rightMargin: 32  // leave room for copy button
            spacing: 4

            // ── Loading pulse (thinking, no content yet) ──────────────────
            Item {
                Layout.fillWidth: true
                implicitHeight: pulseLoader.shown ? 22 : 0  // 6px dots + padding; pulseRow not accessible outside sourceComponent
                visible: implicitHeight > 0

                Behavior on implicitHeight {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }

                FadeLoader {
                    id: pulseLoader
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    shown: (root.messageBlocks.length === 0) && !(root.messageData?.done ?? false)
                    sourceComponent: Row {
                        id: pulseRow
                        spacing: 5

                        Repeater {
                            model: 3
                            delegate: Rectangle {
                                required property int index
                                width: 6; height: 6; radius: 3
                                color: root.meta.color

                                SequentialAnimation on opacity {
                                    loops: Animation.Infinite
                                    running: pulseLoader.shown
                                    PauseAnimation { duration: index * 180 }
                                    NumberAnimation { from: 0.25; to: 1.0; duration: 400; easing.type: Easing.InOutSine }
                                    NumberAnimation { from: 1.0; to: 0.25; duration: 400; easing.type: Easing.InOutSine }
                                    PauseAnimation { duration: (2 - index) * 180 }
                                }
                            }
                        }
                    }
                }
            }

            // ── Tool call rows (expandable, like thinking blocks) ─────────
            Repeater {
                model: ScriptModel {
                    values: root.messageData?.toolCalls ?? []
                }
                delegate: ColumnLayout {
                    id: toolCallRow
                    required property var modelData
                    required property int index
                    // Alias so inner delegates can access the tool call without shadowing
                    readonly property var toolCall: modelData
                    Layout.fillWidth: true
                    spacing: 2

                    // ── Header row — always visible ───────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        // Colored status dot
                        Rectangle {
                            width: 7; height: 7; radius: 3.5
                            color: root.toolActionColors[modelData.name] ?? Appearance.colors.colSubtext
                            Layout.alignment: Qt.AlignVCenter
                        }

                        // Tool name
                        StyledText {
                            text: modelData.name
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Medium
                            color: root.toolActionColors[modelData.name] ?? Appearance.colors.colSubtext
                            Layout.alignment: Qt.AlignVCenter
                        }

                        // Primary argument (command, file, pattern…) — always visible
                        StyledText {
                            text: modelData.target ?? ""
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.family: (modelData.name === "Bash") ? Appearance.font.family.mono : Appearance.font.family.main
                            color: Appearance.colors.colSubtext
                            elide: Text.ElideMiddle
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                        }

                        // Output indicator pill — shows when output has been captured
                        Rectangle {
                            visible: (toolCallRow.toolCall?.output ?? "").length > 0
                            radius: Appearance.rounding.full
                            color: Qt.rgba(
                                (root.toolActionColors[modelData.name] ?? Appearance.colors.colSubtext).r,
                                (root.toolActionColors[modelData.name] ?? Appearance.colors.colSubtext).g,
                                (root.toolActionColors[modelData.name] ?? Appearance.colors.colSubtext).b,
                                0.15
                            )
                            implicitWidth: outputPillText.implicitWidth + 8
                            implicitHeight: outputPillText.implicitHeight + 4
                            Layout.alignment: Qt.AlignVCenter

                            StyledText {
                                id: outputPillText
                                anchors.centerIn: parent
                                text: "output"
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: root.toolActionColors[modelData.name] ?? Appearance.colors.colSubtext
                            }
                        }

                        // Expand toggle — visible when there are input details OR output
                        RippleButton {
                            visible: Object.keys(toolCallRow.toolCall?.input ?? {}).length > 0 || (toolCallRow.toolCall?.output ?? "").length > 0
                            Layout.alignment: Qt.AlignVCenter
                            implicitWidth: 20
                            implicitHeight: 20
                            buttonRadius: Appearance.rounding.small
                            colBackground: "transparent"
                            colBackgroundHover: Appearance.colors.colLayer1Hover
                            colRipple: Appearance.colors.colLayer1Active
                            releaseAction: () => {
                                const calls = root.messageData.toolCalls;
                                const updated = [...calls];
                                updated[index] = Object.assign({}, updated[index], { expanded: !updated[index].expanded });
                                root.messageData.toolCalls = updated;
                            }

                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                text: (modelData.expanded ?? false) ? "keyboard_arrow_up" : "keyboard_arrow_down"
                                iconSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                            }
                        }
                    }

                    // ── Expandable detail block ───────────────────────────
                    Item {
                        id: toolExpandArea
                        Layout.fillWidth: true
                        Layout.leftMargin: 13  // align with text after the dot
                        implicitHeight: (modelData.expanded ?? false) ? toolDetailCol.implicitHeight + 10 : 0
                        visible: implicitHeight > 0
                        clip: true

                        Behavior on implicitHeight {
                            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                        }

                        Rectangle {
                            anchors { fill: parent; topMargin: 4; bottomMargin: 4 }
                            color: Appearance.colors.colLayer2
                            radius: Appearance.rounding.small
                            implicitHeight: toolDetailCol.implicitHeight + 16

                            ColumnLayout {
                                id: toolDetailCol
                                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                                spacing: 6

                                // Input fields — render each meaningful key/value pair
                                Repeater {
                                    model: ScriptModel {
                                        values: {
                                            const inp = toolCallRow.toolCall?.input ?? {};
                                            const keys = ["command", "file_path", "new_string", "old_string",
                                                          "pattern", "path", "glob", "query", "url",
                                                          "description", "prompt"];
                                            return keys
                                                .filter(k => inp[k] !== undefined && String(inp[k]).length > 0)
                                                .map(k => ({ key: k, value: String(inp[k]) }));
                                        }
                                    }
                                    delegate: ColumnLayout {
                                        required property var modelData  // {key, value}
                                        Layout.fillWidth: true
                                        spacing: 2

                                        StyledText {
                                            text: modelData.key
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            font.weight: Font.Medium
                                            color: root.toolActionColors[toolCallRow.toolCall?.name] ?? Appearance.colors.colSubtext
                                            opacity: 0.7
                                        }

                                        StyledText {
                                            text: modelData.value
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            font.family: Appearance.font.family.mono
                                            color: Appearance.colors.colOnLayer1
                                            wrapMode: Text.Wrap
                                            Layout.fillWidth: true
                                            maximumLineCount: 12
                                            elide: Text.ElideRight
                                        }
                                    }
                                }

                                // Divider between input and output
                                Rectangle {
                                    visible: (toolCallRow.toolCall?.output ?? "").length > 0
                                             && Object.keys(toolCallRow.toolCall?.input ?? {}).length > 0
                                    Layout.fillWidth: true
                                    height: 1
                                    color: Appearance.colors.colOutline
                                    opacity: 0.3
                                }

                                // Output section
                                ColumnLayout {
                                    visible: (toolCallRow.toolCall?.output ?? "").length > 0
                                    Layout.fillWidth: true
                                    spacing: 2

                                    StyledText {
                                        text: "output"
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        font.weight: Font.Medium
                                        color: root.toolActionColors[toolCallRow.toolCall?.name] ?? Appearance.colors.colSubtext
                                        opacity: 0.7
                                    }

                                    StyledText {
                                        text: toolCallRow.toolCall?.output ?? ""
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        font.family: Appearance.font.family.mono
                                        color: Appearance.colors.colSubtext
                                        wrapMode: Text.Wrap
                                        Layout.fillWidth: true
                                        maximumLineCount: 20
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── Text / code / think content blocks ────────────────────────
            Repeater {
                model: ScriptModel {
                    values: root.messageBlocks
                }
                delegate: DelegateChooser {
                    id: messageDelegate
                    role: "type"

                    DelegateChoice {
                        roleValue: "code"
                        MessageCodeBlock {
                            editing: false
                            renderMarkdown: root.renderMarkdown
                            enableMouseSelection: false
                            segmentContent: modelData.content
                            segmentLang: modelData.lang
                            messageData: root.messageData
                        }
                    }
                    DelegateChoice {
                        roleValue: "think"
                        MessageThinkBlock {
                            editing: false
                            renderMarkdown: root.renderMarkdown
                            enableMouseSelection: false
                            segmentContent: modelData.content
                            messageData: root.messageData
                            done: root.messageData?.done ?? false
                            completed: modelData.completed ?? false
                        }
                    }
                    DelegateChoice {
                        roleValue: "text"
                        MessageTextBlock {
                            editing: false
                            renderMarkdown: root.renderMarkdown
                            enableMouseSelection: false
                            segmentContent: modelData.content
                            messageData: root.messageData
                            done: root.messageData?.done ?? false
                            forceDisableChunkSplitting: true  // typewriter handles progressive reveal
                        }
                    }
                }
            }
        }
    }
}
