pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.modules.common

Singleton {
    id: root

    readonly property bool enabled: Config.options.overlay.desktopPet.enable
    readonly property real scale: Config.options.overlay.desktopPet.scale
    readonly property real speedMultiplier: Config.options.overlay.desktopPet.speed
    readonly property real activityMultiplier: Config.options.overlay.desktopPet.activity
    readonly property real followBias: Config.options.overlay.desktopPet.followBias
    readonly property bool reactionsEnabled: Config.options.overlay.desktopPet.reactions
    readonly property real shadowOpacity: Config.options.overlay.desktopPet.shadowOpacity
    readonly property string multiMonitorMode: Config.options.overlay.desktopPet.multiMonitorMode
    readonly property string petName: "Pixel Pup"

    property string mood: "idle"
    property string behavior: "roam"
    property string animationState: "idle"
    property real energy: 72
    property real hunger: 18
    property real tiredness: 24
    property real fun: 62
    property int direction: 1
    readonly property int visualDirection: {
        if (turnMsRemaining > 0)
            return pendingDirection;
        if (Math.abs(targetVelocity) > 0.5)
            return targetVelocity >= 0 ? 1 : -1;
        return direction >= 0 ? 1 : -1;
    }
    readonly property bool facingRight: visualDirection >= 0
    property real worldX: worldLeft
    property real targetWorldX: worldLeft
    property real velocity: 0
    property real targetVelocity: 0
    property int behaviorMsRemaining: 1800
    property int reactionMsRemaining: 0
    property int turnMsRemaining: 0
    property int landingMsRemaining: 0
    property int pendingDirection: 1
    property int restMsAccumulated: 0
    property bool statusOpen: false
    property bool dragging: false
    property string draggingScreenName: ""
    property bool toyActive: false
    property bool toyDragging: false
    property bool toyAwaitingThrow: false
    property string toyScreenName: ""
    property real toyWorldX: worldLeft
    property real toyHeight: 0
    property real toyVelocityX: 0
    property real toyVelocityY: 0
    property string activeAppId: ToplevelManager.activeToplevel?.appId ?? ""
    property string lastAppCategory: appCategory
    property bool lastMusicPlaying: musicPlaying
    property string lastFocusedAddress: activeClient?.address ?? ""
    property int focusRetargetCooldownMs: 0
    property int walkPhase: 0
    property real walkPhaseAccumulator: 0
    property string emote: ""
    property string thought: ""
    property string targetKind: "focus_zone"
    property real tailSwing: 0
    property real headTilt: 0
    property bool blinking: false
    property int blinkMsRemaining: 0
    property int nextBlinkMs: 1800
    readonly property real petBaseSize: 84
    readonly property var activeClient: HyprlandData.clientForToplevel(ToplevelManager.activeToplevel)
    readonly property real activeClientCenterX: activeClient ? ((activeClient.at?.[0] ?? 0) + (activeClient.size?.[0] ?? 0) / 2) : -1

    readonly property real cpuUsagePercent: ResourceUsage.cpuUsage * 100
    readonly property bool musicPlaying: MprisController.isPlaying
    readonly property bool batteryLow: Battery.available && Battery.isLowAndNotCharging
    readonly property bool batteryCritical: Battery.available && Battery.isCriticalAndNotCharging
    readonly property string appCategory: {
        const app = activeAppId.toLowerCase();
        if (app.length === 0)
            return "idle";
        if (["code", "codium", "zed", "nvim", "emacs"].some(name => app.includes(name)))
            return "editor";
        if (["kitty", "ghostty", "wezterm", "foot", "alacritty"].some(name => app.includes(name)))
            return "terminal";
        if (["firefox", "chromium", "zen", "brave", "librewolf"].some(name => app.includes(name)))
            return "browser";
        if (["steam", "heroic", "lutris"].some(name => app.includes(name)))
            return "game";
        if (["spotify", "youtube-music", "mpv", "vlc"].some(name => app.includes(name)))
            return "media";
        return "other";
    }
    readonly property int hourOfDay: Number(Qt.formatDateTime(new Date(), "H"))
    readonly property string needLabel: {
        if (hunger >= 72)
            return "Feed";
        if (tiredness >= 72 || energy <= 28)
            return "Nap";
        if (fun <= 34)
            return "Play";
        return "Pet";
    }
    readonly property string needHint: {
        switch (needLabel) {
        case "Feed":
            return "A snack would help right now.";
        case "Nap":
            return "This pup needs a proper rest.";
        case "Play":
            return "Spawn the ball, then drag and throw it.";
        default:
            return "A little attention goes a long way.";
        }
    }

    readonly property var monitorSegments: {
        const monitors = (HyprlandData.monitors ?? [])
            .filter(monitor => !monitor.disabled)
            .slice()
            .sort((left, right) => (left.x ?? 0) - (right.x ?? 0));
        return monitors.map((monitor, index) => ({
            "name": monitor.name,
            "left": monitor.x ?? 0,
            "right": (monitor.x ?? 0) + (monitor.width ?? 0),
            "width": monitor.width ?? 0,
            "height": monitor.height ?? 0,
            "index": index,
        }));
    }
    readonly property real worldLeft: monitorSegments.length > 0 ? monitorSegments[0].left : 0
    readonly property real worldRight: monitorSegments.length > 0 ? monitorSegments[monitorSegments.length - 1].right : petRenderWidth
    readonly property var currentSegment: segmentForCenter(worldX + petRenderWidth / 2)
    readonly property string primaryScreenName: currentSegment?.name ?? monitorSegments[0]?.name ?? ""
    readonly property real monitorScaleFactor: {
        const h = currentSegment?.height ?? 1080;
        const w = currentSegment?.width ?? 1920;
        const heightFactor = Math.max(1.0, Math.min(1.12, 1.0 + ((h - 1080) / 1080) * 0.22));
        const widthFactor = Math.max(1.0, Math.min(1.1, 1.0 + ((w - 1920) / 1920) * 0.16));
        return Math.min(1.2, Math.max(heightFactor, widthFactor));
    }
    readonly property real petSize: petBaseSize * scale * monitorScaleFactor
    readonly property real petRenderWidth: petSize * 1.25
    readonly property real toyDiameter: Math.max(18, petSize * 0.24)

    onMonitorSegmentsChanged: {
        if (worldX === 0)
            worldX = worldLeft + 160;
        clampWorldX();
        targetWorldX = clampTarget(targetWorldX);
    }

    Component.onCompleted: {
        worldX = worldLeft + 160;
        clampWorldX();
        targetWorldX = worldX;
    }

    function toggleEnabled() {
        Config.options.overlay.desktopPet.enable = !Config.options.overlay.desktopPet.enable;
        if (!Config.options.overlay.desktopPet.enable)
            statusOpen = false;
    }

    function randomBetween(minimum, maximum) {
        return minimum + Math.floor(Math.random() * (maximum - minimum + 1));
    }

    function clampVital(value) {
        return Math.max(0, Math.min(100, value));
    }

    function clampTarget(x) {
        const maxX = Math.max(worldLeft, worldRight - petRenderWidth);
        return Math.max(worldLeft, Math.min(maxX, x));
    }

    function clampWorldX() {
        worldX = clampTarget(worldX);
    }

    function segmentForScreen(screenName) {
        return monitorSegments.find(segment => segment.name === screenName) ?? null;
    }

    function segmentForCenter(centerX) {
        return monitorSegments.find(segment => centerX >= segment.left && centerX < segment.right)
            ?? monitorSegments[0]
            ?? null;
    }

    function intersectsScreen(screenName) {
        const segment = segmentForScreen(screenName);
        return !!segment && (worldX + petRenderWidth > segment.left) && (worldX < segment.right);
    }

    function positionForScreen(screenName) {
        const segment = segmentForScreen(screenName);
        return segment ? (worldX - segment.left) : 0;
    }

    function positionForWorldX(screenName, x) {
        const segment = segmentForScreen(screenName);
        return segment ? (x - segment.left) : 0;
    }

    function intersectsWorldObject(screenName, x, width) {
        const segment = segmentForScreen(screenName);
        return !!segment && (x + width > segment.left) && (x < segment.right);
    }

    function focusTargetForClient() {
        if (!activeClient)
            return clampTarget(worldLeft + (worldRight - worldLeft - petRenderWidth) / 2);
        return clampTarget(activeClientCenterX - petRenderWidth / 2);
    }

    function chooseFocusZoneTarget() {
        const center = activeClient ? activeClientCenterX : (worldLeft + (worldRight - worldLeft) / 2);
        const spread = Math.max(120, (currentSegment?.width ?? 800) * 0.12);
        targetWorldX = clampTarget(center - petRenderWidth / 2 + (Math.random() * 2 - 1) * spread);
        targetKind = "focus_zone";
    }

    function chooseMonitorRoamTarget() {
        const segment = currentSegment ?? monitorSegments[0];
        if (!segment) {
            chooseWorldRoamTarget();
            return;
        }
        const left = segment.left;
        const right = Math.max(left, segment.right - petRenderWidth);
        targetWorldX = clampTarget(left + Math.random() * Math.max(1, right - left));
        targetKind = "monitor_roam_zone";
    }

    function chooseWorldRoamTarget() {
        const maxX = Math.max(worldLeft, worldRight - petRenderWidth);
        targetWorldX = worldLeft + Math.random() * Math.max(1, maxX - worldLeft);
        targetKind = "world_roam_zone";
    }

    function choosePassiveTarget() {
        const roll = Math.random();
        if (activeClient && roll < followBias) {
            chooseFocusZoneTarget();
            return;
        }
        if (roll < (followBias + 0.25)) {
            chooseMonitorRoamTarget();
            return;
        }
        chooseWorldRoamTarget();
    }

    function settleRadius() {
        return targetKind === "focus_zone" ? 52 : 34;
    }

    function beginDrag(screenName) {
        dragging = true;
        draggingScreenName = screenName;
        velocity = 0;
        targetVelocity = 0;
        turnMsRemaining = 0;
        landingMsRemaining = 0;
        reactionMsRemaining = 0;
        targetKind = "manual_drop";
        setBehavior("rest", 999999);
        emote = "!";
        thought = "Up we go.";
        openStatus();
    }

    function dragTo(screenName, localX) {
        const segment = segmentForScreen(screenName);
        if (!segment)
            return;
        draggingScreenName = screenName;
        worldX = clampTarget(segment.left + localX - petRenderWidth / 2);
        targetWorldX = worldX;
        velocity = 0;
        targetVelocity = 0;
    }

    function endDrag(screenName, localX) {
        dragTo(screenName, localX);
        dragging = false;
        draggingScreenName = "";
        landingMsRemaining = 340;
        emote = "✦";
        thought = "A new cozy spot.";
        if (Math.random() < 0.6)
            setBehavior("inspect", randomBetween(900, 1500));
        else
            setBehavior("rest_sit", randomBetween(2400, 4200));
        openStatus();
    }

    function spawnToy() {
        toyActive = true;
        toyDragging = false;
        toyAwaitingThrow = true;
        toyWorldX = clampTarget(worldX + petRenderWidth * 0.55);
        toyHeight = Math.max(18, toyDiameter * 0.65);
        toyVelocityX = 0;
        toyVelocityY = 0;
        toyScreenName = primaryScreenName;
        emote = "⚾";
        thought = "Ball time. Drag it and give it a throw.";
        openStatus();
    }

    function beginToyDrag(screenName, localX, lift) {
        if (!toyActive)
            spawnToy();
        toyDragging = true;
        toyAwaitingThrow = true;
        toyScreenName = screenName;
        toyVelocityX = 0;
        toyVelocityY = 0;
        updateToyDrag(screenName, localX, lift);
    }

    function updateToyDrag(screenName, localX, lift) {
        const segment = segmentForScreen(screenName);
        if (!segment)
            return;
        toyScreenName = screenName;
        toyWorldX = clampTarget(segment.left + localX - toyDiameter / 2);
        toyHeight = Math.max(0, Math.min(Math.max(160, petSize * 1.7), lift));
    }

    function launchToy(screenName, localX, lift, velocityXInput, velocityYInput) {
        updateToyDrag(screenName, localX, lift);
        toyDragging = false;
        toyAwaitingThrow = false;
        toyVelocityX = Math.max(-860, Math.min(860, velocityXInput));
        toyVelocityY = Math.max(160, Math.min(980, velocityYInput));
        toyScreenName = screenName;
        fun = clampVital(fun + 12);
        emote = "♪";
        thought = "Fetch!";
        targetWorldX = clampTarget(toyWorldX - petRenderWidth * 0.2);
        setBehavior("play", randomBetween(1200, 2200));
        openStatus();
    }

    function stashToy() {
        toyActive = false;
        toyDragging = false;
        toyAwaitingThrow = false;
        toyHeight = 0;
        toyVelocityX = 0;
        toyVelocityY = 0;
    }

    function feed() {
        hunger = clampVital(hunger - 26);
        energy = clampVital(energy + 10);
        tiredness = clampVital(tiredness - 4);
        fun = clampVital(fun + 6);
        reactionMsRemaining = 1800;
        emote = "★";
        thought = "Snack secured. Much better.";
        setBehavior("react", 780);
        openStatus();
    }

    function nap() {
        tiredness = clampVital(tiredness + 6);
        energy = clampVital(energy - 2);
        fun = clampVital(fun - 2);
        emote = "zZ";
        thought = "Curling up for a proper nap.";
        setBehavior("rest_lay", randomBetween(6400, 9800));
        openStatus();
    }

    function wakeUp() {
        tiredness = clampVital(tiredness - 18);
        energy = clampVital(energy + 12);
        fun = clampVital(fun + 4);
        emote = "✦";
        thought = "Okay, I'm up.";
        chooseFocusZoneTarget();
        setBehavior("approach_focus", randomBetween(1200, 2200));
        openStatus();
    }

    function playWith() {
        if (toyActive) {
            toyDragging = false;
            toyAwaitingThrow = true;
            toyWorldX = clampTarget(worldX + petRenderWidth * 0.55);
            toyHeight = Math.max(18, toyDiameter * 0.65);
            toyVelocityX = 0;
            toyVelocityY = 0;
            toyScreenName = primaryScreenName;
            emote = "⚾";
            thought = "There it is. Grab it and throw it.";
            openStatus();
            return;
        }
        spawnToy();
    }

    function setMood(nextMood) {
        if (mood !== nextMood)
            mood = nextMood;
    }

    function setBehavior(nextBehavior, durationMs) {
        if (behavior !== nextBehavior) {
            behavior = nextBehavior;
        if (!["rest", "rest_sit", "rest_lay"].includes(nextBehavior))
            restMsAccumulated = 0;
            if (nextBehavior === "play") {
                const leapDistance = 140 + Math.random() * 90;
                targetWorldX = clampTarget(worldX + (direction >= 0 ? leapDistance : -leapDistance));
                targetKind = "monitor_roam_zone";
            }
        }
        behaviorMsRemaining = durationMs;
    }

    function refreshMood() {
        if (reactionMsRemaining > 0) {
            setMood("celebrating");
            emote = "♥";
            thought = "Warm hands. Safe pup.";
            return;
        }
        if (fun <= 18) {
            setMood("alert");
            emote = "⚾";
            thought = "I need a little play time.";
            return;
        }
        if (energy <= 18) {
            setMood("sleepy");
            emote = "…";
            thought = "Running low. Need a little recharge.";
            return;
        }
        if (tiredness >= 82) {
            setMood("sleepy");
            emote = "zZ";
            thought = "My paws feel heavy. Nap time soon.";
            return;
        }
        if (hunger >= 84) {
            setMood("alert");
            emote = "!";
            thought = "I could really go for a snack.";
            return;
        }
        if (batteryCritical || cpuUsagePercent >= 85) {
            setMood("stressed");
            emote = "!";
            thought = "Too much noise. Need a breather.";
            return;
        }
        if (batteryLow || cpuUsagePercent >= 65) {
            setMood("stressed");
            emote = "...";
            thought = "Everything feels a little heavy.";
            return;
        }
        if (musicPlaying) {
            setMood("happy");
            emote = "♪";
            thought = "This tune is nice.";
            return;
        }
        if (hourOfDay >= 23 || hourOfDay <= 6 || activeAppId.length === 0) {
            setMood("sleepy");
            emote = "zZ";
            thought = "A quiet nap would be perfect.";
            return;
        }
        if (appCategory === "editor" || appCategory === "terminal") {
            setMood("curious");
            emote = "?";
            thought = "Something interesting is happening.";
            return;
        }
        if (appCategory === "browser") {
            setMood("alert");
            emote = "•";
            thought = "So many tabs. So many trails.";
            return;
        }
        if (appCategory === "game") {
            setMood("happy");
            emote = "✦";
            thought = "This one looks lively.";
            return;
        }
        setMood("idle");
        emote = "";
        thought = "Just padding along.";
    }

    function refreshVitals(dt) {
        const powerRate = Math.min(1, Math.abs(Battery.energyRate ?? 0) / 45.0);
        const powerReserve = !Battery.available
            ? 0.86
            : (Battery.isPluggedIn
                ? 0.74 + powerRate * 0.22
                : 0.26 + (Battery.percentage * 0.34));
        const workDrive = Math.min(0.2, cpuUsagePercent / 100 * 0.18)
            + (musicPlaying ? 0.06 : 0)
            + (["editor", "terminal"].includes(appCategory) ? 0.05 : 0);
        const fatigueLoad = (cpuUsagePercent >= 85 ? 0.22 : (cpuUsagePercent >= 65 ? 0.11 : 0))
            + (batteryLow ? 0.12 : 0)
            + (batteryCritical ? 0.18 : 0);

        const energyDelta = ((powerReserve + workDrive) - 0.58 - fatigueLoad) * 8.5 * dt;
        energy = clampVital(energy + energyDelta);

        let hungerDelta = 1.35 * dt;
        if (behavior === "play" || behavior === "roam_fast")
            hungerDelta += 1.35 * dt;
        else if (["rest", "rest_sit", "rest_lay"].includes(behavior))
            hungerDelta += 0.35 * dt;
        hunger = clampVital(hunger + hungerDelta);

        let funDelta = 0.55 * dt;
        if (["rest", "rest_sit", "rest_lay"].includes(behavior))
            funDelta += 0.25 * dt;
        if (["editor", "terminal", "browser"].includes(appCategory))
            funDelta += 0.18 * dt;
        if (musicPlaying)
            funDelta -= 0.4 * dt;
        if (behavior === "play")
            funDelta -= 2.8 * dt;
        fun = clampVital(fun - funDelta);

        let tirednessDelta = 0;
        if (hourOfDay >= 23 || hourOfDay <= 6)
            tirednessDelta += 2.2 * dt;
        else
            tirednessDelta += 0.7 * dt;
        if (["rest", "rest_sit", "rest_lay"].includes(behavior))
            tirednessDelta -= 2.4 * dt;
        else if (behavior === "play")
            tirednessDelta += 1.1 * dt;
        else if (["roam", "roam_fast", "approach_focus"].includes(behavior))
            tirednessDelta += 0.45 * dt;
        if (energy < 30)
            tirednessDelta += 0.7 * dt;
        tiredness = clampVital(tiredness + tirednessDelta);
    }

    function walkSpeed() {
        let speed = 200 * speedMultiplier * activityMultiplier;
        switch (mood) {
        case "sleepy":
            speed *= 0.5;
            break;
        case "stressed":
            speed *= 1.25;
            break;
        case "happy":
            speed *= 1.12;
            break;
        case "curious":
            speed *= 1.08;
            break;
        case "alert":
            speed *= 1.1;
            break;
        case "celebrating":
            speed *= 1.2;
            break;
        default:
            break;
        }
        return speed;
    }

    function startTurn(nextDirection) {
        if (turnMsRemaining > 0)
            return;
        turnMsRemaining = 180;
        pendingDirection = nextDirection;
        targetVelocity = 0;
    }

    function choosePassiveBehavior() {
        if (energy < 24 || tiredness > 78) {
            chooseFocusZoneTarget();
            setBehavior(Math.random() < 0.82 ? "rest_lay" : "rest_sit", randomBetween(4200, 7600));
            return;
        }
        if (hunger > 82) {
            chooseMonitorRoamTarget();
            setBehavior("inspect", randomBetween(1200, 1900));
            return;
        }
        if (fun < 26 && energy > 28 && tiredness < 70) {
            chooseMonitorRoamTarget();
            setBehavior("play", randomBetween(820, 1100));
            return;
        }
        if (mood === "sleepy") {
            chooseFocusZoneTarget();
            setBehavior(Math.random() < 0.8 ? "rest_lay" : "rest_sit", randomBetween(3600, 6800));
            return;
        }
        if (mood === "stressed") {
            choosePassiveTarget();
            setBehavior(Math.random() < 0.25 ? "alert_react" : "roam_fast", randomBetween(1000, 2100));
            return;
        }
        if (activeClient && Math.random() < Math.max(0.36, followBias * 0.68)) {
            chooseFocusZoneTarget();
            setBehavior(Math.random() < 0.58 ? "rest_sit" : "approach_focus", randomBetween(2200, 4200));
            return;
        }
        if (activeClient && Math.random() < Math.max(0.18, followBias * 0.45)) {
            chooseFocusZoneTarget();
            setBehavior("approach_focus", randomBetween(1600, 2600));
            return;
        }
        if ((mood === "curious" || mood === "alert") && Math.random() < 0.32) {
            setBehavior("inspect", randomBetween(900, 1700));
            return;
        }
        if (mood === "happy" && Math.random() < 0.08) {
            setBehavior("play", 760);
            return;
        }
        choosePassiveTarget();
        setBehavior("roam", randomBetween(1300, 2400));
    }

    function advanceBehavior() {
        switch (behavior) {
        case "react":
        case "alert_react":
        case "play":
            if (activeClient && Math.random() < 0.55) {
                chooseFocusZoneTarget();
                setBehavior("approach_focus", randomBetween(1200, 2200));
            } else {
                choosePassiveBehavior();
            }
            return;
        case "approach_focus":
            if (Math.random() < 0.7)
                setBehavior("inspect", randomBetween(900, 1600));
            else if (mood === "sleepy" || energy < 30 || tiredness > 76)
                setBehavior("rest_lay", randomBetween(3600, 6200));
            else
                setBehavior("rest_sit", randomBetween(2600, 4400));
            return;
        case "roam":
        case "roam_fast":
            if ((mood === "curious" || mood === "alert") && Math.random() < 0.22) {
                setBehavior("inspect", randomBetween(1000, 1600));
                return;
            }
            if (activeClient && Math.random() < Math.max(0.2, followBias * 0.4)) {
                chooseFocusZoneTarget();
                setBehavior("approach_focus", randomBetween(1500, 2400));
                return;
            }
            if (Math.random() < 0.34) {
                setBehavior(Math.random() < 0.35 ? "rest_lay" : "rest", randomBetween(1800, 3600));
                return;
            }
            choosePassiveTarget();
            setBehavior(mood === "stressed" ? "roam_fast" : "roam", randomBetween(1400, 2400));
            return;
        case "inspect":
            if (targetKind === "focus_zone") {
                if (Math.random() < 0.72)
                    setBehavior((mood === "sleepy" || tiredness > 74) ? "rest_lay" : "rest_sit", randomBetween(2600, 5200));
                else {
                    choosePassiveTarget();
                    setBehavior("roam", randomBetween(1400, 2400));
                }
            } else if (activeClient && Math.random() < 0.35) {
                chooseFocusZoneTarget();
                setBehavior("approach_focus", randomBetween(1400, 2200));
            } else {
                choosePassiveTarget();
                setBehavior("roam", randomBetween(1500, 2800));
            }
            return;
        case "rest":
            if (mood === "sleepy" || restMsAccumulated >= 1100)
                setBehavior((mood === "sleepy" || tiredness > 72) ? "rest_lay" : "rest_sit", randomBetween(3000, 5600));
            else
                choosePassiveBehavior();
            return;
        case "rest_sit":
            if (targetKind === "focus_zone" && Math.random() < 0.22)
                setBehavior("inspect", randomBetween(800, 1400));
            else
                choosePassiveBehavior();
            return;
        case "rest_lay":
            if (targetKind === "focus_zone" && Math.random() < 0.14)
                setBehavior("inspect", randomBetween(900, 1500));
            else if (energy > 56 && tiredness < 48 && Math.random() < 0.22)
                setBehavior("rest_sit", randomBetween(1200, 2200));
            else
                choosePassiveBehavior();
            return;
        default:
            choosePassiveBehavior();
            return;
        }
    }

    function maybeTriggerAmbientBehavior() {
        if (["react", "alert_react", "play", "rest_sit", "rest_lay"].includes(behavior))
            return;

        if (focusRetargetCooldownMs > 0)
            focusRetargetCooldownMs = Math.max(0, focusRetargetCooldownMs - motionTimer.interval);

        const focusedAddress = activeClient?.address ?? "";
        if (focusedAddress !== lastFocusedAddress) {
            lastFocusedAddress = focusedAddress;
            if (focusedAddress.length > 0 && focusRetargetCooldownMs === 0) {
                chooseFocusZoneTarget();
                setBehavior("approach_focus", randomBetween(1800, 2800));
                focusRetargetCooldownMs = 2600;
                return;
            }
        }

        if (appCategory !== lastAppCategory) {
            lastAppCategory = appCategory;
            if (!["rest", "approach_focus"].includes(behavior))
                setBehavior("inspect", randomBetween(900, 1400));
            return;
        }

        if (musicPlaying !== lastMusicPlaying) {
            lastMusicPlaying = musicPlaying;
            if (musicPlaying) {
                setBehavior("play", 760);
                return;
            }
        }

        if (mood === "stressed" && behavior !== "alert_react" && Math.random() < 0.0035) {
            setBehavior("alert_react", 1100);
            return;
        }

        if (mood === "happy" && behavior === "roam" && Math.random() < 0.0012)
            setBehavior("play", 760);
    }

    function updateAnimationState() {
        switch (behavior) {
        case "roam":
        case "roam_fast":
        case "approach_focus":
            animationState = "walk";
            break;
        case "play":
            animationState = "celebrate";
            break;
        case "rest_sit":
            animationState = mood === "sleepy" ? "sleep" : "idle";
            break;
        case "rest_lay":
            animationState = "sleep";
            break;
        default:
            animationState = "idle";
            break;
        }
    }

    function tick() {
        if (!enabled || monitorSegments.length === 0)
            return;

        const dt = motionTimer.interval / 1000.0;
        refreshVitals(dt);
        refreshMood();

        if (toyActive && !toyDragging && !toyAwaitingThrow) {
            toyWorldX = clampTarget(toyWorldX + toyVelocityX * dt);
            toyHeight = Math.max(0, toyHeight + toyVelocityY * dt);
            toyVelocityY -= 940 * dt;
            toyVelocityX *= Math.pow(0.995, motionTimer.interval / 16.0);

            if (toyWorldX <= worldLeft || toyWorldX >= Math.max(worldLeft, worldRight - toyDiameter))
                toyVelocityX *= -0.55;

            if (toyHeight <= 0) {
                toyHeight = 0;
                if (Math.abs(toyVelocityY) > 130)
                    toyVelocityY = Math.abs(toyVelocityY) * 0.42;
                else
                    toyVelocityY = 0;

                if (Math.abs(toyVelocityX) < 8)
                    toyVelocityX = 0;
            }
        }

        if (dragging) {
            updateAnimationState();
            return;
        }

        maybeTriggerAmbientBehavior();

        if (reactionMsRemaining > 0)
            reactionMsRemaining = Math.max(0, reactionMsRemaining - motionTimer.interval);

        if (landingMsRemaining > 0)
            landingMsRemaining = Math.max(0, landingMsRemaining - motionTimer.interval);

        if (behaviorMsRemaining > 0)
            behaviorMsRemaining = Math.max(0, behaviorMsRemaining - motionTimer.interval);

        if (["rest", "rest_sit", "rest_lay"].includes(behavior))
            restMsAccumulated += motionTimer.interval;
        else
            restMsAccumulated = 0;

        if (blinkMsRemaining > 0) {
            blinkMsRemaining = Math.max(0, blinkMsRemaining - motionTimer.interval);
            blinking = true;
        } else {
            nextBlinkMs = Math.max(0, nextBlinkMs - motionTimer.interval);
            if (nextBlinkMs === 0) {
                blinking = true;
                blinkMsRemaining = 120;
                nextBlinkMs = 1800 + Math.floor(Math.random() * 2800);
            } else {
                blinking = false;
            }
        }

        if (behaviorMsRemaining === 0)
            advanceBehavior();

        if (toyActive && !toyDragging && !toyAwaitingThrow && !["rest", "rest_sit", "rest_lay", "react", "alert_react"].includes(behavior)) {
            const toyCenter = toyWorldX + toyDiameter / 2;
            const petCenter = worldX + petRenderWidth / 2;
            const toyDistance = toyCenter - petCenter;
            if (Math.abs(toyDistance) > settleRadius() + 10) {
                targetWorldX = clampTarget(toyWorldX - petRenderWidth * 0.2);
                if (behavior !== "play")
                    setBehavior("play", randomBetween(1000, 1800));
            } else if (toyHeight === 0 && Math.abs(toyVelocityX) < 28) {
                stashToy();
                fun = clampVital(fun + 18);
                hunger = clampVital(hunger + 4);
                tiredness = clampVital(tiredness + 3);
                emote = "★";
                thought = "Best throw yet.";
                setBehavior("react", 700);
                openStatus();
            }
        }

        const leftBoundary = worldLeft;
        const rightBoundary = Math.max(worldLeft, worldRight - petRenderWidth);
        const targetCenter = targetWorldX + petRenderWidth / 2;
        const currentCenter = worldX + petRenderWidth / 2;
        const distanceToTarget = targetCenter - currentCenter;
        const desiredDirection = distanceToTarget >= 0 ? 1 : -1;
        const closeEnough = Math.abs(distanceToTarget) < (behavior === "play" ? 26 : settleRadius());

        if (worldX <= leftBoundary + 4 && desiredDirection < 0)
            targetWorldX = leftBoundary + 40;
        else if (worldX >= rightBoundary - 4 && desiredDirection > 0)
            targetWorldX = rightBoundary - 40;

        if (closeEnough && ["roam", "roam_fast", "approach_focus"].includes(behavior)) {
            if (behavior === "approach_focus") {
                if (Math.random() < 0.72)
                    setBehavior("inspect", randomBetween(850, 1500));
                else if (mood === "sleepy" || energy < 30 || tiredness > 74)
                    setBehavior("rest_lay", randomBetween(3200, 5600));
                else
                    setBehavior("rest_sit", randomBetween(2200, 4200));
            }
            else if (Math.random() < 0.4)
                setBehavior("inspect", randomBetween(800, 1500));
            else
                choosePassiveBehavior();
        }

        const shouldMove = ["roam", "roam_fast", "approach_focus", "play"].includes(behavior) && !closeEnough;

        if (turnMsRemaining > 0) {
            turnMsRemaining = Math.max(0, turnMsRemaining - motionTimer.interval);
            targetVelocity = 0;
            if (turnMsRemaining === 0)
                direction = pendingDirection;
        } else if (shouldMove) {
            if (desiredDirection !== direction && Math.abs(velocity) > 18) {
                startTurn(desiredDirection);
            } else {
                direction = desiredDirection;
                const baseSpeed = behavior === "play"
                    ? walkSpeed() * 1.35
                    : (behavior === "roam_fast" ? walkSpeed() * 1.5 : walkSpeed());
                targetVelocity = direction * Math.min(baseSpeed, Math.max(70, Math.abs(distanceToTarget) * 3.5));
            }
        } else {
            targetVelocity = 0;
        }

        velocity += (targetVelocity - velocity) * 0.16;
        worldX += velocity * dt;
        clampWorldX();

        if (Math.abs(velocity) > 3) {
            walkPhaseAccumulator += motionTimer.interval * (Math.abs(velocity) / 170);
            if (walkPhaseAccumulator >= 120) {
                walkPhaseAccumulator = 0;
                walkPhase = (walkPhase + 1) % 4;
            }
        } else {
            walkPhase = 0;
            walkPhaseAccumulator = 0;
        }

        const swayBase = Math.abs(velocity) > 3
            ? Math.sin(Date.now() / 120.0) * 0.9
            : Math.sin(Date.now() / 320.0) * 0.18;
        tailSwing = swayBase;
        headTilt = Math.abs(velocity) > 3
            ? Math.sin(Date.now() / 170.0) * 6
            : Math.sin(Date.now() / 400.0) * 2.5;

        updateAnimationState();
    }

    function pet() {
        if (!reactionsEnabled)
            return;
        reactionMsRemaining = 1500;
        hunger = clampVital(hunger - 8);
        tiredness = clampVital(tiredness - 3);
        energy = clampVital(energy + 4);
        fun = clampVital(fun + 8);
        if (behavior === "rest_lay" || behavior === "rest_sit") {
            chooseFocusZoneTarget();
            setBehavior("approach_focus", randomBetween(1200, 2200));
        } else {
            setBehavior("react", 520);
        }
        emote = "♥";
        thought = "You noticed me.";
        openStatus();
    }

    function openStatus() {
        statusOpen = true;
        statusTimer.restart();
    }

    function toggleStatus() {
        statusOpen = !statusOpen;
        if (statusOpen)
            statusTimer.restart();
        else
            statusTimer.stop();
    }

    Timer {
        id: motionTimer
        interval: 16
        running: true
        repeat: true
        onTriggered: root.tick()
    }

    Timer {
        id: statusTimer
        interval: 7000
        running: false
        repeat: false
        onTriggered: root.statusOpen = false
    }
}
