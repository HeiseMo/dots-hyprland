pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

/**
 * AgentWorkspace — manages real terminal windows attached to the Agents pad.
 *
 * Attached terminals are moved to Hyprland's special:agents workspace and
 * arranged so the active one overlays the left sidebar footprint. When the
 * user leaves the Agents tab, the special workspace is hidden again.
 */
Singleton {
    id: root

    readonly property string specialWorkspaceName: "agents"
    readonly property string specialWorkspaceRef: `special:${root.specialWorkspaceName}`
    readonly property real overlayWidth: Math.round(
        Appearance.sizes.sidebarWidth
        - Appearance.sizes.hyprlandGapsOut
        - Appearance.sizes.elevationMargin
    )

    // Ordered list of attached window addresses.
    property var sessionNames: []
    // Map address -> { address, title, className, workspace, provider }
    property var sessions: ({})
    property string activeSession: ""
    property string dependencyStatus: ""
    property bool overlayDesired: false
    property bool overlayToggleInFlight: false

    GlobalShortcut {
        name: "agentWorkspaceSpawn"
        description: "Attach focused terminal to the Agents pad"
        onPressed: { root.attachFocusedWindow(); }
    }

    GlobalShortcut {
        name: "agentWorkspaceFocusLatest"
        description: "Open Agents tab and focus the most recent attached terminal"
        onPressed: { root.focusLatest(); }
    }

    Component.onCompleted: {
        root._refreshSessions();
        root.overlayDesired = root._shouldShowOverlay();
        Qt.callLater(root._reconcileOverlayVisibility);
    }

    Connections {
        target: GlobalStates

        function onSidebarLeftOpenChanged() {
            Qt.callLater(root._requestOverlaySync);
        }

        function onSidebarLeftTabChanged() {
            Qt.callLater(root._requestOverlaySync);
        }
    }

    Connections {
        target: HyprlandData

        function onWindowListChanged() {
            root._refreshSessions();
            Qt.callLater(root._requestOverlaySync);
            Qt.callLater(root._arrangeWindows);
        }

        function onMonitorsChanged() {
            Qt.callLater(root._onOverlayStateObserved);
        }
    }

    function openAgentsView() {
        GlobalStates.sidebarLeftTab = 0;
        GlobalStates.sidebarLeftOpen = true;
        Qt.callLater(root._requestOverlaySync);
    }

    function closeAgentsView() {
        GlobalStates.sidebarLeftOpen = false;
        root.overlayDesired = false;
        root.overlayToggleInFlight = false;
        overlaySyncTimer.stop();

        if (root.sessionNames.length > 0)
            Hyprland.dispatch(`togglespecialworkspace ${root.specialWorkspaceName}`);
    }

    function shouldUseOverlayToggle() {
        return root.sessionNames.length > 0
            && (GlobalStates.sidebarLeftTab === 0 || root._overlayActuallyVisible());
    }

    function attachFocusedWindow() {
        if (!focusedWindowProc.running)
            focusedWindowProc.running = true;
    }

    function focusLatest() {
        if (root.sessionNames.length === 0) {
            root.openAgentsView();
            return;
        }

        root.focusSession(root.sessionNames[root.sessionNames.length - 1]);
    }

    function focusSession(address) {
        if (!root.sessions[address])
            return;

        root.activeSession = address;
        root.openAgentsView();
        Qt.callLater(root._arrangeWindows);
        Qt.callLater(() => root._focusWindow(address));
    }

    function detachSession(address) {
        if (!root.sessions[address])
            return;

        const targetWorkspace = String(HyprlandData.activeWorkspace?.name ?? "1");
        Hyprland.dispatch(`movetoworkspacesilent ${targetWorkspace},address:${address}`);
        Hyprland.dispatch(`settiled address:${address}`);
        HyprlandData.updateAll();
    }

    function _refreshSessions() {
        const windows = HyprlandData.windowList
            .filter(win => String(win?.workspace?.name ?? "") === root.specialWorkspaceRef)
            .sort((a, b) => {
                const ax = a?.at?.[0] ?? 0;
                const bx = b?.at?.[0] ?? 0;
                return ax - bx;
            });

        const nextSessions = {};
        const nextNames = [];

        for (const win of windows) {
            const address = String(win.address ?? "");
            if (address.length === 0)
                continue;

            nextSessions[address] = {
                address: address,
                title: String(win.title ?? ""),
                className: String(win.class ?? ""),
                workspace: String(win.workspace?.name ?? ""),
                provider: root._providerForWindow(win),
            };
            nextNames.push(address);
        }

        root.sessions = nextSessions;
        root.sessionNames = nextNames;

        if (!root.sessions[root.activeSession])
            root.activeSession = nextNames.length > 0 ? nextNames[0] : "";
    }

    function _providerForWindow(win) {
        const text = `${win?.class ?? ""} ${win?.title ?? ""}`.toLowerCase();
        if (text.includes("claude"))
            return "claude";
        if (text.includes("codex"))
            return "codex";
        if (text.includes("gemini"))
            return "gemini";
        if (text.includes("kimi"))
            return "kimi";
        return "";
    }

    function _shouldShowOverlay() {
        return GlobalStates.sidebarLeftOpen
            && GlobalStates.sidebarLeftTab === 0
            && root.sessionNames.length > 0;
    }

    function _overlayActuallyVisible() {
        return HyprlandData.monitors.some(m => String(m?.specialWorkspace?.name ?? "") === root.specialWorkspaceName);
    }

    function _focusedMonitor() {
        return HyprlandData.monitors.find(m => !!m.focused) ?? HyprlandData.monitors[0] ?? null;
    }

    function _overlayRect() {
        const monitor = root._focusedMonitor();
        if (!monitor)
            return null;

        const gap = Math.round(Appearance.sizes.hyprlandGapsOut);
        const topInset = Math.max(132, Number(monitor?.reserved?.[1] ?? 0) + 92);
        const bottomInset = 80;

        return {
            x: Math.round(Number(monitor.x ?? 0) + gap),
            y: Math.round(Number(monitor.y ?? 0) + topInset),
            width: Math.max(320, Math.round(root.overlayWidth)),
            height: Math.max(280, Math.round(Number(monitor.height ?? 0) - topInset - bottomInset)),
            monitorX: Math.round(Number(monitor.x ?? 0)),
            monitorWidth: Math.round(Number(monitor.width ?? 0)),
        };
    }

    function _requestOverlaySync() {
        root.overlayDesired = root._shouldShowOverlay();
        overlaySyncTimer.restart();
    }

    function _onOverlayStateObserved() {
        const actualVisible = root._overlayActuallyVisible();

        if (actualVisible === root.overlayDesired)
            root.overlayToggleInFlight = false;

        if (!actualVisible
                && root.overlayDesired
                && !root.overlayToggleInFlight
                && GlobalStates.sidebarLeftOpen
                && GlobalStates.sidebarLeftTab === 0
                && root.sessionNames.length > 0) {
            root.overlayDesired = false;
            GlobalStates.sidebarLeftOpen = false;
        }

        overlaySyncTimer.restart();
    }

    function _reconcileOverlayVisibility() {
        const actualVisible = root._overlayActuallyVisible();

        if (actualVisible === root.overlayDesired) {
            root.overlayToggleInFlight = false;
            if (actualVisible)
                Qt.callLater(root._arrangeWindows);
            return;
        }

        if (root.overlayToggleInFlight)
            return;

        root.overlayToggleInFlight = true;
        Hyprland.dispatch(`togglespecialworkspace ${root.specialWorkspaceName}`);
        overlaySyncTimer.restart();
    }

    function _arrangeWindows() {
        if (!root._shouldShowOverlay() || root.sessionNames.length === 0 || !root._overlayActuallyVisible())
            return;

        const rect = root._overlayRect();
        if (!rect)
            return;

        const activeAddress = root.sessions[root.activeSession]
            ? root.activeSession
            : root.sessionNames[0];
        const otherAddresses = root.sessionNames.filter(address => address !== activeAddress);
        const gap = Math.round(Appearance.sizes.hyprlandGapsOut);

        root._placeWindow(activeAddress, rect.x, rect.y, rect.width, rect.height);

        if (otherAddresses.length === 0)
            return;

        const rightX = rect.x + rect.width + gap;
        const rightWidth = Math.max(300, (rect.monitorX + rect.monitorWidth) - rightX - gap);
        const columnCount = otherAddresses.length;
        const itemWidth = Math.max(300, Math.floor((rightWidth - gap * (columnCount - 1)) / columnCount));

        for (let i = 0; i < otherAddresses.length; ++i) {
            const x = rightX + i * (itemWidth + gap);
            root._placeWindow(otherAddresses[i], x, rect.y, itemWidth, rect.height);
        }
    }

    function _placeWindow(address, x, y, width, height) {
        Hyprland.dispatch(`setfloating address:${address}`);
        Hyprland.dispatch(`movewindowpixel exact ${Math.round(x)} ${Math.round(y)},address:${address}`);
        Hyprland.dispatch(`resizewindowpixel exact ${Math.round(width)} ${Math.round(height)},address:${address}`);
    }

    function _focusWindow(address) {
        if (address.length > 0)
            Hyprland.dispatch(`focuswindow address:${address}`);
    }

    function _looksLikeTerminal(win) {
        const className = String(win?.class ?? "").toLowerCase();
        const title = String(win?.title ?? "").toLowerCase();
        const knownClasses = [
            "kitty",
            "foot",
            "alacritty",
            "wezterm",
            "konsole",
            "kgx",
            "xterm",
            "ghostty",
            "warp",
            "claude",
            "codex",
            "gemini",
            "kimi",
        ];

        return knownClasses.some(token => className.includes(token) || title.includes(token));
    }

    Process {
        id: focusedWindowProc
        command: ["hyprctl", "activewindow", "-j"]
        property string _buf: ""

        stdout: SplitParser {
            splitMarker: ""
            onRead: data => { focusedWindowProc._buf += data; }
        }

        onExited: (code) => {
            const raw = focusedWindowProc._buf;
            focusedWindowProc._buf = "";

            if (code !== 0 || raw.trim().length === 0) {
                root.dependencyStatus = "Could not read the focused window.";
                return;
            }

            let win = null;
            try {
                win = JSON.parse(raw);
            } catch (e) {
                root.dependencyStatus = "Could not parse the focused window.";
                return;
            }

            const address = String(win?.address ?? "");
            if (address.length === 0) {
                root.dependencyStatus = "Focus a terminal window first.";
                return;
            }

            if (!root._looksLikeTerminal(win)) {
                root.dependencyStatus = "Focus a terminal window first, then press Super+Ctrl+A.";
                return;
            }

            root.dependencyStatus = "";
            root.activeSession = address;
            Hyprland.dispatch(`movetoworkspacesilent ${root.specialWorkspaceRef},address:${address}`);
            Hyprland.dispatch(`setfloating address:${address}`);
            root.openAgentsView();
            HyprlandData.updateAll();
            root._requestOverlaySync();
            Qt.callLater(root._arrangeWindows);
            Qt.callLater(() => root._focusWindow(address));
        }

        running: false
    }

    Timer {
        id: overlaySyncTimer
        interval: 80
        repeat: false
        onTriggered: root._reconcileOverlayVisibility()
    }
}
