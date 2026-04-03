import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

MouseArea {
    id: root

    property bool expanded: false
    property var popupSessions: Orbitbar.sessions ?? []
    property int popupSessionCount: Orbitbar.sessionCount ?? 0
    property string selectedSessionId: popupSessions.length > 0 ? (popupSessions[0].session_id ?? "") : ""
    readonly property bool approvalFirst: Config.options?.bar?.orbitbar?.approvalFirst ?? true
    readonly property var focusedSession: Orbitbar.focusedSession
    readonly property var headlineSession: Orbitbar.headlineSession
    readonly property int pendingCount: Orbitbar.pendingCount ?? 0
    readonly property int workingCount: Orbitbar.workingCount ?? 0
    readonly property int errorCount: Orbitbar.errorCount ?? 0
    readonly property int doneCount: Orbitbar.doneCount ?? 0
    readonly property int idleCount: Math.max(0, root.popupSessionCount - root.pendingCount - root.errorCount - root.workingCount - root.doneCount)
    readonly property bool hasLiveSessions: root.popupSessionCount > 0
    readonly property bool hasUrgentSessions: root.pendingCount > 0 || root.errorCount > 0
    readonly property string captionText: {
        if (!root.hasLiveSessions)
            return "Watching terminals";
        if (root.pendingCount > 0)
            return "Approval queue";
        if (root.errorCount > 0)
            return "Needs attention";
        if (root.workingCount > 0)
            return "Active agents";
        return "Quiet sessions";
    }
    readonly property string displayTitle: {
        if (!root.approvalFirst) {
            if (!focusedSession)
                return "Orbitbar idle";
            return focusedSession.title ?? focusedSession.session_id ?? focusedSession.tool ?? "Orbitbar";
        }

        if (root.pendingCount > 0)
            return root.pendingCount === 1 ? "1 thread waiting" : `${root.pendingCount} threads waiting`;
        if (root.errorCount > 0)
            return root.errorCount === 1 ? "1 thread errored" : `${root.errorCount} threads errored`;
        if (root.workingCount > 0)
            return root.workingCount === 1 ? "1 thread running" : `${root.workingCount} threads running`;
        if (root.popupSessionCount > 0)
            return root.popupSessionCount === 1 ? "1 thread in view" : `${root.popupSessionCount} threads in view`;
        return "Orbitbar idle";
    }
    readonly property string detailTitle: {
        if (!root.approvalFirst) {
            const summary = focusedSession?.summary ?? focusedSession?.detail ?? "";
            return summary.length > 0 ? summary : "Jump into the currently focused agent terminal";
        }

        const summary = headlineSession?.summary ?? headlineSession?.detail ?? "";
        if (summary.length > 0)
            return summary;
        if (root.pendingCount > 0)
            return "Approvals and questions rise to the top";
        if (root.errorCount > 0)
            return "Errors stay visible until you inspect them";
        if (root.workingCount > 0)
            return "Live sessions stay visible without dominating the bar";
        return "Ready to surface the next action when a terminal needs you";
    }
    readonly property bool urgent: {
        const state = headlineSession?.ui_state ?? "idle";
        return state === "needs_input" || state === "error";
    }
    readonly property color activeColor: {
        const state = headlineSession?.ui_state ?? "idle";
        switch (state) {
        case "needs_input":
            return Appearance.colors.colSecondaryContainer;
        case "error":
            return Appearance.colors.colError;
        case "working":
            return Appearance.colors.colPrimary;
        case "done":
            return Appearance.colors.colPrimaryContainer;
        default:
            return Appearance.colors.colLayer1Hover;
        }
    }
    readonly property color surfaceColor: {
        if (root.expanded)
            return Appearance.colors.colSurfaceContainerHighest;
        if (root.urgent)
            return Qt.rgba(root.activeColor.r, root.activeColor.g, root.activeColor.b, 0.16);
        if (root.hasLiveSessions)
            return Appearance.colors.colSurfaceContainer;
        return Appearance.colors.colLayer1;
    }
    readonly property color baseOutlineColor: {
        if (root.expanded)
            return Qt.rgba(root.activeColor.r, root.activeColor.g, root.activeColor.b, 0.82);
        if (root.hasUrgentSessions)
            return Qt.rgba(root.activeColor.r, root.activeColor.g, root.activeColor.b, 0.58);
        if (root.hasLiveSessions)
            return Qt.rgba(Appearance.colors.colOutline.r, Appearance.colors.colOutline.g, Appearance.colors.colOutline.b, 0.72);
        return Qt.rgba(Appearance.colors.colOutlineVariant.r, Appearance.colors.colOutlineVariant.g, Appearance.colors.colOutlineVariant.b, 0.9);
    }
    readonly property color accentOutlineColor: {
        if (!root.hasLiveSessions)
            return Qt.rgba(1, 1, 1, 0.05);
        if (root.expanded)
            return Qt.rgba(1, 1, 1, 0.12);
        return Qt.rgba(root.activeColor.r, root.activeColor.g, root.activeColor.b, root.hasUrgentSessions ? 0.26 : 0.14);
    }
    readonly property var statusChips: {
        const chips = [];
        if (root.pendingCount > 0) {
            chips.push({
                label: root.pendingCount === 1 ? "1 waiting" : `${root.pendingCount} waiting`,
                background: Appearance.colors.colSecondaryContainer,
                foreground: Appearance.colors.colOnSecondaryContainer,
            });
        }
        if (root.errorCount > 0) {
            chips.push({
                label: root.errorCount === 1 ? "1 error" : `${root.errorCount} errors`,
                background: Appearance.colors.colErrorContainer,
                foreground: Appearance.colors.colOnErrorContainer,
            });
        }
        if (root.workingCount > 0) {
            chips.push({
                label: root.workingCount === 1 ? "1 active" : `${root.workingCount} active`,
                background: Appearance.colors.colPrimaryContainer,
                foreground: Appearance.colors.colOnPrimaryContainer,
            });
        }
        if (chips.length === 0 && root.hasLiveSessions) {
            chips.push({
                label: root.popupSessionCount === 1 ? "1 open" : `${root.popupSessionCount} open`,
                background: Appearance.colors.colLayer1Hover,
                foreground: Appearance.colors.colOnLayer1,
            });
        }
        return chips.slice(0, 2);
    }

    implicitWidth: buttonBackground.implicitWidth
    implicitHeight: Appearance.sizes.baseBarHeight
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton

    onPressed: mouse => {
        if (mouse.button === Qt.LeftButton)
            root.expanded = !root.expanded;
    }

    onPopupSessionsChanged: {
        if (popupSessions.length === 0) {
            root.selectedSessionId = "";
            return;
        }
        const stillExists = popupSessions.some(session => session.session_id === root.selectedSessionId);
        if (!stillExists)
            root.selectedSessionId = popupSessions[0].session_id ?? "";
    }

    component StatusChip: Rectangle {
        required property string label
        required property color backgroundColor
        required property color foregroundColor

        radius: 9
        color: backgroundColor
        implicitWidth: chipText.implicitWidth + 12
        implicitHeight: chipText.implicitHeight + 6

        StyledText {
            id: chipText
            anchors.centerIn: parent
            text: parent.label
            color: parent.foregroundColor
            font.pixelSize: Appearance.font.pixelSize.smallest
            font.weight: Font.Medium
        }
    }

    StyledRectangularShadow {
        target: buttonBackground
        visible: root.expanded || root.hasUrgentSessions
        opacity: root.expanded ? 0.34 : 0.18
    }

    Rectangle {
        id: buttonBackground
        anchors.centerIn: parent
        anchors.verticalCenterOffset: Config.options.bar.bottom ? -1 : 1
        radius: 18
        color: root.containsMouse ? Appearance.colors.colSurfaceContainerHighestHover : root.surfaceColor
        border.width: 0
        implicitWidth: row.implicitWidth + 18
        implicitHeight: Math.min(Appearance.sizes.baseBarHeight - 5, row.implicitHeight + 10)

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "transparent"
            border.width: 1
            border.color: root.baseOutlineColor
        }

        Rectangle {
            anchors {
                fill: parent
                margins: 1
            }
            radius: parent.radius - 1
            color: Qt.rgba(root.activeColor.r, root.activeColor.g, root.activeColor.b, root.hasUrgentSessions ? 0.06 : 0)
        }

        Rectangle {
            anchors {
                fill: parent
                margins: 1
            }
            radius: parent.radius - 1
            color: "transparent"
            border.width: 1
            border.color: root.accentOutlineColor
        }

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: 8

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                width: 22
                height: 22
                radius: 11
                color: headlineSession ? Qt.rgba(root.activeColor.r, root.activeColor.g, root.activeColor.b, 0.18) : Appearance.colors.colSurfaceContainerHigh

                Rectangle {
                    anchors.centerIn: parent
                    width: root.pendingCount > 0 ? 8 : 6
                    height: root.pendingCount > 0 ? 8 : 6
                    radius: width / 2
                    color: headlineSession ? root.activeColor : Appearance.colors.colOutlineVariant
                }
            }

            ColumnLayout {
                spacing: 1
                Layout.maximumWidth: root.approvalFirst ? 250 : 200

                StyledText {
                    text: root.captionText
                    color: root.hasUrgentSessions ? root.activeColor : Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: root.hasUrgentSessions ? Font.Medium : Font.Normal
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    Layout.fillWidth: true
                }

                StyledText {
                    text: root.hasLiveSessions ? root.displayTitle : root.detailTitle
                    color: Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    Layout.fillWidth: true
                }
            }

            ColumnLayout {
                Layout.alignment: Qt.AlignVCenter
                spacing: 4
                visible: root.statusChips.length > 0

                Repeater {
                    model: root.statusChips

                    delegate: StatusChip {
                        label: modelData.label
                        backgroundColor: modelData.background
                        foregroundColor: modelData.foreground
                    }
                }
            }
        }
    }

    OrbitbarPopup {
        hoverTarget: root
        forcedOpen: root.expanded
        selectedSessionId: root.selectedSessionId
        sessions: root.popupSessions
        sessionCount: root.popupSessionCount
        onSelectedSessionIdChanged: root.selectedSessionId = selectedSessionId
        onRequestClose: root.expanded = false
    }
}
