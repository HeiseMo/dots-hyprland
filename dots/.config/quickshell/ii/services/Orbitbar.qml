pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool enabled: true
    property bool daemonEnabled: true
    property string statePath: Directories.orbitbarStatePath
    property string socketPath: Directories.orbitbarSocketPath
    property string bridgeScriptPath: `${Directories.scriptPath}/orbitbar/orbitbar_bridge.py`
    property var state: ({ "updated_at": "", "session_count": 0, "sessions": [] })
    property var sessions: []
    property int sessionCount: 0
    property string lastUpdatedAt: ""
    property string stateFingerprint: ""
    property bool daemonRunning: bridgeProcess.running
    readonly property var focusedSession: root.sessions.length > 0 ? root.sessions[0] : null
    readonly property var needsInputSessions: root.sessions.filter(session => (session?.ui_state ?? "idle") === "needs_input")
    readonly property var workingSessions: root.sessions.filter(session => (session?.ui_state ?? "idle") === "working")
    readonly property var errorSessions: root.sessions.filter(session => (session?.ui_state ?? "idle") === "error")
    readonly property var doneSessions: root.sessions.filter(session => (session?.ui_state ?? "idle") === "done")
    readonly property var idleSessions: root.sessions.filter(session => (session?.ui_state ?? "idle") === "idle")
    readonly property int pendingCount: root.needsInputSessions.length
    readonly property int workingCount: root.workingSessions.length
    readonly property int errorCount: root.errorSessions.length
    readonly property int doneCount: root.doneSessions.length
    readonly property var headlineSession: root.needsInputSessions[0] ?? root.errorSessions[0] ?? root.workingSessions[0] ?? root.sessions[0] ?? null

    function load() {
        if (daemonEnabled && !bridgeProcess.running)
            bridgeProcess.running = true;
        stateFile.reload();
        statePollTimer.restart();
    }

    function resetState() {
        root.state = { "updated_at": "", "session_count": 0, "sessions": [] };
        root.sessions = [];
        root.sessionCount = 0;
        root.lastUpdatedAt = "";
        root.stateFingerprint = "";
    }

    function parseState(raw) {
        if (!raw || raw.trim().length === 0) {
            if (root.sessionCount > 0) {
                console.warn("[Orbitbar] Ignoring empty state payload to preserve live sessions");
                return;
            }
            resetState();
            return;
        }

        try {
            const parsed = JSON.parse(raw);
            const nextSessions = parsed.sessions ?? [];
            const nextSessionCount = parsed.session_count ?? nextSessions.length;
            const fingerprint = JSON.stringify({
                "session_count": nextSessionCount,
                "sessions": nextSessions,
            });

            root.lastUpdatedAt = parsed.updated_at ?? "";
            if (fingerprint === root.stateFingerprint)
                return;

            root.stateFingerprint = fingerprint;
            root.state = parsed;
            root.sessions = nextSessions;
            root.sessionCount = nextSessionCount;
        } catch (error) {
            console.warn(`[Orbitbar] Failed to parse state file: ${error}`);
        }
    }

    Process {
        id: bridgeProcess
        command: [
            "python",
            root.bridgeScriptPath,
            "--socket-path",
            root.socketPath,
            "--state-path",
            root.statePath,
        ]
        running: false
        onExited: (exitCode, exitStatus) => {
            console.log(`[Orbitbar] Bridge exited with code ${exitCode}`)
            if (root.daemonEnabled)
                restartTimer.restart()
        }
    }

    Timer {
        id: restartTimer
        interval: 1500
        repeat: false
        onTriggered: {
            if (root.daemonEnabled && !bridgeProcess.running)
                bridgeProcess.running = true
        }
    }

    Timer {
        id: statePollTimer
        interval: 1200
        repeat: true
        running: root.enabled
        onTriggered: stateFile.reload()
    }

    FileView {
        id: stateFile
        path: Qt.resolvedUrl(root.statePath)
        watchChanges: true
        blockLoading: true
        onLoaded: {
            root.parseState(stateFile.text())
        }
        onLoadFailed: (error) => {
            if (error == FileViewError.FileNotFound) {
                if (root.sessionCount > 0) {
                    console.warn("[Orbitbar] State file temporarily unavailable; keeping previous sessions");
                    return;
                }
                root.resetState()
                stateFile.setText(JSON.stringify(root.state))
            } else {
                console.warn(`[Orbitbar] Failed to load state file: ${error}`)
            }
        }
    }
}
