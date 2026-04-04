import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.sidebarLeft.agents
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell

/**
 * Agents sidebar tab — multi-session chat launcher.
 * Each session wraps a provider CLI (Claude, Codex, Gemini, Kimi) as a
 * streaming process and renders the conversation through the shared AiMessage
 * components, just like the Intelligence tab but supporting multiple concurrent
 * sessions with a session picker.
 */
Item {
    id: root

    property real padding: 4

    // ── Session state ─────────────────────────────────────────────────────
    property var sessions: []       // list of AgentSession instances
    property int activeIdx: -1
    readonly property var activeSession: sessions.length > 0 && activeIdx >= 0
        ? sessions[Math.min(activeIdx, sessions.length - 1)]
        : null

    // Provider definitions
    readonly property var providers: [
        {
            id: "claude-cli",
            name: "Claude Code",
            icon: "robot_2",
            color: "secondary",  // resolved below
        },
        {
            id: "codex",
            name: "Codex",
            icon: "code",
            color: "primary",
        },
        {
            id: "gemini-cli",
            name: "Gemini",
            icon: "neurology",
            color: "tertiary",
        },
        {
            id: "kimi-cli",
            name: "Kimi",
            icon: "auto_awesome",
            color: "outline",
        },
    ]

    function providerColor(modelId) {
        switch (modelId) {
        case "claude-cli":  return Appearance.colors.colSecondary;
        case "codex":       return Appearance.colors.colPrimary;
        case "gemini-cli":  return Appearance.colors.colTertiary;
        default:            return Appearance.colors.colOutlineVariant;
        }
    }

    function providerIcon(modelId) {
        switch (modelId) {
        case "claude-cli":  return "robot_2";
        case "codex":       return "code";
        case "gemini-cli":  return "neurology";
        default:            return "auto_awesome";
        }
    }

    function providerName(modelId) {
        switch (modelId) {
        case "claude-cli":  return "Claude";
        case "codex":       return "Codex";
        case "gemini-cli":  return "Gemini";
        default:            return "Kimi";
        }
    }

    // ── Session management ────────────────────────────────────────────────
    Component {
        id: sessionTemplate
        AgentSession {}
    }

    function idForSession() {
        return Date.now().toString(36) + Math.random().toString(36).substr(2, 8);
    }

    function newSession(modelId) {
        const s = sessionTemplate.createObject(root, {
            modelId: modelId,
            sessionId: idForSession(),
            title: providerName(modelId),
        });
        root.sessions = [...root.sessions, s];
        root.activeIdx = root.sessions.length - 1;
    }

    function closeSession(idx) {
        if (idx < 0 || idx >= root.sessions.length) return;
        root.sessions[idx].clearMessages();
        root.sessions[idx].destroy();
        const next = root.sessions.filter((_, i) => i !== idx);
        root.sessions = next;
        if (next.length === 0) {
            root.activeIdx = -1;
        } else {
            root.activeIdx = Math.max(0, Math.min(root.activeIdx, next.length - 1));
        }
    }

    // ── Layout ────────────────────────────────────────────────────────────
    ColumnLayout {
        anchors {
            fill: parent
            margins: root.padding
        }
        spacing: root.padding

        // ── Session tab strip + New agent button ──────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: tabRow.implicitHeight + 4
            visible: root.sessions.length > 0 || true  // always show toolbar

            RowLayout {
                id: tabRow
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }
                spacing: 4

                // Scrollable session chip strip
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: chipScrollView.implicitHeight

                    ScrollView {
                        id: chipScrollView
                        anchors.fill: parent
                        ScrollBar.horizontal.policy: ScrollBar.AsNeeded
                        ScrollBar.vertical.policy: ScrollBar.AlwaysOff
                        contentWidth: chipRow.implicitWidth
                        implicitHeight: chipRow.implicitHeight + 2
                        clip: true

                        Row {
                            id: chipRow
                            spacing: 4

                            Repeater {
                                model: root.sessions

                                delegate: Rectangle {
                                    required property var modelData
                                    required property int index

                                    readonly property var session: modelData
                                    readonly property bool isActive: root.activeIdx === index
                                    readonly property color provColor: root.providerColor(session?.modelId ?? "")

                                    radius: Appearance.rounding.full
                                    color: isActive
                                        ? Qt.rgba(provColor.r, provColor.g, provColor.b, 0.18)
                                        : Appearance.colors.colLayer1
                                    border.width: 1
                                    border.color: isActive
                                        ? Qt.rgba(provColor.r, provColor.g, provColor.b, 0.7)
                                        : Qt.rgba(Appearance.colors.colOutlineVariant.r,
                                                  Appearance.colors.colOutlineVariant.g,
                                                  Appearance.colors.colOutlineVariant.b, 0.45)
                                    implicitWidth: chipContents.implicitWidth + 14
                                    implicitHeight: chipContents.implicitHeight + 8

                                    Behavior on color {
                                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                                    }
                                    Behavior on border.color {
                                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                                    }

                                    // Click to activate
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.activeIdx = index
                                    }

                                    RowLayout {
                                        id: chipContents
                                        anchors.centerIn: parent
                                        spacing: 4

                                        // Working pulse dot
                                        Rectangle {
                                            Layout.alignment: Qt.AlignVCenter
                                            width: 7
                                            height: 7
                                            radius: 3.5
                                            color: session?.isWorking
                                                ? provColor
                                                : Qt.rgba(provColor.r, provColor.g, provColor.b, 0.5)

                                            SequentialAnimation on opacity {
                                                running: session?.isWorking ?? false
                                                loops: Animation.Infinite
                                                NumberAnimation { to: 0.3; duration: 600; easing.type: Easing.InOutSine }
                                                NumberAnimation { to: 1.0; duration: 600; easing.type: Easing.InOutSine }
                                            }
                                        }

                                        StyledText {
                                            text: session?.title ?? ""
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            color: isActive
                                                ? Appearance.colors.colOnLayer1
                                                : Appearance.colors.colSubtext
                                            maximumLineCount: 1
                                            elide: Text.ElideRight
                                            Layout.maximumWidth: 90
                                        }

                                        // Close × button
                                        Item {
                                            implicitWidth: 16
                                            implicitHeight: 16

                                            Rectangle {
                                                id: closeBg
                                                anchors.fill: parent
                                                radius: 8
                                                color: closeArea.containsMouse
                                                    ? Qt.rgba(Appearance.colors.colError.r,
                                                              Appearance.colors.colError.g,
                                                              Appearance.colors.colError.b, 0.18)
                                                    : "transparent"
                                                Behavior on color {
                                                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                                                }
                                            }

                                            StyledText {
                                                anchors.centerIn: parent
                                                text: "×"
                                                font.pixelSize: Appearance.font.pixelSize.small
                                                color: closeArea.containsMouse
                                                    ? Appearance.colors.colError
                                                    : Appearance.colors.colSubtext
                                                Behavior on color {
                                                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                                                }
                                            }

                                            MouseArea {
                                                id: closeArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.closeSession(index)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // New agent button
                RippleButton {
                    id: newAgentBtn
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: newAgentRow.implicitWidth + 14
                    implicitHeight: newAgentRow.implicitHeight + 8
                    buttonRadius: Appearance.rounding.full
                    colBackground: pickerPopup.visible
                        ? Appearance.colors.colPrimaryContainer
                        : Appearance.colors.colLayer1
                    colBackgroundHover: Appearance.colors.colLayer1Hover
                    colRipple: Appearance.colors.colLayer1Active
                    releaseAction: () => { pickerPopup.visible = !pickerPopup.visible }

                    contentItem: RowLayout {
                        id: newAgentRow
                        spacing: 4
                        anchors.centerIn: parent

                        MaterialSymbol {
                            text: "add"
                            iconSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            text: qsTr("New agent")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colOnLayer1
                        }
                    }
                }
            }
        }

        // ── Provider picker popup ─────────────────────────────────────────
        Rectangle {
            id: pickerPopup
            Layout.fillWidth: true
            visible: false
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1
            border.width: 1
            border.color: Qt.rgba(
                Appearance.colors.colOutlineVariant.r,
                Appearance.colors.colOutlineVariant.g,
                Appearance.colors.colOutlineVariant.b, 0.5)
            implicitHeight: pickerColumn.implicitHeight + 12

            StyledRectangularShadow {
                target: pickerPopup
                opacity: 0.3
            }

            Column {
                id: pickerColumn
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: 6
                }
                spacing: 3

                Repeater {
                    model: root.providers

                    delegate: RippleButton {
                        required property var modelData
                        readonly property var provider: modelData
                        readonly property color pColor: root.providerColor(provider.id)

                        implicitWidth: parent.width
                        implicitHeight: providerRow.implicitHeight + 12
                        buttonRadius: Appearance.rounding.small
                        colBackground: "transparent"
                        colBackgroundHover: Qt.rgba(pColor.r, pColor.g, pColor.b, 0.1)
                        colRipple: Qt.rgba(pColor.r, pColor.g, pColor.b, 0.18)
                        releaseAction: () => {
                            root.newSession(provider.id);
                            pickerPopup.visible = false;
                        }

                        contentItem: RowLayout {
                            id: providerRow
                            anchors {
                                left: parent.left
                                right: parent.right
                                verticalCenter: parent.verticalCenter
                                leftMargin: 8
                                rightMargin: 8
                            }
                            spacing: 10

                            Rectangle {
                                Layout.alignment: Qt.AlignVCenter
                                width: 30
                                height: 30
                                radius: 15
                                color: Qt.rgba(pColor.r, pColor.g, pColor.b, 0.14)

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: root.providerIcon(provider.id)
                                    iconSize: Appearance.font.pixelSize.normal
                                    color: pColor
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: provider.name
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnLayer1
                            }

                            MaterialSymbol {
                                text: "chevron_right"
                                iconSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                            }
                        }
                    }
                }
            }
        }

        // ── Empty state ───────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.sessions.length === 0
            spacing: 16

            Item { Layout.fillHeight: true }

            MaterialShapeWrappedMaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                text: "smart_toy"
                shape: MaterialShape.Shape.PixelCircle
                padding: 14
                iconSize: 52
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: qsTr("No agent sessions")
                font {
                    family: Appearance.font.family.title
                    pixelSize: Appearance.font.pixelSize.larger
                    variableAxes: Appearance.font.variableAxes.title
                }
                color: Appearance.m3colors.m3outline
                horizontalAlignment: Text.AlignHCenter
            }

            Rectangle {
                Layout.fillWidth: true
                color: Appearance.colors.colLayer2
                radius: Appearance.rounding.normal
                implicitHeight: hintCol.implicitHeight + 24

                ColumnLayout {
                    id: hintCol
                    anchors {
                        fill: parent
                        margins: 12
                    }
                    spacing: 8

                    StyledText {
                        text: qsTr("Quick start")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                    }

                    Repeater {
                        model: [
                            { icon: "robot_2",    text: qsTr("Claude Code — Anthropic's coding agent") },
                            { icon: "code",       text: qsTr("Codex — OpenAI coding agent via CLI") },
                            { icon: "neurology",  text: qsTr("Gemini — Google's multimodal agent") },
                        ]

                        delegate: RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 8

                            MaterialSymbol {
                                text: modelData.icon
                                iconSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: modelData.text
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colSubtext
                                wrapMode: Text.Wrap
                            }
                        }
                    }
                }
            }

            Item { Layout.fillHeight: true }
        }

        // ── Active session chat view ───────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.sessions.length > 0

            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: sessionViewLoader.width
                    height: sessionViewLoader.height
                    radius: Appearance.rounding.small
                }
            }

            Loader {
                id: sessionViewLoader
                anchors.fill: parent
                active: root.activeSession !== null

                sourceComponent: Component {
                    AgentSessionView {
                        session: root.activeSession
                    }
                }
            }
        }
    }

    // Close picker when clicking outside
    MouseArea {
        anchors.fill: parent
        z: -1
        enabled: pickerPopup.visible
        onClicked: pickerPopup.visible = false
    }
}
