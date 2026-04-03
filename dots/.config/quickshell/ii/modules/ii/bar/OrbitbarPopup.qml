import qs.modules.common
import qs.modules.common.widgets

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

LazyLoader {
    id: root

    signal requestClose()

    property Item hoverTarget
    property bool forcedOpen: false
    property var sessions: []
    property int sessionCount: 0
    property string selectedSessionId: sessions.length > 0 ? (sessions[0].session_id ?? "") : ""
    property string viewMode: "list"
    property string choiceScriptPath: `${Directories.scriptPath}/orbitbar/send_choice.py`
    property string focusScriptPath: `${Directories.scriptPath}/orbitbar/focus_terminal.py`
    property string statePath: Directories.orbitbarStatePath
    property bool approvalFirst: Config.options?.bar?.orbitbar?.approvalFirst ?? true

    readonly property real horizontalPadding: 14
    readonly property real verticalPadding: 14
    readonly property real panelWidth: viewMode === "list" ? 432 : 560
    readonly property var needsInputSessions: sessions.filter(session => (session?.ui_state ?? "idle") === "needs_input")
    readonly property var errorSessions: sessions.filter(session => (session?.ui_state ?? "idle") === "error")
    readonly property var workingSessions: sessions.filter(session => (session?.ui_state ?? "idle") === "working")
    readonly property var doneSessions: sessions.filter(session => (session?.ui_state ?? "idle") === "done")
    readonly property var idleSessions: sessions.filter(session => (session?.ui_state ?? "idle") === "idle")
    readonly property string overviewText: {
        const parts = [];
        if (needsInputSessions.length > 0)
            parts.push(needsInputSessions.length === 1 ? "1 needs input" : `${needsInputSessions.length} need input`);
        if (workingSessions.length > 0)
            parts.push(workingSessions.length === 1 ? "1 working" : `${workingSessions.length} working`);
        if (errorSessions.length > 0)
            parts.push(errorSessions.length === 1 ? "1 error" : `${errorSessions.length} errors`);
        if (parts.length === 0)
            return "Watching live agent terminals";
        return parts.join(" · ");
    }

    readonly property var selectedSession: {
        if (sessions.length === 0)
            return null;
        const matched = sessions.find(session => session.session_id === selectedSessionId);
        return matched ?? sessions[0];
    }
    readonly property var selectedPendingAction: selectedSession?.pending_action ?? null
    readonly property var selectedChoiceList: selectedPendingAction?.choices ?? selectedSession?.options ?? []
    readonly property bool selectedHasActions: (selectedSession?.actions ?? []).length > 0
    readonly property bool selectedHasChoices: selectedChoiceList.length > 0
    readonly property bool selectedHasPreview: ((selectedPendingAction?.preview ?? "") || (selectedSession?.preview ?? "")).length > 0
    readonly property bool selectedHasRecent: (selectedSession?.recent ?? []).length > 0
    readonly property bool selectedHasChangeSummary: (selectedPendingAction?.change_summary?.file_count ?? 0) > 0
    readonly property bool selectedNeedsInput: !!selectedPendingAction || selectedHasChoices || (selectedSession?.requires_action ?? false)

    active: hoverTarget && (hoverTarget.containsMouse || forcedOpen)

    onSessionsChanged: {
        if (sessions.length === 0) {
            selectedSessionId = "";
            viewMode = "list";
            return;
        }

        if (!selectedSessionId || !sessions.some(session => session.session_id === selectedSessionId))
            selectedSessionId = sessions[0].session_id ?? "";
    }

    function openThread(sessionId) {
        selectedSessionId = sessionId;
        viewMode = "detail";
    }

    function resetView() {
        viewMode = "list";
    }

    function submitChoice(option) {
        if (!selectedSession?.pid || !option?.id)
            return;

        const responseMode = option?.response_mode ?? selectedPendingAction?.response_mode ?? "direct_tty";
        if (responseMode === "focus_terminal") {
            focusTerminal();
            return;
        }

        Quickshell.execDetached([
            "python",
            choiceScriptPath,
            "--pid",
            `${selectedSession.pid}`,
            "--session-id",
            `${selectedSession.session_id ?? ""}`,
            "--state-path",
            `${statePath}`,
            "--choice-id",
            `${option.id}`,
        ]);

        if (selectedSession?.sensitive_input_required ?? false) {
            focusTerminal();
            return;
        }

        requestClose();
    }

    function focusTerminal() {
        if (!selectedSession?.window_address)
            return;
        Quickshell.execDetached([
            "python",
            focusScriptPath,
            "--address",
            `${selectedSession.window_address}`,
            "--special-name",
            "agents",
            "--move-to-special",
            "--show-special",
            "--focus",
        ]);
        requestClose();
    }

    function dispatchAction(action) {
        if (!action?.id)
            return;
        if (action.id === "focus_terminal" || action.id === "show_terminal")
            focusTerminal();
    }

    function pendingActionLabel(action) {
        const kind = action?.kind ?? "";
        switch (kind) {
        case "change_review":
            return "Change review";
        case "question":
            return "Input needed";
        default:
            return "Approval required";
        }
    }

    function uiStateLabel(uiState) {
        switch (uiState) {
        case "needs_input":
            return "Needs input";
        case "working":
            return "Working";
        case "done":
            return "Done";
        case "error":
            return "Error";
        default:
            return "Idle";
        }
    }

    function statusColorFor(status) {
        switch (status) {
        case "needs_input":
        case "approval_required":
            return Appearance.colors.colSecondary;
        case "question":
            return Appearance.colors.colPrimary;
        case "error":
            return Appearance.colors.colError;
        case "done":
            return Appearance.colors.colPrimary;
        default:
            return Appearance.colors.colTertiary;
        }
    }

    component ThreadBadge: Rectangle {
        required property string label

        radius: 8
        color: Appearance.colors.colLayer1
        border.width: 1
        border.color: Qt.rgba(Appearance.colors.colOutlineVariant.r, Appearance.colors.colOutlineVariant.g, Appearance.colors.colOutlineVariant.b, 0.4)
        implicitWidth: badgeText.implicitWidth + 12
        implicitHeight: badgeText.implicitHeight + 6

        StyledText {
            id: badgeText
            anchors.centerIn: parent
            text: parent.label
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smallest
        }
    }

    component SessionMetaRow: Row {
        required property var thread

        spacing: 6

        ThreadBadge {
            visible: !!parent.thread?.provider || !!parent.thread?.tool
            label: `${parent.thread?.provider ?? parent.thread?.tool ?? ""}`
        }

        ThreadBadge {
            visible: !!parent.thread?.project
            label: `${parent.thread?.project ?? ""}`
        }

        ThreadBadge {
            visible: !parent.thread?.project && !!parent.thread?.terminal_app
            label: `${parent.thread?.terminal_app ?? ""}`
        }

        StyledText {
            visible: text.length > 0
            text: parent.thread?.age ?? ""
            color: "#bfc0c7"
            font.pixelSize: Appearance.font.pixelSize.smallest
        }
    }

    component ActionPill: Rectangle {
        required property string label
        property bool emphasized: false

        radius: 10
        color: emphasized ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer1
        border.width: 1
        border.color: emphasized ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
        implicitWidth: pillText.implicitWidth + 18
        implicitHeight: pillText.implicitHeight + 10

        StyledText {
            id: pillText
            anchors.centerIn: parent
            text: parent.label
            color: parent.emphasized ? Appearance.colors.colOnPrimaryContainer : "#ffffff"
            font.pixelSize: Appearance.font.pixelSize.smallest
        }
    }

    component SectionHeader: Row {
        required property string title
        required property int count

        spacing: 8

        StyledText {
            text: parent.title
            color: "#ffffff"
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.Medium
        }

        StyledText {
            text: `${parent.count}`
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smallest
        }
    }

    component SessionCard: RippleButton {
        required property var thread

        readonly property color stateColor: root.statusColorFor(thread?.ui_state ?? thread?.status ?? "idle")
        readonly property string stateLabel: root.uiStateLabel(thread?.ui_state ?? "idle")
        readonly property string summaryText: `${thread?.summary ?? thread?.detail ?? ""}`
        readonly property var primaryAction: thread?.primary_action ?? null

        implicitWidth: parent.width
        implicitHeight: cardBody.childrenRect.height + 20
        buttonRadius: 14
        colBackground: Qt.rgba(Appearance.colors.colLayer1.r, Appearance.colors.colLayer1.g, Appearance.colors.colLayer1.b, 0.72)
        colBackgroundHover: Appearance.colors.colSurfaceContainerHighest
        colBackgroundToggled: colBackground
        colBackgroundToggledHover: colBackgroundHover
        colRipple: Appearance.colors.colSurfaceContainerHighestActive
        colRippleToggled: colRipple
        releaseAction: () => root.openThread(thread?.session_id ?? "")

        contentItem: Column {
            id: cardBody
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8

            Row {
                width: parent.width
                spacing: 8

                Rectangle {
                    y: 5
                    width: 8
                    height: 8
                    radius: 4
                    color: stateColor
                }

                StyledText {
                    width: metaRow.visible ? parent.width - metaRow.width - 18 : parent.width - 18
                    text: `${thread?.title ?? thread?.session_id ?? "untitled"}`
                    color: "#ffffff"
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                SessionMetaRow {
                    id: metaRow
                    visible: implicitWidth > 0
                    thread: thread
                }
            }

            StyledText {
                width: parent.width
                text: summaryText
                color: "#d3d6de"
                font.pixelSize: Appearance.font.pixelSize.smallest
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }

            Row {
                spacing: 8

                ActionPill {
                    label: stateLabel
                    emphasized: thread?.ui_state === "needs_input"
                }

                ActionPill {
                    visible: !!primaryAction?.label
                    label: `${primaryAction?.label ?? ""}`
                    emphasized: true
                }
            }
        }
    }

    component DetailCard: Rectangle {
        width: root.panelWidth - root.horizontalPadding * 2
        radius: 16
        color: Appearance.colors.colSurfaceContainer
        border.width: 1
        border.color: Qt.rgba(root.statusColorFor(root.selectedSession?.ui_state ?? root.selectedSession?.status ?? "idle").r, root.statusColorFor(root.selectedSession?.ui_state ?? root.selectedSession?.status ?? "idle").g, root.statusColorFor(root.selectedSession?.ui_state ?? root.selectedSession?.status ?? "idle").b, 0.3)
        implicitHeight: detailBody.childrenRect.height + 24

        Column {
            id: detailBody
            x: 12
            y: 12
            width: parent.width - 24
            spacing: 10

            StyledText {
                width: parent.width
                text: root.selectedSession?.title ?? "Thread"
                color: "#ffffff"
                font.pixelSize: 18
                font.weight: Font.DemiBold
                wrapMode: Text.Wrap
            }

            SessionMetaRow {
                thread: root.selectedSession
            }

            StyledText {
                width: parent.width
                text: root.selectedSession?.summary ?? root.selectedSession?.detail ?? "No details"
                color: "#ffffff"
                opacity: 0.92
                font.pixelSize: Appearance.font.pixelSize.small
                wrapMode: Text.Wrap
            }

            ThreadBadge {
                visible: !!root.selectedPendingAction
                label: root.pendingActionLabel(root.selectedPendingAction)
            }

            Rectangle {
                visible: root.selectedHasChangeSummary
                width: parent.width
                radius: 12
                color: Appearance.colors.colLayer1
                border.width: 1
                border.color: Appearance.colors.colOutlineVariant
                implicitHeight: changeSummaryBody.childrenRect.height + 16

                Column {
                    id: changeSummaryBody
                    x: 8
                    y: 8
                    width: parent.width - 16
                    spacing: 4

                    StyledText {
                        text: `${root.selectedPendingAction?.change_summary?.file_count ?? 0} file${(root.selectedPendingAction?.change_summary?.file_count ?? 0) === 1 ? "" : "s"} in this change`
                        color: "#ffffff"
                        font.pixelSize: Appearance.font.pixelSize.smallest
                    }

                    StyledText {
                        visible: (root.selectedPendingAction?.change_summary?.files ?? []).length > 0
                        width: parent.width
                        text: `${(root.selectedPendingAction?.change_summary?.files ?? []).join("\n")}`
                        color: "#ffffff"
                        opacity: 0.82
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        wrapMode: Text.Wrap
                    }
                }
            }

            Rectangle {
                visible: root.selectedHasPreview
                width: parent.width
                radius: 12
                color: Appearance.colors.colLayer1
                border.width: 1
                border.color: Appearance.colors.colOutlineVariant
                implicitHeight: previewText.implicitHeight + 18

                StyledText {
                    id: previewText
                    x: 9
                    y: 9
                    width: parent.width - 18
                    text: root.selectedPendingAction?.preview ?? root.selectedSession?.preview ?? ""
                    color: "#ffffff"
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    wrapMode: Text.Wrap
                }
            }

            Column {
                visible: root.selectedHasChoices
                width: parent.width
                spacing: 8

                Repeater {
                    model: root.selectedChoiceList

                    delegate: RippleButton {
                        readonly property var option: modelData

                        implicitHeight: optionBody.childrenRect.height + 16
                        implicitWidth: parent.width
                        buttonRadius: 12
                        colBackground: Appearance.colors.colPrimaryContainer
                        colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                        colBackgroundToggled: colBackground
                        colBackgroundToggledHover: colBackgroundHover
                        colRipple: Appearance.colors.colPrimaryContainerActive
                        colRippleToggled: colRipple
                        releaseAction: () => root.submitChoice(option)

                        contentItem: Column {
                            id: optionBody
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 2

                            StyledText {
                                width: parent.width
                                text: `${option.label ?? option.id ?? ""}`
                                color: Appearance.colors.colOnPrimaryContainer
                                font.pixelSize: Appearance.font.pixelSize.small
                                wrapMode: Text.Wrap
                            }

                            StyledText {
                                visible: text.length > 0
                                width: parent.width
                                text: `${option.description ?? ""}`
                                color: Appearance.colors.colOnPrimaryContainer
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                opacity: 0.82
                                wrapMode: Text.Wrap
                            }
                        }
                    }
                }
            }

            Flow {
                visible: root.selectedHasActions
                width: parent.width
                spacing: 8

                Repeater {
                    model: root.selectedSession?.actions ?? []

                    delegate: RippleButton {
                        readonly property var actionModel: modelData

                        implicitWidth: actionBody.implicitWidth + 18
                        implicitHeight: actionBody.implicitHeight + 10
                        buttonRadius: 10
                        colBackground: actionModel.emphasized ?? false ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer1
                        colBackgroundHover: actionModel.emphasized ?? false ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colLayer1Hover
                        colBackgroundToggled: colBackground
                        colBackgroundToggledHover: colBackgroundHover
                        colRipple: actionModel.emphasized ?? false ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colLayer1Active
                        colRippleToggled: colRipple
                        releaseAction: () => root.dispatchAction(actionModel)

                        contentItem: StyledText {
                            id: actionBody
                            anchors.centerIn: parent
                            text: `${actionModel.label ?? actionModel.id ?? actionModel}`
                            color: actionModel.emphasized ?? false ? Appearance.colors.colOnPrimaryContainer : "#ffffff"
                            font.pixelSize: Appearance.font.pixelSize.smallest
                        }
                    }
                }
            }

            Row {
                visible: !!root.selectedSession && !root.selectedNeedsInput
                spacing: 10

                Rectangle {
                    width: 22
                    height: 22
                    radius: 11
                    color: Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.14)

                    StyledText {
                        anchors.centerIn: parent
                        text: "✓"
                        color: Appearance.colors.colPrimary
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                }

                StyledText {
                    text: "No action needed"
                    color: "#ffffff"
                    font.pixelSize: Appearance.font.pixelSize.small
                }
            }
        }
    }

    component RecentCard: Rectangle {
        visible: root.selectedHasRecent
        width: root.panelWidth - root.horizontalPadding * 2
        radius: 16
        color: Appearance.colors.colSurfaceContainer
        border.width: 1
        border.color: Qt.rgba(Appearance.colors.colOutlineVariant.r, Appearance.colors.colOutlineVariant.g, Appearance.colors.colOutlineVariant.b, 0.4)
        implicitHeight: recentBody.childrenRect.height + 24

        Column {
            id: recentBody
            x: 12
            y: 12
            width: parent.width - 24
            spacing: 8

            StyledText {
                text: "Recent activity"
                color: "#ffffff"
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Medium
            }

            Repeater {
                model: root.selectedSession?.recent ?? []

                delegate: Row {
                    width: parent.width
                    spacing: 8

                    Rectangle {
                        y: 6
                        width: 4
                        height: 4
                        radius: 2
                        color: root.statusColorFor(root.selectedSession?.ui_state ?? root.selectedSession?.status ?? "idle")
                    }

                    StyledText {
                        width: parent.width - 12
                        text: `${modelData}`
                        color: "#ffffff"
                        opacity: 0.82
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        wrapMode: Text.Wrap
                    }
                }
            }
        }
    }

    component: PanelWindow {
        id: popupWindow

        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        WlrLayershell.namespace: "quickshell:popup"
        WlrLayershell.layer: WlrLayer.Overlay

        anchors.top: true
        anchors.left: true

        implicitWidth: panel.implicitWidth + Appearance.sizes.elevationMargin * 2
        implicitHeight: panel.implicitHeight + Appearance.sizes.elevationMargin * 2

        margins {
            left: root.QsWindow?.mapFromItem(root.hoverTarget, (root.hoverTarget.width - panel.implicitWidth) / 2, 0).x ?? 0
            top: Appearance.sizes.barHeight + 4
        }

        mask: Region {
            item: panel
        }

        StyledRectangularShadow {
            target: panel
            opacity: 0.45
        }

        Rectangle {
            id: panel
            anchors.fill: parent
            anchors.margins: Appearance.sizes.elevationMargin
            radius: 18
            color: Qt.rgba(Appearance.colors.colLayer0.r, Appearance.colors.colLayer0.g, Appearance.colors.colLayer0.b, 0.96)
            border.width: 1
            border.color: Qt.rgba(Appearance.colors.colOutlineVariant.r, Appearance.colors.colOutlineVariant.g, Appearance.colors.colOutlineVariant.b, 0.45)
            implicitWidth: root.panelWidth
            implicitHeight: (root.viewMode === "list" ? listBody.implicitHeight : detailBody.implicitHeight) + root.verticalPadding * 2

            Item {
                anchors.fill: parent

                Item {
                    id: listBody
                    x: root.horizontalPadding
                    y: root.verticalPadding
                    width: parent.width - root.horizontalPadding * 2
                    visible: root.viewMode === "list"
                    implicitHeight: listColumn.childrenRect.height

                    Column {
                        id: listColumn
                        width: parent.width
                        spacing: 10

                        StyledText {
                            text: "Orbitbar"
                            color: Appearance.colors.colOnSurface
                            font.pixelSize: Appearance.font.pixelSize.large
                            font.weight: Font.DemiBold
                        }

                        StyledText {
                            width: parent.width
                            text: root.overviewText
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            wrapMode: Text.Wrap
                        }

                        Column {
                            visible: root.approvalFirst && root.needsInputSessions.length > 0
                            width: parent.width
                            spacing: 8

                            SectionHeader {
                                title: "Needs input"
                                count: root.needsInputSessions.length
                            }

                            Repeater {
                                model: root.needsInputSessions
                                delegate: SessionCard {
                                    thread: modelData
                                }
                            }
                        }

                        Column {
                            visible: root.approvalFirst && root.errorSessions.length > 0
                            width: parent.width
                            spacing: 8

                            SectionHeader {
                                title: "Errors"
                                count: root.errorSessions.length
                            }

                            Repeater {
                                model: root.errorSessions
                                delegate: SessionCard {
                                    thread: modelData
                                }
                            }
                        }

                        Column {
                            visible: root.approvalFirst && root.workingSessions.length > 0
                            width: parent.width
                            spacing: 8

                            SectionHeader {
                                title: "Working"
                                count: root.workingSessions.length
                            }

                            Repeater {
                                model: root.workingSessions
                                delegate: SessionCard {
                                    thread: modelData
                                }
                            }
                        }

                        Column {
                            visible: root.approvalFirst && (root.idleSessions.length + root.doneSessions.length) > 0
                            width: parent.width
                            spacing: 8

                            SectionHeader {
                                title: "Idle and done"
                                count: root.idleSessions.length + root.doneSessions.length
                            }

                            Repeater {
                                model: root.idleSessions.concat(root.doneSessions)
                                delegate: SessionCard {
                                    thread: modelData
                                }
                            }
                        }

                        Column {
                            visible: !root.approvalFirst && root.sessions.length > 0
                            width: parent.width
                            spacing: 8

                            Repeater {
                                model: root.sessions
                                delegate: SessionCard {
                                    thread: modelData
                                }
                            }
                        }

                        Rectangle {
                            visible: root.sessions.length === 0
                            radius: 16
                            color: Appearance.colors.colSurfaceContainer
                            border.width: 1
                            border.color: Appearance.colors.colOutlineVariant
                            width: parent.width
                            implicitHeight: emptyStateBody.childrenRect.height + 24

                            Column {
                                id: emptyStateBody
                                x: 12
                                y: 12
                                width: parent.width - 24
                                spacing: 6

                                StyledText {
                                    text: "No live agent terminals"
                                    color: "#ffffff"
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: Font.Medium
                                }

                                StyledText {
                                    width: parent.width
                                    text: "Orbitbar appears when Codex, Gemini, or Claude sessions are active and gives you a fast jump point for approvals and follow-up."
                                    color: Appearance.colors.colSubtext
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    wrapMode: Text.Wrap
                                }
                            }
                        }
                    }
                }

                Item {
                    id: detailBody
                    x: root.horizontalPadding
                    y: root.verticalPadding
                    width: parent.width - root.horizontalPadding * 2
                    visible: root.viewMode === "detail"
                    implicitHeight: detailColumn.childrenRect.height

                    Column {
                        id: detailColumn
                        width: parent.width
                        spacing: 10

                        RippleButton {
                            implicitWidth: 36
                            implicitHeight: 32
                            buttonRadius: 10
                            colBackground: Appearance.colors.colLayer1
                            colBackgroundHover: Appearance.colors.colLayer1Hover
                            colRipple: Appearance.colors.colLayer1Active
                            releaseAction: root.resetView

                            contentItem: StyledText {
                                anchors.centerIn: parent
                                text: "←"
                                color: "#ffffff"
                                font.pixelSize: Appearance.font.pixelSize.small
                            }
                        }

                        DetailCard {}
                        RecentCard {}
                    }
                }
            }
        }
    }
}
