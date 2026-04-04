import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions as CF
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

/**
 * Slash command popup for the Agents input field.
 * Appears above the input when the user types "/".
 * Supports built-in meta-commands and custom commands from .claude/commands/*.md
 */
Rectangle {
    id: root

    required property var session       // AgentSession instance
    property string filterText: ""      // text after the "/" character
    property int selectedIndex: 0
    property var pendingAttachments: [] // list of {type: "file"|"image", path, name}

    signal commandApplied(string commandId, string args)
    signal attachmentQueued(var attachment)

    color: Appearance.colors.colLayer1
    radius: Appearance.rounding.normal
    clip: true

    implicitWidth: 320
    implicitHeight: Math.min(filteredCommands.length * 44 + 8, 240)

    StyledRectangularShadow { target: root }

    // ── Built-in commands ─────────────────────────────────────────────────
    readonly property var builtinCommands: [
        { id: "clear",  icon: "delete_sweep",   args: "",                    desc: "Clear conversation & restart session" },
        { id: "model",  icon: "model_training",  args: "haiku|sonnet|opus",   desc: "Switch model for next session" },
        { id: "mode",   icon: "security",        args: "plan|edit|auto|…",    desc: "Change permission / approval mode" },
        { id: "effort", icon: "psychology",      args: "low|medium|high|max", desc: "Set thinking effort (Claude only)" },
        { id: "cwd",    icon: "folder_open",     args: "path",                desc: "Change working directory" },
        { id: "file",   icon: "attach_file",     args: "path",                desc: "Attach file as context" },
        { id: "image",  icon: "image",           args: "path",                desc: "Attach image (Claude only)" },
    ]

    // ── Custom commands loaded from .claude/commands/*.md ─────────────────
    property var customCommands: []

    Process {
        id: commandScanner
        command: ["bash", "-c", "ls \"" + (root.session?.cwd ?? "") + "/.claude/commands/\" 2>/dev/null"]
        running: false

        stdout: SplitParser {
            onRead: line => {
                if (!line.endsWith(".md")) return;
                const id = line.replace(/\.md$/, "").trim();
                if (!id) return;
                root.customCommands = [...root.customCommands, {
                    id: id, icon: "smart_toy", args: "", desc: "Custom command", isCustom: true,
                    filePath: (root.session?.cwd ?? "") + "/.claude/commands/" + line.trim()
                }];
            }
        }
    }

    function reloadCustomCommands() {
        root.customCommands = [];
        commandScanner.running = false;
        commandScanner.running = true;
    }

    Component.onCompleted: reloadCustomCommands()
    onVisibleChanged: if (visible) reloadCustomCommands()

    readonly property var allCommands: builtinCommands.concat(root.customCommands)

    // ── Filtering ─────────────────────────────────────────────────────────
    readonly property var filteredCommands: {
        const q = root.filterText.toLowerCase().split(" ")[0];
        if (!q) return root.allCommands;
        return root.allCommands.filter(c => c.id.startsWith(q));
    }

    onFilterTextChanged: {
        root.selectedIndex = 0;
    }

    // ── Navigation API (called by parent input field) ─────────────────────
    function moveUp() {
        if (filteredCommands.length === 0) return;
        root.selectedIndex = (root.selectedIndex - 1 + filteredCommands.length) % filteredCommands.length;
        commandList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
    }

    function moveDown() {
        if (filteredCommands.length === 0) return;
        root.selectedIndex = (root.selectedIndex + 1) % filteredCommands.length;
        commandList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
    }

    function applySelected(inputField) {
        if (filteredCommands.length === 0) return;
        _apply(filteredCommands[root.selectedIndex], inputField);
    }

    function _apply(cmd, inputField) {
        // Extract args from input: everything after "/commandId "
        const full = inputField?.text ?? "";
        const spaceIdx = full.indexOf(" ");
        const args = spaceIdx >= 0 ? full.substring(spaceIdx + 1).trim() : "";

        if (root.session) {
            switch (cmd.id) {
            case "clear":
                root.session.clearMessages();
                break;
            case "model":
                if (args.length > 0) root.session.modelOverride = args;
                break;
            case "mode":
                if (args.length > 0) {
                    if (root.session.modelId === "claude-cli") root.session.permissionMode = args;
                    else root.session.approvalMode = args;
                }
                break;
            case "effort":
                if (args.length > 0) root.session.effortLevel = args;
                break;
            case "cwd":
                if (args.length > 0) root.session.cwd = CF.FileUtils.trimFileProtocol(args);
                break;
            case "file":
                if (args.length > 0) {
                    const name = args.split("/").pop();
                    root.attachmentQueued({ type: "file", path: args, name: name });
                }
                break;
            case "image":
                if (root.session.modelId !== "claude-cli") {
                    // Image attachment only supported for Claude
                    break;
                }
                if (args.length > 0) {
                    const name = args.split("/").pop();
                    root.attachmentQueued({ type: "image", path: args, name: name });
                }
                break;
            default:
                // Custom command — signal parent to load file content
                root.commandApplied(cmd.id, args);
                break;
            }
        }

        if (inputField) inputField.clear();
        root.visible = false;
    }

    // ── List view ─────────────────────────────────────────────────────────
    ListView {
        id: commandList
        anchors { fill: parent; margins: 4 }
        model: ScriptModel { values: root.filteredCommands }
        spacing: 0
        clip: true

        delegate: Rectangle {
            required property var modelData
            required property int index
            width: ListView.view.width
            height: 44
            radius: Appearance.rounding.small
            color: index === root.selectedIndex
                ? Appearance.colors.colLayer2
                : "transparent"

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.selectedIndex = index
                onClicked: root._apply(modelData, null)
            }

            RowLayout {
                anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                spacing: 8

                MaterialSymbol {
                    text: modelData.icon
                    iconSize: Appearance.font.pixelSize.normal
                    color: index === root.selectedIndex
                        ? root.meta?.color ?? Appearance.colors.colSubtext
                        : Appearance.colors.colSubtext
                    Layout.alignment: Qt.AlignVCenter

                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }

                StyledText {
                    text: "/" + modelData.id
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Medium
                    color: index === root.selectedIndex
                        ? Appearance.colors.colOnLayer1
                        : Appearance.colors.colSubtext
                    Layout.alignment: Qt.AlignVCenter

                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }

                StyledText {
                    text: modelData.args
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                    opacity: 0.6
                    visible: modelData.args.length > 0
                    Layout.alignment: Qt.AlignVCenter
                }

                Item { Layout.fillWidth: true }

                StyledText {
                    text: modelData.desc
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                    Layout.maximumWidth: 130
                    Layout.alignment: Qt.AlignVCenter
                }
            }
        }
    }

    // Provider color for icon highlight
    readonly property var meta: {
        const m = {
            "claude-cli":  { color: Appearance.colors.colTertiary },
            "codex":       { color: Appearance.colors.colPrimary },
            "gemini-cli":  { color: Appearance.colors.colSecondary },
            "kimi-cli":    { color: Appearance.colors.colSuccess },
        };
        return m[root.session?.modelId ?? "claude-cli"] ?? m["claude-cli"];
    }
}
