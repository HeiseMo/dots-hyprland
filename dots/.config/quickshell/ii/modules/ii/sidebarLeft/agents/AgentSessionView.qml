import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions as CF
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

/**
 * Chat UI for a single AgentSession instance.
 * Renders messages via AgentMessage and provides an input field with:
 *   - Slash command menu (/ popup above input)
 *   - Attachment chips (files/images queued for next message)
 *   - Mode badge (bottom-right of input area; click or Shift+Tab to cycle)
 *   - Plus button (left of input; opens file/image picker shortcut)
 */
Item {
    id: root

    required property var session  // AgentSession instance

    property real inputPadding: 5
    property var pendingAttachments: []  // [{type, path, name}]

    readonly property var providerMeta: ({
        "claude-cli":  { name: "Claude Code", color: Appearance.colors.colTertiary },
        "codex":       { name: "Codex",       color: Appearance.colors.colPrimary },
        "gemini-cli":  { name: "Gemini",      color: Appearance.colors.colSecondary },
        "kimi-cli":    { name: "Kimi",        color: Appearance.colors.colSuccess },
    })
    readonly property var meta: providerMeta[root.session?.modelId ?? "claude-cli"] ?? providerMeta["claude-cli"]

    // ── Mode cycling ──────────────────────────────────────────────────────
    function cycleMode() {
        const s = root.session;
        if (!s) return;
        if (s.modelId === "claude-cli") {
            const modes = ["plan", "default", "acceptEdits", "auto", "dontAsk", "bypassPermissions"];
            const i = modes.indexOf(s.permissionMode);
            s.permissionMode = modes[(i + 1) % modes.length];
        } else if (s.modelId === "codex") {
            const modes = ["suggest", "auto-edit", "full-auto"];
            const i = modes.indexOf(s.approvalMode);
            s.approvalMode = modes[(i + 1) % modes.length];
        }
    }

    readonly property string currentMode: {
        if (!root.session) return "";
        if (root.session.modelId === "claude-cli") return root.session.permissionMode ?? "";
        if (root.session.modelId === "codex") return root.session.approvalMode ?? "";
        return "";
    }

    readonly property bool hasModeControl: root.session?.modelId === "claude-cli" || root.session?.modelId === "codex"

    readonly property color modeColor: {
        const m = root.currentMode;
        if (m === "plan" || m === "suggest")        return Appearance.colors.colSubtext;
        if (m === "default" || m === "acceptEdits" || m === "auto-edit") return Appearance.colors.colTertiary;
        return Appearance.colors.colError;  // auto, full-auto, dontAsk, bypassPermissions
    }

    // ── Attachment file reading ────────────────────────────────────────────
    property int _loadingAttachmentIndex: -1

    FileView {
        id: attachmentReader
        onLoaded: {
            const i = root._loadingAttachmentIndex;
            if (i < 0 || i >= root.pendingAttachments.length) return;
            const updated = [...root.pendingAttachments];
            updated[i] = Object.assign({}, updated[i], { content: attachmentReader.text() });
            root.pendingAttachments = updated;
            root._loadingAttachmentIndex = -1;
            // Load next pending attachment if any
            _loadNextAttachment();
        }
        onLoadFailed: error => {
            root._loadingAttachmentIndex = -1;
            _loadNextAttachment();
        }
    }

    function _loadNextAttachment() {
        for (let i = 0; i < root.pendingAttachments.length; i++) {
            const att = root.pendingAttachments[i];
            if (att.type === "file" && !att.content) {
                root._loadingAttachmentIndex = i;
                attachmentReader.path = Qt.resolvedUrl(att.path);
                attachmentReader.reload();
                return;
            }
        }
    }

    function _queueAttachment(att) {
        root.pendingAttachments = [...root.pendingAttachments, att];
        if (att.type === "file" && root._loadingAttachmentIndex < 0)
            _loadNextAttachment();
    }

    // ── Attachment helpers ─────────────────────────────────────────────────
    function _buildMessageWithAttachments(text) {
        if (root.pendingAttachments.length === 0) return text;
        let prefix = "";
        for (const att of root.pendingAttachments) {
            if (att.type === "file") {
                prefix += "```" + att.name + "\n" + (att.content ?? "") + "\n```\n\n";
            } else if (att.type === "image") {
                prefix += "![" + att.name + "](" + (att.dataUri ?? att.path) + ")\n\n";
            }
        }
        return prefix + text;
    }

    function _sendWithAttachments(text) {
        root.session?.sendUserMessage(_buildMessageWithAttachments(text));
        root.pendingAttachments = [];
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: root.inputPadding

        // ── Session context strip ─────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 4
            spacing: 6

            Rectangle {
                width: 8; height: 8; radius: 4
                color: root.meta.color
                Layout.alignment: Qt.AlignVCenter
            }

            StyledText {
                text: root.meta.name
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Medium
                color: root.meta.color
                Layout.alignment: Qt.AlignVCenter
            }

            StyledText {
                text: "·"
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
                Layout.alignment: Qt.AlignVCenter
            }

            StyledText {
                text: root.session?.modelId ?? ""
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
                Layout.alignment: Qt.AlignVCenter
            }

            Item { Layout.fillWidth: true }

            RippleButton {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 28
                implicitHeight: 28
                buttonRadius: Appearance.rounding.small
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer1Hover
                colRipple: Appearance.colors.colLayer1Active
                releaseAction: () => { root.session?.clearMessages() }

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "clear_all"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colSubtext
                }

                StyledToolTip { text: qsTr("Clear conversation") }
            }
        }

        // ── Message list ──────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ScrollEdgeFade {
                z: 1
                target: messageListView
                vertical: true
            }

            StyledListView {
                id: messageListView
                anchors.fill: parent
                spacing: 14
                popin: false
                add: null  // Prevent janky animations on function calls

                onContentHeightChanged: {
                    if (atYEnd)
                        Qt.callLater(positionViewAtEnd);
                }
                onCountChanged: {
                    if (atYEnd)
                        Qt.callLater(positionViewAtEnd);
                }

                model: ScriptModel {
                    values: (root.session?.messageIDs ?? []).filter(id => {
                        const msg = root.session?.messageByID[id];
                        return msg?.visibleToUser ?? true;
                    })
                }

                delegate: AgentMessage {
                    required property var modelData
                    messageData: root.session?.messageByID[modelData] ?? null
                    modelId: root.session?.modelId ?? "claude-cli"
                    width: ListView.view.width
                }
            }
        }

        // ── Thinking indicator ────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: thinkingRow.implicitHeight + 8
            visible: root.session?.isWorking ?? false

            RowLayout {
                id: thinkingRow
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    leftMargin: 10
                }
                spacing: 8

                MaterialLoadingIndicator {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 16
                    implicitHeight: 16
                    loading: root.session?.isWorking ?? false
                }

                StyledText {
                    text: qsTr("Working…")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smallest
                }
            }
        }

        // ── Slash command menu (above input) ──────────────────────────────
        AgentCommandMenu {
            id: commandMenu
            Layout.fillWidth: true
            visible: false
            session: root.session
            pendingAttachments: root.pendingAttachments

            onAttachmentQueued: att => {
                root._queueAttachment(att);
            }
            onCommandApplied: (cmdId, args) => {
                // Custom command — load file content and prepend as context
                // (handled by commandMenu internally for now)
            }

            Behavior on implicitHeight {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }
        }

        // ── Input area ────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            radius: Appearance.rounding.normal - root.inputPadding
            color: Appearance.colors.colLayer2
            implicitHeight: Math.max(inputAreaCol.implicitHeight + 8, 45)
            clip: true

            Behavior on implicitHeight {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }

            ColumnLayout {
                id: inputAreaCol
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    leftMargin: 2
                    rightMargin: 2
                    topMargin: 4
                }
                spacing: 0

                // ── Attachment chips ──────────────────────────────────────
                Flow {
                    Layout.fillWidth: true
                    Layout.leftMargin: 8
                    Layout.rightMargin: 8
                    Layout.topMargin: 4
                    spacing: 6
                    visible: root.pendingAttachments.length > 0

                    Repeater {
                        model: ScriptModel { values: root.pendingAttachments }
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            color: Appearance.colors.colLayer1
                            radius: Appearance.rounding.full
                            implicitHeight: chipRow.implicitHeight + 6

                            RowLayout {
                                id: chipRow
                                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 6; rightMargin: 4 }
                                spacing: 4

                                MaterialSymbol {
                                    text: modelData.type === "image" ? "image" : "attach_file"
                                    iconSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colSubtext
                                }

                                StyledText {
                                    text: modelData.name
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colSubtext
                                    elide: Text.ElideMiddle
                                    Layout.maximumWidth: 120
                                }

                                RippleButton {
                                    implicitWidth: 16
                                    implicitHeight: 16
                                    buttonRadius: 8
                                    colBackground: "transparent"
                                    colBackgroundHover: Appearance.colors.colLayer1Hover
                                    colRipple: Appearance.colors.colLayer1Active
                                    releaseAction: () => {
                                        const arr = [...root.pendingAttachments];
                                        arr.splice(index, 1);
                                        root.pendingAttachments = arr;
                                    }

                                    contentItem: MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "close"
                                        iconSize: Appearance.font.pixelSize.smallest
                                        color: Appearance.colors.colSubtext
                                    }
                                }
                            }

                            implicitWidth: chipRow.implicitWidth + 10
                        }
                    }
                }

                // ── Input row ─────────────────────────────────────────────
                RowLayout {
                    id: inputRowLayout
                    Layout.fillWidth: true
                    spacing: 0

                    // Plus button — quick file/image attach
                    RippleButton {
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: 36
                        implicitHeight: 36
                        buttonRadius: Appearance.rounding.small
                        colBackground: "transparent"
                        colBackgroundHover: Appearance.colors.colLayer1Hover
                        colRipple: Appearance.colors.colLayer1Active
                        enabled: !(root.session?.isWorking ?? false)
                        releaseAction: () => {
                            // Insert /file into input to trigger slash menu
                            inputField.text = "/file ";
                            inputField.forceActiveFocus();
                            commandMenu.filterText = "file";
                            commandMenu.visible = true;
                        }

                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "add"
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colSubtext
                        }

                        StyledToolTip { text: qsTr("Attach file or image") }
                    }

                    ScrollView {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(root.height * 0.4, inputField.height)
                        clip: true
                        ScrollBar.vertical.policy: ScrollBar.AsNeeded

                        StyledTextArea {
                            id: inputField
                            anchors.fill: parent
                            wrapMode: TextArea.Wrap
                            padding: 10
                            color: activeFocus
                                ? Appearance.m3colors.m3onSurface
                                : Appearance.m3colors.m3onSurfaceVariant
                            placeholderText: root.session?.isWorking
                                ? qsTr("Working…")
                                : qsTr("Message…")
                            enabled: !(root.session?.isWorking ?? false)
                            background: null

                            onTextChanged: {
                                if (text.startsWith("/")) {
                                    const afterSlash = text.substring(1);
                                    commandMenu.filterText = afterSlash.split(" ")[0];
                                    commandMenu.visible = true;
                                } else {
                                    commandMenu.visible = false;
                                }
                            }

                            Keys.onPressed: event => {
                                // Slash menu navigation
                                if (commandMenu.visible) {
                                    if (event.key === Qt.Key_Up) {
                                        commandMenu.moveUp();
                                        event.accepted = true;
                                        return;
                                    }
                                    if (event.key === Qt.Key_Down) {
                                        commandMenu.moveDown();
                                        event.accepted = true;
                                        return;
                                    }
                                    if (event.key === Qt.Key_Return && !event.modifiers) {
                                        commandMenu.applySelected(inputField);
                                        event.accepted = true;
                                        return;
                                    }
                                    if (event.key === Qt.Key_Escape) {
                                        commandMenu.visible = false;
                                        event.accepted = true;
                                        return;
                                    }
                                }

                                // Shift+Tab → cycle mode
                                if (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier)) {
                                    root.cycleMode();
                                    event.accepted = true;
                                    return;
                                }

                                // Enter to send
                                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    if (event.modifiers & Qt.ShiftModifier) {
                                        inputField.insert(inputField.cursorPosition, "\n");
                                        event.accepted = true;
                                    } else {
                                        const txt = inputField.text.trim();
                                        inputField.clear();
                                        commandMenu.visible = false;
                                        if (txt.length > 0)
                                            root._sendWithAttachments(txt);
                                        event.accepted = true;
                                    }
                                }
                            }
                        }
                    }

                    // Send button
                    RippleButton {
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: 36
                        implicitHeight: 36
                        buttonRadius: Appearance.rounding.small
                        colBackground: "transparent"
                        colBackgroundHover: Appearance.colors.colLayer1Hover
                        colRipple: Appearance.colors.colLayer1Active
                        enabled: !(root.session?.isWorking ?? false)
                        releaseAction: () => {
                            const txt = inputField.text.trim();
                            inputField.clear();
                            commandMenu.visible = false;
                            if (txt.length > 0)
                                root._sendWithAttachments(txt);
                        }

                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "send"
                            iconSize: Appearance.font.pixelSize.normal
                            color: inputField.text.length > 0 && !(root.session?.isWorking ?? false)
                                ? Appearance.colors.colOnLayer1
                                : Appearance.colors.colSubtext

                            Behavior on color {
                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                            }
                        }
                    }
                }

                // ── Input footer: keyboard hints + mode badge ─────────────
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 8
                    Layout.rightMargin: 8
                    Layout.bottomMargin: 4
                    spacing: 12

                    StyledText {
                        text: "↵ Send"
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }

                    StyledText {
                        text: "⇧↵ Newline"
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }

                    StyledText {
                        text: "/ Commands"
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }

                    Item { Layout.fillWidth: true }

                    // Mode badge — click or Shift+Tab to cycle
                    Rectangle {
                        visible: root.hasModeControl
                        radius: Appearance.rounding.full
                        color: Qt.rgba(root.modeColor.r, root.modeColor.g, root.modeColor.b, 0.15)
                        implicitWidth: modeBadgeLabel.implicitWidth + 12
                        implicitHeight: modeBadgeLabel.implicitHeight + 6
                        Layout.alignment: Qt.AlignVCenter

                        StyledText {
                            id: modeBadgeLabel
                            anchors.centerIn: parent
                            text: root.currentMode
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: root.modeColor

                            Behavior on color {
                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.cycleMode()
                        }

                        StyledToolTip { text: qsTr("Click or ⇧⇥ to cycle mode") }
                    }
                }
            }
        }
    }
}
