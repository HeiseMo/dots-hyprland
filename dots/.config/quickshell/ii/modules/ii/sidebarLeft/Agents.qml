import QtQuick

/**
 * Agents tab intentionally renders no body content.
 *
 * The real terminal pad lives in Hyprland's special:agents workspace and is
 * controlled by the tab state itself, while the sidebar only keeps the tab bar
 * visible at the top.
 */
Item {
    id: root

    readonly property real desiredPanelHeight: 0
}
