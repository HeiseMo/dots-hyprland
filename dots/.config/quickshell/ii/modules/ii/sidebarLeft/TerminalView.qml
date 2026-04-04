import qs.modules.common
import qs.modules.common.functions as CF
import qs.modules.common.widgets
import qs.services
import "../../../services/ai/AnsiParser.js" as AnsiParser
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

/**
 * TerminalView — live tmux pane viewer embedded in the sidebar.
 *
 * Polls `tmux capture-pane` while active, converts ANSI SGR sequences to
 * Qt RichText HTML via AnsiParser, and renders in a scrollable monospace area.
 * A text input at the bottom forwards keystrokes to the tmux session via
 * `tmux send-keys`.  The "Jump to terminal" button attaches a real kitty
 * window to the same session for TUI/interactive use.
 */
Item {
    id: root

    // Name of the tmux session to display (e.g. "ii-agent-claude-abc123")
    property string sessionName: ""
    // Set to false when the sidebar is hidden to pause polling
    property bool active: true

    // Interval between capture-pane polls (ms)
    property int pollInterval: 200

    // ── Poll state ─────────────────────────────────────────────────────────
    property string _lastContent: ""
    property bool   _atBottom: true

    function _shellQuote(value) {
        return `'${CF.StringUtils.shellSingleQuoteEscape(String(value ?? ""))}'`;
    }

    // ── Polling timer ──────────────────────────────────────────────────────
    Timer {
        id: pollTimer
        interval: root.pollInterval
        repeat: true
        running: root.active && root.sessionName.length > 0
        onTriggered: {
            if (!captureProc.running)
                captureProc.running = true;
        }
    }

    // ── Capture process ────────────────────────────────────────────────────
    Process {
        id: captureProc
        property string _buf: ""
        // -e: include ANSI escape codes
        // -p: print to stdout
        // -J: join visually-continued lines (wrapping)
        command: [
            "bash",
            "-lc",
            "TMUX_BIN=\"$(command -v tmux 2>/dev/null || true)\"; " +
            "if [ -z \"$TMUX_BIN\" ]; then exit 127; fi; " +
            `exec \"$TMUX_BIN\" capture-pane -t ${root._shellQuote(root.sessionName)} -e -p -J`
        ]
        stdout: SplitParser {
            splitMarker: ""   // collect everything (no per-line splitting)
            onRead: data => { captureProc._buf += data; }
        }
        onExited: (code) => {
            const raw = captureProc._buf;
            captureProc._buf = "";
            if (code === 127) {
                termText.text = '<font color="#ffb4ab">tmux is not installed or unavailable.</font>';
                return;
            }
            if (raw === root._lastContent) return;   // nothing changed
            root._lastContent = raw;
            const html = AnsiParser.toHtml(raw);
            termText.text = html;
            if (root._atBottom)
                Qt.callLater(scrollView.scrollToBottom);
        }
        running: false
    }

    // ── Send-keys process ──────────────────────────────────────────────────
    Process {
        id: sendKeysProc
        running: false
    }

    function sendText(text) {
        if (!root.sessionName || text.length === 0) return;
        sendKeysProc.command = [
            "bash",
            "-lc",
            "TMUX_BIN=\"$(command -v tmux 2>/dev/null || true)\"; " +
            "if [ -z \"$TMUX_BIN\" ]; then exit 127; fi; " +
            `exec \"$TMUX_BIN\" send-keys -t ${root._shellQuote(root.sessionName)} -- ${root._shellQuote(text)} Enter`
        ];
        sendKeysProc.running = true;
    }

    function sendKey(key) {
        if (!root.sessionName) return;
        sendKeysProc.command = [
            "bash",
            "-lc",
            "TMUX_BIN=\"$(command -v tmux 2>/dev/null || true)\"; " +
            "if [ -z \"$TMUX_BIN\" ]; then exit 127; fi; " +
            `exec \"$TMUX_BIN\" send-keys -t ${root._shellQuote(root.sessionName)} ${root._shellQuote(key)}`
        ];
        sendKeysProc.running = true;
    }

    // ── Layout ─────────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ── Terminal output area ───────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "#0d0d0d"
            radius: Appearance.rounding.small
            clip: true

            ScrollView {
                id: scrollView
                anchors.fill: parent
                anchors.margins: 6
                ScrollBar.vertical.policy: ScrollBar.AsNeeded
                ScrollBar.horizontal.policy: ScrollBar.AsNeeded

                function scrollToBottom() {
                    ScrollBar.vertical.position = 1.0 - ScrollBar.vertical.size;
                }

                // Track whether the user has manually scrolled away from bottom
                ScrollBar.vertical.onPositionChanged: {
                    const atEnd = ScrollBar.vertical.position + ScrollBar.vertical.size >= 0.99;
                    root._atBottom = atEnd;
                }

                Text {
                    id: termText
                    textFormat: Text.RichText
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: "#cccccc"
                    wrapMode: Text.NoWrap
                    lineHeight: 1.2
                    // Default text while waiting for first capture
                    text: root.sessionName.length > 0
                        ? ""
                        : '<font color="#555555">Waiting for session…</font>'
                }
            }

            // Fade at bottom edge to hint more content
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: 20
                radius: Appearance.rounding.small
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 1.0; color: "#0d0d0d" }
                }
                visible: !root._atBottom
            }
        }

        // ── Input row ──────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 4
            implicitHeight: inputRow.implicitHeight + 10
            color: Appearance.colors.colLayer2
            radius: Appearance.rounding.small

            RowLayout {
                id: inputRow
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    leftMargin: 8
                    rightMargin: 4
                }
                spacing: 4

                TextField {
                    id: inputField
                    Layout.fillWidth: true
                    placeholderText: root.sessionName.length > 0
                        ? (AgentWorkspace.tmuxReady ? qsTr("Send keys…") : qsTr("tmux unavailable"))
                        : qsTr("No session")
                    enabled: root.sessionName.length > 0 && AgentWorkspace.tmuxReady
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colOnLayer1
                    background: null
                    leftPadding: 0

                    Keys.onReturnPressed: {
                        root.sendText(text);
                        clear();
                    }
                    // Forward special keys directly
                    Keys.onUpPressed:    { root.sendKey("Up");   event.accepted = true; }
                    Keys.onDownPressed:  { root.sendKey("Down"); event.accepted = true; }
                    Keys.onTabPressed:   { root.sendKey("Tab");  event.accepted = true; }
                    Keys.onEscapePressed: { root.sendKey("Escape"); event.accepted = true; }
                }

                // Send button
                RippleButton {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 28
                    implicitHeight: 28
                    buttonRadius: Appearance.rounding.small
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer1Hover
                    colRipple: Appearance.colors.colLayer1Active
                    enabled: root.sessionName.length > 0 && AgentWorkspace.tmuxReady
                    releaseAction: () => {
                        root.sendText(inputField.text);
                        inputField.clear();
                    }
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "send"
                        iconSize: Appearance.font.pixelSize.normal
                        color: inputField.text.length > 0
                            ? Appearance.colors.colOnLayer1
                            : Appearance.colors.colSubtext
                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }
                    }
                }

                // Jump to real terminal
                RippleButton {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 28
                    implicitHeight: 28
                    buttonRadius: Appearance.rounding.small
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer1Hover
                    colRipple: Appearance.colors.colLayer1Active
                    enabled: root.sessionName.length > 0 && AgentWorkspace.tmuxReady
                    releaseAction: () => {
                        Quickshell.execDetached([
                            "bash", "-lc",
                            "TMUX_BIN=\"$(command -v tmux 2>/dev/null || true)\"; " +
                            "KITTY_BIN=\"$(command -v kitty 2>/dev/null || true)\"; " +
                            "if [ -z \"$TMUX_BIN\" ] || [ -z \"$KITTY_BIN\" ]; then exit 127; fi; " +
                            `exec \"$KITTY_BIN\" -e \"$TMUX_BIN\" attach-session -t ${root._shellQuote(root.sessionName)}`
                        ]);
                    }
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "open_in_new"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colSubtext
                    }
                    StyledToolTip { text: qsTr("Open in terminal (attach tmux session)") }
                }
            }
        }
    }
}
