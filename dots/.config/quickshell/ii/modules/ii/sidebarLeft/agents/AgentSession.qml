import qs.modules.common
import qs.modules.common.functions as CF
import qs.services.ai
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Self-contained agent session: process lifecycle + message storage.
 *
 * Claude and Codex use a **persistent process** model:
 *   - Process starts at session creation (CLI loads context, CLAUDE.md, etc.)
 *   - Each user message is written to stdin as NDJSON
 *   - Process stays alive between turns
 *   - clearMessages() kills and restarts the process
 *
 * Gemini and Kimi use a **one-shot** model (launched per message with full transcript)
 * until their persistent stdin mode is confirmed.
 */
Item {
    id: root

    // Session identity
    property string sessionId: Date.now().toString(36) + Math.random().toString(36).substr(2, 8)
    property string modelId: "claude-cli" // "claude-cli" | "codex" | "gemini-cli" | "kimi-cli"
    property string title: ""
    property string cwd: CF.FileUtils.trimFileProtocol(Directories.home)

    // Mode controls (baked into CLI startup args — changing them restarts the process)
    property string permissionMode: "plan"    // claude-cli: plan | default | acceptEdits | auto | dontAsk | bypassPermissions
    property string approvalMode:   "suggest" // codex: suggest | auto-edit | full-auto
    property string modelOverride:  ""        // empty = use default per-provider model
    property string effortLevel:    ""        // claude-cli: low | medium | high | max

    // Message storage (same shape as Ai.qml)
    property var messageIDs: []
    property var messageByID: ({})

    // Status
    property bool isWaitingForUser: true
    readonly property bool isWorking: !isWaitingForUser
    readonly property bool isPersistent: root.modelId === "claude-cli" || root.modelId === "codex"

    signal responseFinished()

    // ── Strategy instances (one per provider) ─────────────────────────────
    ClaudeCliStrategy { id: claudeStrategy }
    CodexCliStrategy  { id: codexStrategy }
    GeminiCliStrategy { id: geminiStrategy }
    KimiCliStrategy   { id: kimiStrategy }

    readonly property var activeStrategy: {
        switch (root.modelId) {
        case "claude-cli":  return claudeStrategy;
        case "gemini-cli":  return geminiStrategy;
        case "kimi-cli":    return kimiStrategy;
        default:            return codexStrategy;
        }
    }

    readonly property string apiFormat: {
        const m = {"claude-cli": "claude_cli", "codex": "codex_cli", "gemini-cli": "gemini_cli", "kimi-cli": "kimi_cli"};
        return m[root.modelId] ?? "codex_cli";
    }

    readonly property string resolvedModel: {
        if (root.modelOverride && root.modelOverride.length > 0) return root.modelOverride;
        const defaults = {
            "claude-cli": "sonnet",
            "codex":      "codex",
            "gemini-cli": "gemini-2.5-pro",
            "kimi-cli":   "kimi-k2",
        };
        return defaults[root.modelId] ?? "sonnet";
    }

    // ── Message factory ───────────────────────────────────────────────────
    Component { id: msgTemplate; AiMessageData {} }

    function idForMessage() {
        return Date.now().toString(36) + Math.random().toString(36).substr(2, 8);
    }

    // ── Process management ─────────────────────────────────────────────────
    property bool _pendingRestart: false
    property string _pendingStdinMessage: ""

    function _buildPersistentCommand() {
        const fmt = root.apiFormat;
        if (fmt === "claude_cli") {
            return [
                "bash", "-lc",
                "CLAUDE_BIN=\"$(command -v claude 2>/dev/null || true)\"; " +
                "if [ -z \"$CLAUDE_BIN\" ]; then " +
                    "printf '{\"type\":\"result\",\"result\":\"**Error**: Claude Code not installed. Run `npm i -g @anthropic-ai/claude-code`.\",\"done\":true}\\n'; exit 0; fi; " +
                "exec \"$CLAUDE_BIN\" " +
                    "--input-format stream-json " +
                    "--output-format stream-json " +
                    "--verbose " +
                    "--include-partial-messages " +
                    "--model \"" + root.resolvedModel + "\" " +
                    "--permission-mode \"" + root.permissionMode + "\"" +
                    (root.effortLevel.length > 0 ? " --effort \"" + root.effortLevel + "\"" : "")
            ];
        } else if (fmt === "codex_cli") {
            return [
                "bash", "-lc",
                "CODEX_BIN=\"$(command -v codex 2>/dev/null || true)\"; " +
                "if [ -z \"$CODEX_BIN\" ]; then printf '{\"type\":\"turn.completed\",\"text\":\"**Error**: codex not found.\"}\\n'; exit 1; fi; " +
                "exec \"$CODEX_BIN\" --json --approval-mode \"" + root.approvalMode + "\""
            ];
        }
        return [];
    }

    function _startPersistentProcess() {
        if (!root.isPersistent) return;
        const cmd = _buildPersistentCommand();
        if (cmd.length === 0) return;
        cliProcess.command = cmd;
        cliProcess.workingDirectory = CF.FileUtils.trimFileProtocol(root.cwd);
        cliProcess.stdinEnabled = true;  // keep stdin open for the lifetime of the process
        cliProcess.running = true;
    }

    // ── Public API ─────────────────────────────────────────────────────────
    function clearMessages() {
        root.messageIDs = [];
        root.messageByID = {};
        root.isWaitingForUser = true;
        root._pendingStdinMessage = "";
        if (root.isPersistent) {
            if (cliProcess.running) {
                root._pendingRestart = true;
                cliProcess.running = false;
            } else {
                _startPersistentProcess();
            }
        }
    }

    function sendUserMessage(text) {
        if (!text || text.trim().length === 0) return;
        if (!root.isWaitingForUser) return;

        const userMsg = msgTemplate.createObject(root, {
            role: "user",
            content: text,
            rawContent: text,
            thinking: false,
            done: true,
        });
        const uid = idForMessage();
        root.messageIDs = [...root.messageIDs, uid];
        root.messageByID[uid] = userMsg;

        const assistantMsg = msgTemplate.createObject(root, {
            role: "assistant",
            model: root.modelId,
            content: "",
            rawContent: "",
            thinking: true,
            done: false,
        });
        const aid = idForMessage();
        root.messageIDs = [...root.messageIDs, aid];
        root.messageByID[aid] = assistantMsg;

        cliProcess.currentMessage = assistantMsg;
        root.isWaitingForUser = false;
        root.activeStrategy.reset();

        if (root.isPersistent) {
            const stdinMsg = root.activeStrategy.buildStdinMessage(text) + "\n";
            if (cliProcess.running) {
                cliProcess.write(stdinMsg);
            } else {
                // Process died between turns — restart and queue message
                root._pendingStdinMessage = stdinMsg;
                _startPersistentProcess();
            }
        } else {
            _launchOneshotProcess(text);
        }
    }

    function _launchOneshotProcess(userText) {
        const fmt = root.apiFormat;
        const wd = CF.FileUtils.trimFileProtocol(root.cwd);
        const msgArray = root.messageIDs
            .map(id => root.messageByID[id])
            .filter(m => m && m.role !== "interface");
        const modelCfg = {
            api_format: fmt,
            model: root.resolvedModel,
            requires_key: false,
            extraParams: { cwd: wd, binary_path: "", permission_mode: "", approval_mode: "" }
        };
        const data = root.activeStrategy.buildRequestData(modelCfg, msgArray, "", 0.5, [], "");

        if (fmt === "gemini_cli") {
            cliProcess.environment["II_GEMINI_PROMPT"] = data.prompt;
            cliProcess.environment["II_GEMINI_MODEL"] = data.model || root.resolvedModel;
            cliProcess.environment["II_GEMINI_BIN"] = data.binaryPath || "gemini";
            cliProcess.command = [
                "bash", "-lc",
                "GEMINI_BIN=\"$II_GEMINI_BIN\"; " +
                "if [ ! -x \"$GEMINI_BIN\" ]; then GEMINI_BIN=\"$(command -v gemini 2>/dev/null || true)\"; fi; " +
                "if [ -z \"$GEMINI_BIN\" ]; then " +
                    "printf '{\"type\":\"result\",\"text\":\"**Error**: Gemini CLI not installed. Run `npm i -g @google/gemini-cli`.\",\"done\":true}\\n'; exit 0; fi; " +
                "exec \"$GEMINI_BIN\" -p \"$II_GEMINI_PROMPT\" --output-format stream-json -m \"$II_GEMINI_MODEL\"",
            ];
        } else if (fmt === "kimi_cli") {
            cliProcess.environment["II_KIMI_PROMPT"] = data.prompt;
            cliProcess.environment["II_KIMI_MODEL"] = data.model || root.resolvedModel;
            cliProcess.environment["II_KIMI_BIN"] = data.binaryPath || "kimi";
            cliProcess.command = [
                "bash", "-lc",
                "KIMI_BIN=\"$II_KIMI_BIN\"; " +
                "if [ ! -x \"$KIMI_BIN\" ]; then KIMI_BIN=\"$(command -v kimi 2>/dev/null || true)\"; fi; " +
                "if [ -z \"$KIMI_BIN\" ]; then " +
                    "printf '{\"type\":\"result\",\"text\":\"**Error**: Kimi CLI not installed.\",\"done\":true}\\n'; exit 0; fi; " +
                "exec \"$KIMI_BIN\" --print --output-format stream-json --final-message-only -m \"$II_KIMI_MODEL\" -w \"$PWD\" -p \"$II_KIMI_PROMPT\"",
            ];
        }
        cliProcess.workingDirectory = wd;
        cliProcess.running = true;
    }

    // ── Process ────────────────────────────────────────────────────────────
    Process {
        id: cliProcess
        property var currentMessage: null

        stdout: SplitParser {
            onRead: data => {
                if (!data || data.length === 0) return;
                if (cliProcess.currentMessage?.thinking)
                    cliProcess.currentMessage.thinking = false;
                try {
                    const result = root.activeStrategy.parseResponseLine(data, cliProcess.currentMessage);
                    if (result?.finished && root.isPersistent) {
                        // Persistent: turn complete signal from stdout — don't kill process
                        _markTurnDone();
                    }
                } catch (e) {
                    if (cliProcess.currentMessage) {
                        cliProcess.currentMessage.rawContent += data;
                        cliProcess.currentMessage.content += data;
                    }
                }
            }
        }

        onRunningChanged: {
            if (running && root._pendingStdinMessage.length > 0) {
                const msg = root._pendingStdinMessage;
                root._pendingStdinMessage = "";
                Qt.callLater(() => cliProcess.write(msg));
            }
        }

        onExited: (exitCode, exitStatus) => {
            // One-shot processes: mark done on exit
            if (!root.isPersistent) {
                if (cliProcess.currentMessage && !cliProcess.currentMessage.done) {
                    root.activeStrategy.onRequestFinished(cliProcess.currentMessage);
                    _markTurnDone();
                }
                return;
            }
            // Persistent: unexpected exit
            if (cliProcess.currentMessage && !cliProcess.currentMessage.done)
                _markTurnDone();
            if (root._pendingRestart) {
                root._pendingRestart = false;
                _startPersistentProcess();
            }
        }
    }

    function _markTurnDone() {
        if (cliProcess.currentMessage)
            cliProcess.currentMessage.done = true;
        root.isWaitingForUser = true;
        root.responseFinished();
    }

    Component.onCompleted: {
        if (root.isPersistent)
            _startPersistentProcess();
    }

    // Restart process when mode changes (mode is baked into startup args)
    onPermissionModeChanged: {
        if (root.apiFormat === "claude_cli" && cliProcess.running)
            clearMessages();
    }
    onApprovalModeChanged: {
        if (root.apiFormat === "codex_cli" && cliProcess.running)
            clearMessages();
    }
}
