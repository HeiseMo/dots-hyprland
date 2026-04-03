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
    readonly property string displayTitle: {
        if (!root.approvalFirst) {
            if (!focusedSession)
                return "Orbitbar";
            return focusedSession.title ?? focusedSession.session_id ?? focusedSession.tool ?? "Orbitbar";
        }

        if (root.pendingCount > 0)
            return root.pendingCount === 1 ? "1 needs input" : `${root.pendingCount} need input`;
        if (root.errorCount > 0)
            return root.errorCount === 1 ? "1 error" : `${root.errorCount} errors`;
        if (root.workingCount > 0)
            return root.workingCount === 1 ? "1 working" : `${root.workingCount} working`;
        if (root.doneCount > 0)
            return root.doneCount === 1 ? "1 done" : `${root.doneCount} done`;
        if (!headlineSession)
            return "Orbitbar";
        return headlineSession.title ?? headlineSession.session_id ?? headlineSession.tool ?? "Orbitbar";
    }
    readonly property string detailTitle: {
        if (!root.approvalFirst)
            return "";

        const summary = headlineSession?.summary ?? headlineSession?.detail ?? "";
        if (summary && root.popupSessionCount > 0)
            return `${headlineSession?.title ?? ""}`.trim().length > 0 ? `${headlineSession.title}` : summary;
        return "";
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

    implicitWidth: buttonBackground.implicitWidth
    implicitHeight: Appearance.sizes.barHeight
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

    Rectangle {
        id: buttonBackground
        anchors.centerIn: parent
        radius: Appearance.rounding.full
        color: root.containsMouse || root.expanded ? Appearance.colors.colSurfaceContainerHighest : Appearance.colors.colLayer1
        border.width: 1
        border.color: Qt.rgba(root.activeColor.r, root.activeColor.g, root.activeColor.b, focusedSession ? 0.82 : 0.24)
        implicitWidth: row.implicitWidth + 20
        implicitHeight: row.implicitHeight + 12

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: 6

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                width: 14
                height: 14
                radius: 7
                color: headlineSession ? Qt.rgba(root.activeColor.r, root.activeColor.g, root.activeColor.b, 0.18) : Appearance.colors.colSurfaceContainerHigh

                Rectangle {
                    anchors.centerIn: parent
                    width: 6
                    height: 6
                    radius: 3
                    color: headlineSession ? root.activeColor : Appearance.colors.colOutlineVariant
                }
            }

            ColumnLayout {
                spacing: 0
                Layout.maximumWidth: root.approvalFirst ? 220 : 180

                StyledText {
                    text: root.displayTitle
                    color: Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.small
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    Layout.fillWidth: true
                }

                StyledText {
                    visible: root.approvalFirst && text.length > 0
                    text: root.detailTitle
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    Layout.fillWidth: true
                }
            }

            StyledText {
                text: root.popupSessionCount > 1 ? `${root.popupSessionCount}` : ""
                visible: root.popupSessionCount > 1
                color: root.urgent ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.weight: root.urgent ? Font.Medium : Font.Normal
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
