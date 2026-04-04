import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

Scope {
    id: root

    readonly property real statusCardAllowance: 520

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: petWindow
            required property var modelData

            property var screenSegment: DesktopPet.segmentForScreen(modelData?.name ?? "")

            screen: modelData
            visible: DesktopPet.enabled
                && !GlobalStates.screenLocked
                && !!screenSegment

            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            implicitHeight: lane.implicitHeight
            WlrLayershell.namespace: "quickshell:desktopPet"
            WlrLayershell.layer: WlrLayer.Overlay

            anchors {
                left: true
                right: true
                bottom: true
            }

            mask: Region {
                item: petWrapper
            }

            Item {
                id: lane
                anchors {
                    fill: parent
                    leftMargin: 10
                    rightMargin: 10
                    bottomMargin: Config.options.overlay.desktopPet.bottomMargin
                }
                clip: true
                implicitHeight: DesktopPet.petSize + root.statusCardAllowance

                Item {
                    id: petWrapper
                    y: lane.height - height
                    x: DesktopPet.positionForScreen(modelData?.name ?? "") - 10
                    visible: DesktopPet.intersectsScreen(modelData?.name ?? "")
                    implicitWidth: DesktopPet.petRenderWidth
                    implicitHeight: DesktopPet.petSize + root.statusCardAllowance - 24

                    Item {
                        id: emoteBubble
                        anchors.horizontalCenter: petBody.horizontalCenter
                        anchors.bottom: petBody.top
                        anchors.bottomMargin: 4
                        visible: opacity > 0 && DesktopPet.primaryScreenName === (modelData?.name ?? "")
                        opacity: DesktopPet.emote.length > 0 ? 1 : 0
                        implicitWidth: emoteText.implicitWidth + 10
                        implicitHeight: emoteText.implicitHeight + 6

                        Rectangle {
                            anchors.fill: parent
                            radius: Appearance.rounding.full
                            color: Appearance.colors.colLayer0
                            border.color: Appearance.colors.colOutlineVariant
                            border.width: 1
                        }

                        StyledText {
                            id: emoteText
                            anchors.centerIn: parent
                            text: DesktopPet.emote
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer0
                        }
                    }

                    MouseArea {
                        id: petMouseArea
                        anchors.fill: petBody
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        property real pressX: 0
                        property real pressY: 0
                        property bool dragStarted: false
                        property real dragYOffset: 0
                        readonly property real dragThreshold: 10

                        onPressed: event => {
                            pressX = mouseX;
                            pressY = mouseY;
                            dragYOffset = 0;
                            dragStarted = false;
                        }

                        onPositionChanged: event => {
                            if (!pressed)
                                return;
                            const travel = Math.hypot(mouseX - pressX, mouseY - pressY);
                            if (!dragStarted && travel >= dragThreshold) {
                                dragStarted = true;
                                DesktopPet.beginDrag(modelData?.name ?? "");
                            }
                            if (dragStarted) {
                                dragYOffset = mouseY - pressY;
                                DesktopPet.dragTo(modelData?.name ?? "", petWrapper.x + mouseX);
                            }
                        }

                        onReleased: event => {
                            if (dragStarted)
                                DesktopPet.endDrag(modelData?.name ?? "", petWrapper.x + mouseX);
                            else
                                DesktopPet.pet();
                            dragStarted = false;
                            dragYOffset = 0;
                        }

                        onCanceled: {
                            if (dragStarted)
                                DesktopPet.endDrag(modelData?.name ?? "", petWrapper.x + mouseX);
                            dragStarted = false;
                            dragYOffset = 0;
                        }
                    }

                    Item {
                        id: statusCardWrapper
                        anchors.bottom: emoteBubble.top
                        anchors.bottomMargin: 8
                        anchors.horizontalCenter: petBody.horizontalCenter
                        visible: opacity > 0 && DesktopPet.primaryScreenName === (modelData?.name ?? "")
                        opacity: DesktopPet.statusOpen ? 1 : 0
                        implicitWidth: statusCard.implicitWidth
                        implicitHeight: statusCard.implicitHeight

                        Behavior on opacity {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }

                        StyledRectangularShadow {
                            target: statusCard
                            opacity: statusCardWrapper.opacity
                        }

                        Rectangle {
                            id: statusCard
                            color: Appearance.colors.colLayer0
                            border.color: Appearance.colors.colOutlineVariant
                            border.width: 1
                            radius: Appearance.rounding.normal
                            implicitWidth: 220
                            implicitHeight: statusColumn.implicitHeight + 12 * 2

                            ColumnLayout {
                                id: statusColumn
                                anchors {
                                    fill: parent
                                    margins: 12
                                }
                                spacing: 8

                                RowLayout {
                                    Layout.fillWidth: true

                                    MaterialShapeWrappedMaterialSymbol {
                                        text: "pets"
                                        shape: MaterialShape.Shape.PixelCircle
                                        iconSize: 18
                                        padding: 6
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0

                                        StyledText {
                                            text: DesktopPet.petName
                                            font {
                                                family: Appearance.font.family.title
                                                pixelSize: Appearance.font.pixelSize.normal
                                                variableAxes: Appearance.font.variableAxes.title
                                            }
                                            color: Appearance.colors.colOnLayer0
                                        }
                                        StyledText {
                                            text: Translation.tr("Mood · %1").arg(DesktopPet.mood)
                                            font.pixelSize: Appearance.font.pixelSize.smallie
                                            color: Appearance.colors.colSubtext
                                        }
                                        StyledText {
                                            text: Translation.tr("Behavior · %1").arg(DesktopPet.behavior)
                                            font.pixelSize: Appearance.font.pixelSize.smallie
                                            color: Appearance.colors.colSubtext
                                        }
                                    }
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: DesktopPet.thought
                                    wrapMode: Text.Wrap
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colOnLayer0
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    radius: Appearance.rounding.normal
                                    color: Appearance.colors.colLayer1
                                    border.color: Appearance.colors.colOutlineVariant
                                    border.width: 1
                                    implicitHeight: needColumn.implicitHeight + 10

                                    ColumnLayout {
                                        id: needColumn
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        spacing: 2

                                        StyledText {
                                            text: Translation.tr("Wants · %1").arg(DesktopPet.needLabel)
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            color: Appearance.colors.colOnLayer0
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: DesktopPet.needHint
                                            wrapMode: Text.Wrap
                                            font.pixelSize: Appearance.font.pixelSize.smallie
                                            color: Appearance.colors.colSubtext
                                        }
                                    }
                                }

                                GridLayout {
                                    Layout.fillWidth: true
                                    columns: 2
                                    columnSpacing: 10
                                    rowSpacing: 6

                                    StyledText {
                                        text: Translation.tr("Scene")
                                        font.pixelSize: Appearance.font.pixelSize.smallie
                                        color: Appearance.colors.colSubtext
                                    }
                                    StyledText {
                                        Layout.alignment: Qt.AlignRight
                                        text: DesktopPet.appCategory
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: Appearance.colors.colOnLayer0
                                    }

                                    StyledText {
                                        text: Translation.tr("CPU")
                                        font.pixelSize: Appearance.font.pixelSize.smallie
                                        color: Appearance.colors.colSubtext
                                    }
                                    StyledText {
                                        Layout.alignment: Qt.AlignRight
                                        text: `${Math.round(DesktopPet.cpuUsagePercent)}%`
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: Appearance.colors.colOnLayer0
                                    }

                                    StyledText {
                                        text: Translation.tr("Battery")
                                        font.pixelSize: Appearance.font.pixelSize.smallie
                                        color: Appearance.colors.colSubtext
                                    }
                                    StyledText {
                                        Layout.alignment: Qt.AlignRight
                                        text: Battery.available ? `${Math.round(Battery.percentage * 100)}%` : Translation.tr("Desktop")
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: Appearance.colors.colOnLayer0
                                    }

                                    StyledText {
                                        text: Translation.tr("Music")
                                        font.pixelSize: Appearance.font.pixelSize.smallie
                                        color: Appearance.colors.colSubtext
                                    }
                                    StyledText {
                                        Layout.alignment: Qt.AlignRight
                                        text: DesktopPet.musicPlaying ? Translation.tr("Playing") : Translation.tr("Quiet")
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: Appearance.colors.colOnLayer0
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Repeater {
                                        model: [
                                            {
                                                label: Translation.tr("Energy"),
                                                value: DesktopPet.energy,
                                                color: DesktopPet.energy < 28
                                                    ? Appearance.colors.colError
                                                    : Appearance.colors.colPrimary
                                            },
                                            {
                                                label: Translation.tr("Hunger"),
                                                value: DesktopPet.hunger,
                                                color: DesktopPet.hunger > 72
                                                    ? Appearance.colors.colError
                                                    : Appearance.colors.colSecondary
                                            },
                                            {
                                                label: Translation.tr("Tiredness"),
                                                value: DesktopPet.tiredness,
                                                color: DesktopPet.tiredness > 72
                                                    ? Appearance.colors.colError
                                                    : Appearance.m3colors.m3tertiary
                                            },
                                            {
                                                label: Translation.tr("Fun"),
                                                value: DesktopPet.fun,
                                                color: DesktopPet.fun < 30
                                                    ? Appearance.colors.colError
                                                    : Appearance.colors.colPrimary
                                            }
                                        ]

                                        delegate: ColumnLayout {
                                            required property var modelData

                                            Layout.fillWidth: true
                                            spacing: 2

                                            RowLayout {
                                                Layout.fillWidth: true

                                                StyledText {
                                                    Layout.fillWidth: true
                                                    text: modelData.label
                                                    font.pixelSize: Appearance.font.pixelSize.smallie
                                                    color: Appearance.colors.colSubtext
                                                }

                                                StyledText {
                                                    text: `${Math.round(modelData.value)}`
                                                    font.pixelSize: Appearance.font.pixelSize.smallie
                                                    color: Appearance.colors.colOnLayer0
                                                }
                                            }

                                            Rectangle {
                                                Layout.fillWidth: true
                                                implicitHeight: 6
                                                radius: 3
                                                color: Appearance.colors.colLayer2

                                                Rectangle {
                                                    width: parent.width * Math.max(0.06, modelData.value / 100)
                                                    height: parent.height
                                                    radius: parent.radius
                                                    color: modelData.color
                                                }
                                            }
                                        }
                                    }
                                }

                                Flow {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Repeater {
                                        model: [
                                            {
                                                label: Translation.tr("Feed"),
                                                actionId: "feed"
                                            },
                                            {
                                                label: Translation.tr("Nap"),
                                                actionId: "nap"
                                            },
                                            {
                                                label: Translation.tr("Wake"),
                                                actionId: "wake"
                                            },
                                            {
                                                label: Translation.tr("Play"),
                                                actionId: "play"
                                            }
                                        ]

                                        delegate: Rectangle {
                                            required property var modelData

                                            width: actionText.implicitWidth + 16
                                            height: actionText.implicitHeight + 10
                                            radius: Appearance.rounding.full
                                            color: actionMouseArea.pressed
                                                ? Appearance.colors.colSecondaryContainer
                                                : Appearance.colors.colLayer1
                                            border.color: Appearance.colors.colOutlineVariant
                                            border.width: 1

                                            StyledText {
                                                id: actionText
                                                anchors.centerIn: parent
                                                text: modelData.label
                                                font.pixelSize: Appearance.font.pixelSize.smallie
                                                color: Appearance.colors.colOnLayer0
                                            }

                                            MouseArea {
                                                id: actionMouseArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    switch (modelData.actionId) {
                                                    case "feed":
                                                        DesktopPet.feed();
                                                        break;
                                                    case "nap":
                                                        DesktopPet.nap();
                                                        break;
                                                    case "wake":
                                                        DesktopPet.wakeUp();
                                                        break;
                                                    case "play":
                                                        DesktopPet.playWith();
                                                        break;
                                                    default:
                                                        break;
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Item {
                        id: toyWrapper
                        visible: DesktopPet.toyActive && DesktopPet.intersectsWorldObject(modelData?.name ?? "", DesktopPet.toyWorldX, DesktopPet.toyDiameter)
                        width: DesktopPet.toyDiameter
                        height: DesktopPet.toyDiameter
                        x: DesktopPet.positionForWorldX(modelData?.name ?? "", DesktopPet.toyWorldX) - 10
                        y: lane.height - height - DesktopPet.toyHeight

                        property real squash: DesktopPet.toyDragging ? 1.08 : (DesktopPet.toyHeight === 0 ? 1.0 : 0.96)

                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width
                            height: parent.height * 0.18
                            radius: height / 2
                            color: "#240f10"
                            opacity: DesktopPet.toyDragging ? 0.08 : 0.18
                            y: DesktopPet.toyDragging ? parent.height * 0.8 : parent.height * 0.92
                            scale: DesktopPet.toyDragging ? 0.5 : 0.72
                        }

                        Rectangle {
                            id: toyBall
                            anchors.centerIn: parent
                            width: parent.width
                            height: parent.height
                            radius: width / 2
                            color: "#d94c3a"
                            border.color: "#f7d2be"
                            border.width: 2
                            scale: toyWrapper.squash

                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width * 0.32
                                height: width
                                radius: width / 2
                                color: "#f7d2be"
                            }
                        }

                        MouseArea {
                            id: toyMouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.OpenHandCursor
                            enabled: DesktopPet.toyActive
                            property real pressX: 0
                            property real pressY: 0
                            property real lastX: 0
                            property real lastY: 0
                            property bool dragStarted: false
                            readonly property real dragThreshold: 8

                            onPressed: event => {
                                pressX = mouseX;
                                pressY = mouseY;
                                lastX = mouseX;
                                lastY = mouseY;
                                dragStarted = false;
                            }

                            onPositionChanged: event => {
                                if (!pressed)
                                    return;
                                const travel = Math.hypot(mouseX - pressX, mouseY - pressY);
                                if (!dragStarted && travel >= dragThreshold) {
                                    dragStarted = true;
                                    DesktopPet.beginToyDrag(modelData?.name ?? "", toyWrapper.x + mouseX, Math.max(0, pressY - mouseY));
                                }
                                if (dragStarted) {
                                    DesktopPet.updateToyDrag(modelData?.name ?? "", toyWrapper.x + mouseX, Math.max(0, pressY - mouseY));
                                    lastX = mouseX;
                                    lastY = mouseY;
                                }
                            }

                            onReleased: event => {
                                if (dragStarted) {
                                    const deltaX = mouseX - lastX;
                                    const deltaY = lastY - mouseY;
                                    DesktopPet.launchToy(
                                        modelData?.name ?? "",
                                        toyWrapper.x + mouseX,
                                        Math.max(0, pressY - mouseY),
                                        deltaX * 34,
                                        Math.max(180, (pressY - mouseY) * 7 + deltaY * 26)
                                    );
                                }
                                dragStarted = false;
                            }

                            onCanceled: {
                                if (dragStarted)
                                    DesktopPet.launchToy(modelData?.name ?? "", toyWrapper.x + mouseX, Math.max(0, pressY - mouseY), 0, 220);
                                dragStarted = false;
                            }
                        }
                    }

                    Item {
                        id: petBody
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        implicitWidth: DesktopPet.petSize * 1.25
                        implicitHeight: DesktopPet.petSize * 1.25

                        readonly property real draggingPhase: Date.now() / 170.0
                        readonly property real dragPullLift: {
                            const pulledUp = Math.max(0, -petMouseArea.dragYOffset);
                            return Math.min(Math.max(120, DesktopPet.petSize * 1.05), pulledUp * 1.05);
                        }
                        readonly property real dragLift: DesktopPet.dragging ? -(Math.max(30, DesktopPet.petSize * 0.28) + dragPullLift) : 0
                        readonly property real dragSway: DesktopPet.dragging ? Math.sin(draggingPhase) * 4.5 : 0
                        readonly property real dragTilt: DesktopPet.dragging ? Math.sin(draggingPhase * 0.85) * 7 : 0
                        readonly property real landingProgress: DesktopPet.landingMsRemaining > 0 ? (DesktopPet.landingMsRemaining / 340.0) : 0
                        readonly property real landingBounce: DesktopPet.landingMsRemaining > 0
                            ? (Math.sin((1 - landingProgress) * Math.PI) * Math.max(6, DesktopPet.petSize * 0.06))
                            : 0
                        readonly property real landingSquash: DesktopPet.landingMsRemaining > 0
                            ? (1 + (Math.sin((1 - landingProgress) * Math.PI) * 0.12))
                            : 1
                        property real bounceOffset: DesktopPet.dragging
                            ? (dragLift + dragSway)
                            : (DesktopPet.animationState === "walk"
                                ? (DesktopPet.walkPhase % 2 === 0 ? 0 : -4)
                                : (DesktopPet.animationState === "celebrate" ? jumpOffset : landingBounce))
                        readonly property real jumpProgress: {
                            const frameCount = currentAnimation?.frames?.length ?? 0;
                            if (currentAnimationName !== "Jump" || frameCount <= 1)
                                return 0;
                            return frameIndex / (frameCount - 1);
                        }
                        readonly property real jumpOffset: {
                            if (currentAnimationName !== "Jump")
                                return -6;
                            const t = jumpProgress;
                            return -(4 * 26 * t * (1 - t));
                        }
                        readonly property int frameSize: 48
                        readonly property string spriteBasePath: Qt.resolvedUrl("../../../assets/desktopPet/pixelDog/Split_Animations")
                        readonly property string directionName: "RightSide"
                        readonly property var animationDefinitions: ({
                            "Idle": {
                                file: `${spriteBasePath}/${directionName}-Idle-Sheet.png`,
                                frames: [[0, 0], [1, 0], [2, 0], [3, 0], [0, 1], [1, 1], [2, 1], [3, 1], [4, 1], [5, 1], [6, 1], [7, 1]],
                                interval: 120
                            },
                            "Walk": {
                                file: `${spriteBasePath}/${directionName}-Walk-Sheet.png`,
                                frames: [[0, 0], [1, 0], [2, 0], [3, 0]],
                                interval: 95
                            },
                            "Run": {
                                file: `${spriteBasePath}/${directionName}-Run-Sheet.png`,
                                frames: [[0, 0], [1, 0], [2, 0], [3, 0], [4, 0], [5, 0], [6, 0], [7, 0]],
                                interval: 70
                            },
                            "Sniff": {
                                file: `${spriteBasePath}/${directionName}-Sniff-Sheet.png`,
                                frames: [[0, 0], [1, 0], [2, 0], [3, 0]],
                                interval: 130
                            },
                            "Lick": {
                                file: `${spriteBasePath}/${directionName}-Lick-Sheet.png`,
                                frames: [[0, 0], [1, 0], [2, 0], [3, 0]],
                                interval: 90
                            },
                            "Bark": {
                                file: `${spriteBasePath}/${directionName}-Bark-Sheet.png`,
                                frames: [[0, 0], [1, 0], [2, 0], [3, 0], [4, 0], [5, 0], [6, 0], [7, 0], [0, 1], [1, 1], [2, 1], [3, 1], [4, 1]],
                                interval: 85
                            },
                            "Sit": {
                                file: `${spriteBasePath}/${directionName}-Sit-Sheet.png`,
                                frames: [[0, 4], [1, 4], [2, 4], [3, 4], [4, 4], [5, 4], [6, 4], [7, 4], [8, 4], [9, 4], [10, 4], [11, 4], [12, 4], [13, 4], [14, 4]],
                                interval: 150,
                                mode: "loop"
                            },
                            "Laydown": {
                                file: `${spriteBasePath}/${directionName}-Die-Sheet.png`,
                                frames: [[0, 0], [1, 0], [2, 0]],
                                interval: 140,
                                mode: "once"
                            },
                            "Jump": {
                                file: `${spriteBasePath}/${directionName}-Jump-Sheet.png`,
                                frames: [[0, 0], [1, 0], [2, 0], [0, 1], [1, 1], [2, 1], [3, 1], [0, 2], [1, 2], [2, 2]],
                                interval: 85,
                                mode: "once"
                            },
                            "JumpHold": {
                                file: `${spriteBasePath}/${directionName}-Jump-Sheet.png`,
                                frames: [[2, 0], [0, 1], [1, 1], [2, 1], [3, 1], [2, 1], [1, 1], [0, 1]],
                                interval: 95,
                                mode: "loop"
                            }
                        })
                        readonly property string currentAnimationName: {
                            switch (DesktopPet.behavior) {
                            case "react":
                                return "Lick";
                            case "alert_react":
                                return "Bark";
                            case "rest":
                                if (DesktopPet.dragging)
                                    return "JumpHold";
                                return "Idle";
                            case "play":
                                return "Jump";
                            case "roam_fast":
                                return "Run";
                            case "roam":
                            case "approach_focus":
                                return "Walk";
                            case "inspect":
                                return "Sniff";
                            case "rest_lay":
                                return "Laydown";
                            case "rest_sit":
                                return "Sit";
                            default:
                                return "Idle";
                            }
                        }
                        readonly property var currentAnimation: animationDefinitions[currentAnimationName] || animationDefinitions["Idle"]
                        property int frameIndex: 0
                        y: bounceOffset

                        onCurrentAnimationNameChanged: frameIndex = 0
                        onDirectionNameChanged: frameIndex = 0

                        Timer {
                            id: spriteTimer
                            interval: petBody.currentAnimation?.interval ?? 120
                            running: true
                            repeat: true
                            onTriggered: {
                                const frameCount = petBody.currentAnimation?.frames?.length ?? 0;
                                if (frameCount <= 0)
                                    return;
                                if ((petBody.currentAnimation?.mode ?? "loop") === "once") {
                                    petBody.frameIndex = Math.min(frameCount - 1, petBody.frameIndex + 1);
                                } else {
                                    petBody.frameIndex = (petBody.frameIndex + 1) % frameCount;
                                }
                            }
                        }

                        Rectangle {
                            anchors.centerIn: spriteImage
                            width: spriteImage.width * 0.6
                            height: spriteImage.height * 0.12
                            radius: height / 2
                            color: "#240f10"
                            opacity: DesktopPet.dragging ? (DesktopPet.shadowOpacity * 0.5) : DesktopPet.shadowOpacity
                            y: spriteImage.y + spriteImage.height * 0.41 + (DesktopPet.dragging ? 16 : 0)
                            scale: DesktopPet.dragging
                                ? 0.58
                                : (DesktopPet.behavior === "play" ? 0.72 : (DesktopPet.animationState === "walk" ? 0.92 : 0.96))
                        }

                        Image {
                            id: spriteImage
                            anchors.centerIn: parent
                            width: parent.width
                            height: parent.height
                            source: petBody.currentAnimation?.file ?? ""
                            fillMode: Image.PreserveAspectFit
                            sourceClipRect: {
                                const frames = petBody.currentAnimation?.frames ?? [];
                                const safeIndex = Math.min(petBody.frameIndex, Math.max(0, frames.length - 1));
                                const frame = frames[safeIndex] ?? [0, 0];
                                return Qt.rect(frame[0] * petBody.frameSize, frame[1] * petBody.frameSize, petBody.frameSize, petBody.frameSize);
                            }
                            smooth: false
                            mipmap: false
                            transform: [
                                Rotation {
                                    origin.x: spriteImage.width / 2
                                    origin.y: spriteImage.height / 2
                                    angle: petBody.dragTilt
                                },
                                Scale {
                                    origin.x: spriteImage.width / 2
                                    origin.y: spriteImage.height
                                    xScale: (DesktopPet.facingRight ? 1 : -1) * (DesktopPet.dragging ? 0.96 : 1)
                                    yScale: DesktopPet.dragging ? 1.04 : petBody.landingSquash
                                }
                            ]
                        }
                    }
                }
            }
        }
    }
}
