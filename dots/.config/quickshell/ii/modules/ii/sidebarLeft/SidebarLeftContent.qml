import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Qt.labs.synchronizer

Item {
    id: root
    required property var scopeRoot
    property int sidebarPadding: 10
    readonly property int compactSidebarPadding: 6
    anchors.fill: parent
    property bool aiChatEnabled: Config.options.policies.ai !== 0
    property bool translatorEnabled: Config.options.sidebar.translator.enable
    property bool animeEnabled: Config.options.policies.weeb !== 0
    property bool animeCloset: Config.options.policies.weeb === 2
    // Agents tab is always first; finance index shifts by 1 when Intelligence is also present
    readonly property int financeTabIndex: root.aiChatEnabled ? 2 : 1
    readonly property bool agentsOverlayActive: GlobalStates.sidebarLeftOpen && GlobalStates.sidebarLeftTab === 0 && AgentWorkspace.sessionNames.length > 0
    property var tabButtonList: [
        {"icon": "smart_toy", "name": Translation.tr("Agents")},
        ...(root.aiChatEnabled ? [{"icon": "neurology", "name": Translation.tr("Intelligence")}] : []),
        {"icon": "finance", "name": Translation.tr("Finance")},
        ...(root.translatorEnabled ? [{"icon": "translate", "name": Translation.tr("Translator")}] : []),
        ...((root.animeEnabled && !root.animeCloset) ? [{"icon": "bookmark_heart", "name": Translation.tr("Anime")}] : [])
    ]
    property int tabCount: swipeView.count
    readonly property real desiredPanelHeight: {
        const currentPadding = agentsOverlayActive ? compactSidebarPadding : sidebarPadding;
        const toolbarHeight = toolbar.visible ? toolbar.implicitHeight : 0;
        const contentHeight = agentsOverlayActive
            ? Number(swipeView.currentItem?.desiredPanelHeight ?? 0)
            : 0;
        const gapCount = contentHeight > 0 && toolbarHeight > 0 ? 1 : 0;
        return currentPadding * 2 + toolbarHeight + contentHeight + gapCount * layoutColumn.spacing;
    }

    function focusActiveItem() {
        if (swipeView.currentItem)
            swipeView.currentItem.forceActiveFocus()
    }

    // Respond to external requests to switch to a specific tab (e.g. sidebarLeftOpenAgents)
    Connections {
        target: GlobalStates
        function onSidebarLeftTabChanged() {
            if (GlobalStates.sidebarLeftTab !== swipeView.currentIndex)
                tabBar.setCurrentIndex(GlobalStates.sidebarLeftTab);
        }
    }

    Keys.onPressed: (event) => {
        if (event.modifiers === Qt.ControlModifier) {
            if (event.key === Qt.Key_PageDown) {
                swipeView.incrementCurrentIndex()
                event.accepted = true;
            }
            else if (event.key === Qt.Key_PageUp) {
                swipeView.decrementCurrentIndex()
                event.accepted = true;
            }
        }
    }

    ColumnLayout {
        id: layoutColumn
        anchors {
            fill: parent
            margins: root.agentsOverlayActive ? compactSidebarPadding : sidebarPadding
        }
        spacing: root.agentsOverlayActive ? 0 : sidebarPadding

        Toolbar {
            id: toolbar
            visible: tabButtonList.length > 0
            Layout.alignment: Qt.AlignHCenter
            enableShadow: false
            ToolbarTabBar {
                id: tabBar
                Layout.alignment: Qt.AlignHCenter
                tabButtonList: root.tabButtonList
                currentIndex: swipeView.currentIndex
            }
        }

        Rectangle {
            visible: !root.agentsOverlayActive || Number(swipeView.currentItem?.desiredPanelHeight ?? 0) > 0
            Layout.fillWidth: true
            Layout.fillHeight: !root.agentsOverlayActive
            Layout.preferredHeight: root.agentsOverlayActive
                ? Number(swipeView.currentItem?.desiredPanelHeight ?? 0)
                : -1
            implicitWidth: swipeView.implicitWidth
            implicitHeight: root.agentsOverlayActive
                ? Number(swipeView.currentItem?.desiredPanelHeight ?? swipeView.implicitHeight)
                : swipeView.implicitHeight
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1

            SwipeView { // Content pages
                id: swipeView
                anchors.fill: parent
                spacing: 10
                currentIndex: tabBar.currentIndex

                onCurrentIndexChanged: {
                    GlobalStates.sidebarLeftTab = currentIndex;
                }

                clip: true
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: swipeView.width
                        height: swipeView.height
                        radius: Appearance.rounding.small
                    }
                }

                contentChildren: [
                    agents.createObject(),
                    ...(root.aiChatEnabled ? [aiChat.createObject()] : []),
                    finance.createObject(),
                    ...(root.translatorEnabled ? [translator.createObject()] : []),
                    ...((root.tabButtonList.length === 0 || (!root.aiChatEnabled && !root.translatorEnabled && root.animeCloset)) ? [placeholder.createObject()] : []),
                    ...(root.animeEnabled ? [anime.createObject()] : []),
                ]
            }
        }

        Component {
            id: agents
            Agents {}
        }
        Component {
            id: aiChat
            AiChat {}
        }
        Component {
            id: finance
            Finance {
                isActive: swipeView.currentIndex === root.financeTabIndex
            }
        }
        Component {
            id: translator
            Translator {}
        }
        Component {
            id: anime
            Anime {}
        }
        Component {
            id: placeholder
            Item {
                StyledText {
                    anchors.centerIn: parent
                    text: root.animeCloset ? Translation.tr("Nothing") : Translation.tr("Enjoy your empty sidebar...")
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }
}
