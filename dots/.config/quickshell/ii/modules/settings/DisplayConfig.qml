import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ContentPage {
    id: displayConfigPage
    forceWidth: true

    property var monitors: []
    property var pendingChanges: ({})

    // Palette of colours for distinguishing monitors on the canvas
    readonly property var monitorColors: [
        Appearance.colors.colPrimary,
        Appearance.m3colors.m3tertiary,
        Appearance.m3colors.m3secondary,
        Appearance.m3colors.m3error,
    ]

    property string monitorsConfPath: `${Quickshell.env("HOME")}/.config/hypr/monitors.conf`
    property var confBitdepth: ({})

    function parseMonitorsConf() {
        readConfProc.running = false;
        readConfProc.running = true;
    }

    Process {
        id: readConfProc
        command: ["cat", displayConfigPage.monitorsConfPath]
        property string output: ""
        stdout: SplitParser {
            onRead: data => readConfProc.output += data
        }
        onExited: {
            let result = {};
            readConfProc.output.split("\n").forEach(line => {
                let m = line.match(/^monitor=([^,]+),.+,bitdepth,(\d+)/);
                if (m) result[m[1]] = parseInt(m[2]);
            });
            displayConfigPage.confBitdepth = result;
            readConfProc.output = "";
            // Only refresh monitors after conf is parsed so initPending gets correct bitdepth
            displayConfigPage.refreshMonitors();
        }
    }

    function refreshMonitors() {
        monitorProc.running = false;
        monitorProc.running = true;
    }

    // Snap scale to exact rational values to avoid floating point drift
    function snapScale(scale) {
        const knownScales = [1.0, 1.25, 1.5, 5/3, 1.875, 2.0];
        return knownScales.reduce((prev, curr) =>
            Math.abs(curr - scale) < Math.abs(prev - scale) ? curr : prev);
    }

    function buildMonitorLine(name, m, mon) {
        if (!m.enabled) return `monitor=${name},disabled`;
        let res = `${m.width}x${m.height}`;
        let refresh = m.refreshRate.toFixed(6);
        let pos = `${m.x}x${m.y}`;
        let snapped = snapScale(m.scale);
        // Format as exact fraction string to avoid float imprecision
        const scaleMap = {
            [1.0]:   "1.0",
            [1.25]:  "1.25",
            [1.5]:   "1.5",
            [5/3]:   "1.666667",
            [1.875]: "1.875",
            [2.0]:   "2.0"
        };
        let scale = scaleMap[snapped] ?? snapped.toFixed(4);
        let line = `monitor=${name},${res}@${refresh},${pos},${scale}`;
        line += `,transform,${m.transform}`;
        if ((m.bitdepth ?? 8) !== 8) line += `,bitdepth,${m.bitdepth}`;
        return line;
    }

    function applyMonitorChanges(monitorName) {
        let m = pendingChanges[monitorName];
        if (!m) return;
        // Build full monitors.conf content from all pending changes
        let lines = [];
        monitors.forEach(mon => {
            let p = pendingChanges[mon.name] ?? {};
            lines.push(buildMonitorLine(mon.name, p, mon));
        });
        let content = lines.join("\n") + "\n";
        writeProc.content = content;
        writeProc.running = false;
        writeProc.running = true;
    }

    function parseMode(modeStr) {
        let match = modeStr.match(/^(\d+)x(\d+)@([\d.]+)Hz$/);
        if (!match) return null;
        return {
            width: parseInt(match[1]),
            height: parseInt(match[2]),
            refreshRate: parseFloat(match[3]),
            label: `${match[1]}x${match[2]} @ ${parseFloat(match[3]).toFixed(2)} Hz`
        };
    }

    function initPending(monitor) {
        let name = monitor.name;
        if (!pendingChanges[name]) {
            pendingChanges[name] = {
                width: monitor.width,
                height: monitor.height,
                refreshRate: monitor.refreshRate,
                x: monitor.x,
                y: monitor.y,
                scale: monitor.scale,
                transform: monitor.transform,
                enabled: !monitor.disabled,
                bitdepth: confBitdepth[name] ?? 8
            };
        }
    }

    function currentModeIndex(monitor) {
        let seen = new Set();
        let sorted = [];
        let modes = monitor.availableModes || [];
        modes.forEach(modeStr => {
            let m = parseMode(modeStr);
            if (!m) return;
            let key = `${m.width}x${m.height}@${Math.round(m.refreshRate)}`;
            if (seen.has(key)) return;
            seen.add(key);
            sorted.push(m);
        });
        sorted.sort((a, b) => {
            let pixelDiff = (b.width * b.height) - (a.width * a.height);
            if (pixelDiff !== 0) return pixelDiff;
            return b.refreshRate - a.refreshRate;
        });
        for (let i = 0; i < sorted.length; i++) {
            let m = sorted[i];
            if (m.width === monitor.width &&
                m.height === monitor.height &&
                Math.abs(m.refreshRate - monitor.refreshRate) < 0.1) {
                return i;
            }
        }
        return 0;
    }

    // Compute canvas scale factor and offset so all monitors fit
    function canvasLayout(canvasWidth, canvasHeight, padding) {
        if (monitors.length === 0) return { scale: 1, offsetX: 0, offsetY: 0 };

        let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
        monitors.forEach(mon => {
            let p = pendingChanges[mon.name] ?? {};
            let x = p.x ?? mon.x;
            let y = p.y ?? mon.y;
            let w = p.width ?? mon.width;
            let h = p.height ?? mon.height;
            minX = Math.min(minX, x);
            minY = Math.min(minY, y);
            maxX = Math.max(maxX, x + w);
            maxY = Math.max(maxY, y + h);
        });

        let totalW = maxX - minX;
        let totalH = maxY - minY;
        if (totalW <= 0 || totalH <= 0) return { scale: 1, offsetX: 0, offsetY: 0 };

        let scaleX = (canvasWidth  - padding * 2) / totalW;
        let scaleY = (canvasHeight - padding * 2) / totalH;
        let s = Math.min(scaleX, scaleY);

        let scaledW = totalW * s;
        let scaledH = totalH * s;

        return {
            scale: s,
            offsetX: padding + (canvasWidth  - padding * 2 - scaledW) / 2 - minX * s,
            offsetY: padding + (canvasHeight - padding * 2 - scaledH) / 2 - minY * s
        };
    }

    Process {
        id: monitorProc
        command: ["hyprctl", "monitors", "all", "-j"]
        property string output: ""
        stdout: SplitParser {
            onRead: data => monitorProc.output += data
        }
        onExited: {
            try {
                let parsed = JSON.parse(monitorProc.output.trim());
                displayConfigPage.monitors = parsed;
                displayConfigPage.pendingChanges = ({});
                parsed.forEach(m => displayConfigPage.initPending(m));
                // Force reassignment so onPendingChangesChanged fires with fully populated data
                displayConfigPage.pendingChanges = Object.assign({}, displayConfigPage.pendingChanges);
            } catch (e) {
                console.warn("Failed to parse monitor data:", e);
            }
            monitorProc.output = "";
        }
    }

    // Write monitors.conf then reload Hyprland
    Process {
        id: writeProc
        property string content: ""
        command: ["python3", "-c", `
import sys
path = sys.argv[1]
content = sys.argv[2]
with open(path, 'w') as f:
    f.write(content)
`, displayConfigPage.monitorsConfPath, content]
        onExited: {
            reloadProc.running = false;
            reloadProc.running = true;
        }
    }

    Process {
        id: reloadProc
        command: ["hyprctl", "reload"]
        onExited: displayConfigPage.parseMonitorsConf()
    }

    Component.onCompleted: {
        parseMonitorsConf();
    }

    // ── Arrangement canvas ─────────────────────────────────────────────────
    ContentSection {
        icon: "monitor"
        title: Translation.tr("Display Arrangement")

        // Canvas area
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 220
            color: Appearance.m3colors.m3surfaceContainer
            radius: Appearance.rounding.normal

            // Re-compute layout whenever pendingChanges or size changes
            property var layout: displayConfigPage.canvasLayout(width, height, 16)
            onWidthChanged:  layout = displayConfigPage.canvasLayout(width, height, 16)
            onHeightChanged: layout = displayConfigPage.canvasLayout(width, height, 16)

            Connections {
                target: displayConfigPage
                function onPendingChangesChanged() {
                    canvasContainer.layout = displayConfigPage.canvasLayout(
                        canvasContainer.width, canvasContainer.height, 16);
                }
                function onMonitorsChanged() {
                    canvasContainer.layout = displayConfigPage.canvasLayout(
                        canvasContainer.width, canvasContainer.height, 16);
                }
            }

            id: canvasContainer

            StyledText {
                visible: displayConfigPage.monitors.length === 0
                anchors.centerIn: parent
                text: Translation.tr("No monitors detected")
                color: Appearance.colors.colSubtext
            }

            Repeater {
                model: displayConfigPage.monitors

                delegate: Item {
                    id: monRect
                    required property var modelData
                    required property int index

                    property var mon: modelData
                    property string monName: mon.name
                    property var pending: displayConfigPage.pendingChanges[monName] ?? {}
                    property var layout: canvasContainer.layout
                    property color monColor: displayConfigPage.monitorColors[index % displayConfigPage.monitorColors.length]

                    // Position and size on canvas
                    x: (pending.x ?? mon.x) * layout.scale + layout.offsetX
                    y: (pending.y ?? mon.y) * layout.scale + layout.offsetY
                    width:  (pending.width  ?? mon.width)  * layout.scale
                    height: (pending.height ?? mon.height) * layout.scale

                    // Drag state
                    property real dragStartX: 0
                    property real dragStartY: 0
                    property real dragStartPendingX: 0
                    property real dragStartPendingY: 0
                    property bool dragging: false

                    Rectangle {
                        anchors.fill: parent
                        color: Qt.alpha(monRect.monColor, monRect.dragging ? 0.55 : (pending.enabled ?? true) ? 0.35 : 0.15)
                        border.color: Qt.alpha(monRect.monColor, monRect.dragging ? 1.0 : 0.8)
                        border.width: monRect.dragging ? 2 : 1
                        radius: Appearance.rounding.small

                        Behavior on color { ColorAnimation { duration: 100 } }
                        Behavior on border.color { ColorAnimation { duration: 100 } }

                        // Monitor name
                        StyledText {
                            anchors {
                                top: parent.top
                                left: parent.left
                                right: parent.right
                                margins: 6
                            }
                            text: monRect.monName
                            font.pixelSize: Math.max(9, Math.min(14, parent.height * 0.16))
                            color: monRect.monColor
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignHCenter
                        }

                        // Resolution
                        StyledText {
                            anchors.centerIn: parent
                            text: `${pending.width ?? mon.width}×${pending.height ?? mon.height}`
                            font.pixelSize: Math.max(8, Math.min(12, parent.height * 0.13))
                            color: Appearance.m3colors.m3onSurface
                            opacity: 0.7
                            horizontalAlignment: Text.AlignHCenter
                        }

                        // Disabled badge
                        Rectangle {
                            visible: !(pending.enabled ?? true)
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: parent.height * 0.18
                            color: Qt.alpha(Appearance.m3colors.m3error, 0.8)
                            radius: Appearance.rounding.full
                            implicitWidth: disabledLabel.implicitWidth + 8
                            implicitHeight: disabledLabel.implicitHeight + 4
                            StyledText {
                                id: disabledLabel
                                anchors.centerIn: parent
                                text: Translation.tr("OFF")
                                font.pixelSize: 9
                                color: Appearance.m3colors.m3onError
                            }
                        }
                    }

                    // Dummy item used solely to prevent the parent Flickable from stealing the drag grab
                    Item { id: dragDummy }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: monRect.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                        propagateComposedEvents: false
                        drag.target: dragDummy
                        drag.axis: Drag.XAndYAxis

                        onPressed: mouse => {
                            mouse.accepted = true;
                            monRect.dragging = true;
                            let canvasPos = mapToItem(canvasContainer, mouse.x, mouse.y);
                            monRect.dragStartX = canvasPos.x;
                            monRect.dragStartY = canvasPos.y;
                            monRect.dragStartPendingX = monRect.pending.x ?? monRect.mon.x;
                            monRect.dragStartPendingY = monRect.pending.y ?? monRect.mon.y;
                        }

                        onPositionChanged: mouse => {
                            if (!monRect.dragging) return;
                            let layout = canvasContainer.layout;
                            if (layout.scale <= 0) return;

                            let canvasPos = mapToItem(canvasContainer, mouse.x, mouse.y);
                            let dx = (canvasPos.x - monRect.dragStartX) / layout.scale;
                            let dy = (canvasPos.y - monRect.dragStartY) / layout.scale;

                            let nx = Math.round(monRect.dragStartPendingX + dx);
                            let ny = Math.round(monRect.dragStartPendingY + dy);

                            let dw = monRect.pending.width  ?? monRect.mon.width;
                            let dh = monRect.pending.height ?? monRect.mon.height;

                            // Resolve collisions with all other monitors
                            let allMonitors = displayConfigPage.monitors;
                            let allPending  = displayConfigPage.pendingChanges;
                            for (let pass = 0; pass < allMonitors.length; pass++) {
                                let pushed = false;
                                for (let i = 0; i < allMonitors.length; i++) {
                                    let other = allMonitors[i];
                                    if (other.name === monRect.monName) continue;
                                    let op = allPending[other.name] ?? {};
                                    if (!(op.enabled ?? true)) continue;
                                    let ox = op.x ?? other.x;
                                    let oy = op.y ?? other.y;
                                    let ow = op.width  ?? other.width;
                                    let oh = op.height ?? other.height;
                                    // Skip if no overlap
                                    if (nx >= ox + ow || nx + dw <= ox || ny >= oy + oh || ny + dh <= oy) continue;
                                    // Pick the axis with minimum penetration
                                    let pL = (ox + ow) - nx;
                                    let pR = (nx + dw) - ox;
                                    let pU = (oy + oh) - ny;
                                    let pD = (ny + dh) - oy;
                                    let minP = Math.min(pL, pR, pU, pD);
                                    if      (minP === pL) nx = ox + ow;
                                    else if (minP === pR) nx = ox - dw;
                                    else if (minP === pU) ny = oy + oh;
                                    else                  ny = oy - dh;
                                    pushed = true;
                                }
                                if (!pushed) break;
                            }

                            let p = Object.assign({}, displayConfigPage.pendingChanges[monRect.monName]);
                            p.x = nx;
                            p.y = ny;
                            displayConfigPage.pendingChanges[monRect.monName] = p;
                            displayConfigPage.pendingChanges = Object.assign({}, displayConfigPage.pendingChanges);
                        }

                        onReleased: {
                            monRect.dragging = false;
                            // Reset dummy so it doesn't drift
                            dragDummy.x = 0;
                            dragDummy.y = 0;
                        }
                    }
                }
            }
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: Translation.tr("Drag monitors to reposition · changes apply per-monitor below")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
        }

        RippleButtonWithIcon {
            Layout.fillWidth: true
            nerdIcon: ""
            mainText: Translation.tr("Refresh monitor list")
            onClicked: displayConfigPage.refreshMonitors()
        }
    }

    // ── Per-monitor settings ───────────────────────────────────────────────
    Repeater {
        model: displayConfigPage.monitors

        delegate: ContentSection {
            id: monitorSection
            required property var modelData
            required property int index

            property var mon: modelData
            property string monName: mon.name
            property var pending: displayConfigPage.pendingChanges[monName] ?? {}
            property var availableModes: mon.availableModes || []
            property color monColor: displayConfigPage.monitorColors[index % displayConfigPage.monitorColors.length]

            icon: "tv"
            title: `${mon.name}  —  ${mon.make} ${mon.model}`

            // Coloured indicator strip matching canvas colour
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 3
                radius: Appearance.rounding.full
                color: monitorSection.monColor
                opacity: 0.7
            }

            // Enable / disable
            ConfigSwitch {
                buttonIcon: "power_settings_new"
                text: Translation.tr("Enabled")
                checked: monitorSection.pending.enabled ?? true
                onCheckedChanged: {
                    let p = Object.assign({}, displayConfigPage.pendingChanges[monitorSection.monName]);
                    p.enabled = checked;
                    displayConfigPage.pendingChanges[monitorSection.monName] = p;
                    displayConfigPage.pendingChanges = Object.assign({}, displayConfigPage.pendingChanges);
                }
            }

            // Mode selector
            ContentSubsection {
                title: Translation.tr("Mode")
                tooltip: Translation.tr("Select a preset resolution and refresh rate")

                StyledComboBox {
                    buttonIcon: "tune"
                    textRole: "label"
                    Layout.fillWidth: true

                    model: {
                        let seen = new Set();
                        let out = [];
                        monitorSection.availableModes.forEach(modeStr => {
                            let m = displayConfigPage.parseMode(modeStr);
                            if (!m) return;
                            let key = `${m.width}x${m.height}@${Math.round(m.refreshRate)}`;
                            if (seen.has(key)) return;
                            seen.add(key);
                            out.push(m);
                        });
                        out.sort((a, b) => {
                            let pixelDiff = (b.width * b.height) - (a.width * a.height);
                            if (pixelDiff !== 0) return pixelDiff;
                            return b.refreshRate - a.refreshRate;
                        });
                        return out;
                    }

                    currentIndex: displayConfigPage.currentModeIndex(monitorSection.mon)

                    onActivated: idx => {
                        let seen = new Set();
                        let sorted = [];
                        monitorSection.availableModes.forEach(modeStr => {
                            let m = displayConfigPage.parseMode(modeStr);
                            if (!m) return;
                            let key = `${m.width}x${m.height}@${m.refreshRate.toFixed(2)}`;
                            if (seen.has(key)) return;
                            seen.add(key);
                            sorted.push(m);
                        });
                        sorted.sort((a, b) => {
                            let pixelDiff = (b.width * b.height) - (a.width * a.height);
                            if (pixelDiff !== 0) return pixelDiff;
                            return b.refreshRate - a.refreshRate;
                        });
                        let m = sorted[idx];
                        if (!m) return;
                        let p = Object.assign({}, displayConfigPage.pendingChanges[monitorSection.monName]);
                        p.width = m.width;
                        p.height = m.height;
                        p.refreshRate = m.refreshRate;
                        displayConfigPage.pendingChanges[monitorSection.monName] = p;
                        displayConfigPage.pendingChanges = Object.assign({}, displayConfigPage.pendingChanges);
                    }
                }
            }

            // Position — kept as spinboxes for precise numeric entry
            ContentSubsection {
                title: Translation.tr("Position")
                tooltip: Translation.tr("Current: %1x%2 · or drag on the canvas above")
                    .arg(pending.x ?? mon.x).arg(pending.y ?? mon.y)

                ConfigRow {
                    ConfigSpinBox {
                        id: xSpinBox
                        icon: "swap_horiz"
                        text: Translation.tr("X offset")
                        value: monitorSection.pending.x ?? mon.x
                        from: -7680
                        to: 7680
                        stepSize: 1
                        onValueChanged: {
                            let p = Object.assign({}, displayConfigPage.pendingChanges[monitorSection.monName]);
                            p.x = value;
                            displayConfigPage.pendingChanges[monitorSection.monName] = p;
                            displayConfigPage.pendingChanges = Object.assign({}, displayConfigPage.pendingChanges);
                        }
                    }
                    ConfigSpinBox {
                        id: ySpinBox
                        icon: "swap_vert"
                        text: Translation.tr("Y offset")
                        value: monitorSection.pending.y ?? mon.y
                        from: -4320
                        to: 4320
                        stepSize: 1
                        onValueChanged: {
                            let p = Object.assign({}, displayConfigPage.pendingChanges[monitorSection.monName]);
                            p.y = value;
                            displayConfigPage.pendingChanges[monitorSection.monName] = p;
                            displayConfigPage.pendingChanges = Object.assign({}, displayConfigPage.pendingChanges);
                        }
                    }
                    RippleButton {
                        implicitHeight: 30
                        implicitWidth: 120
                        colBackground: Appearance.colors.colLayer2
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        colRipple: Appearance.colors.colLayer2Active

                        contentItem: StyledText {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            font.pixelSize: Appearance.font.pixelSize.small
                            text: Translation.tr("Reset position")
                            color: Appearance.colors.colOnLayer2
                        }

                        onClicked: {
                            let p = Object.assign({}, displayConfigPage.pendingChanges[monitorSection.monName]);
                            p.x = 0;
                            p.y = 0;
                            displayConfigPage.pendingChanges[monitorSection.monName] = p;
                            displayConfigPage.pendingChanges = Object.assign({}, displayConfigPage.pendingChanges);

                            // Resolve collisions after reset
                            let nx = 0;
                            let ny = 0;
                            let dw = p.width  ?? monitorSection.mon.width;
                            let dh = p.height ?? monitorSection.mon.height;
                            let allMonitors = displayConfigPage.monitors;
                            let allPending  = displayConfigPage.pendingChanges;
                            for (let pass = 0; pass < allMonitors.length; pass++) {
                                let pushed = false;
                                for (let i = 0; i < allMonitors.length; i++) {
                                    let other = allMonitors[i];
                                    if (other.name === monitorSection.monName) continue;
                                    let op = allPending[other.name] ?? {};
                                    if (!(op.enabled ?? true)) continue;
                                    let ox = op.x ?? other.x;
                                    let oy = op.y ?? other.y;
                                    let ow = op.width  ?? other.width;
                                    let oh = op.height ?? other.height;
                                    if (nx >= ox + ow || nx + dw <= ox || ny >= oy + oh || ny + dh <= oy) continue;
                                    // Always resolve along X — push to the right of the blocking monitor
                                    nx = ox + ow;
                                    pushed = true;
                                }
                                if (!pushed) break;
                            }

                            let resolved = Object.assign({}, displayConfigPage.pendingChanges[monitorSection.monName]);
                            resolved.x = nx;
                            resolved.y = ny;
                            displayConfigPage.pendingChanges[monitorSection.monName] = resolved;
                            displayConfigPage.pendingChanges = Object.assign({}, displayConfigPage.pendingChanges);
                            xSpinBox.value = nx;
                            ySpinBox.value = ny;
                        }
                    }
                }
            }

            // Scale
            ContentSubsection {
                title: Translation.tr("Scale")
                tooltip: Translation.tr("Current: %1%").arg(Math.round(mon.scale * 100))

                ConfigSelectionArray {
                    currentValue: {
                        let scale = Math.round((monitorSection.pending.scale ?? mon.scale) * 10000);
                        let options = [10000, 12500, 15000, 16667, 18750, 20000];
                        return options.reduce((prev, curr) =>
                            Math.abs(curr - scale) < Math.abs(prev - scale) ? curr : prev);
                    }
                    onSelected: newValue => {
                        let p = Object.assign({}, displayConfigPage.pendingChanges[monitorSection.monName]);
                        p.scale = newValue / 10000;
                        displayConfigPage.pendingChanges[monitorSection.monName] = p;
                        displayConfigPage.pendingChanges = Object.assign({}, displayConfigPage.pendingChanges);
                    }
                    options: [
                        { displayName: "100%",   value: 10000 },
                        { displayName: "125%",   value: 12500 },
                        { displayName: "150%",   value: 15000 },
                        { displayName: "167%",   value: 16667 },
                        { displayName: "188%",   value: 18750 },
                        { displayName: "200%",   value: 20000 },
                    ]
                }
            }

            // Rotation / transform
            ContentSubsection {
                title: Translation.tr("Rotation")
                tooltip: Translation.tr("Current transform: %1").arg(mon.transform)

                ConfigSelectionArray {
                    currentValue: monitorSection.pending.transform ?? mon.transform
                    onSelected: newValue => {
                        let p = Object.assign({}, displayConfigPage.pendingChanges[monitorSection.monName]);
                        p.transform = newValue;
                        displayConfigPage.pendingChanges[monitorSection.monName] = p;
                        displayConfigPage.pendingChanges = Object.assign({}, displayConfigPage.pendingChanges);
                    }
                    options: [
                        { displayName: Translation.tr("0°"),   icon: "screen_rotation_alt",  value: 0 },
                        { displayName: Translation.tr("90°"),  icon: "rotate_90_degrees_cw",  value: 1 },
                        { displayName: Translation.tr("180°"), icon: "rotate_left",            value: 2 },
                        { displayName: Translation.tr("270°"), icon: "rotate_90_degrees_ccw", value: 3 },
                    ]
                }
            }

            property bool is10bit: (displayConfigPage.pendingChanges[monName]?.bitdepth ?? 8) === 10

            Connections {
                target: displayConfigPage
                function onPendingChangesChanged() {
                    let new10bit = (displayConfigPage.pendingChanges[monitorSection.monName]?.bitdepth ?? 8) === 10;
                    if (monitorSection.is10bit !== new10bit) {
                        monitorSection.is10bit = new10bit;
                        tenBitSwitch.checked = new10bit;
                    }
                }
            }

            // 10-bit colour
            ConfigSwitch {
                id: tenBitSwitch
                Layout.fillWidth: false
                Layout.alignment: Qt.AlignRight
                buttonIcon: "hdr_on"
                text: Translation.tr("10-bit")
                checked: monitorSection.is10bit

                onCheckedChanged: {
                    if (monitorSection.is10bit === checked) return;
                    monitorSection.is10bit = checked;
                    let p = Object.assign({}, displayConfigPage.pendingChanges[monitorSection.monName]);
                    p.bitdepth = checked ? 10 : 8;
                    displayConfigPage.pendingChanges[monitorSection.monName] = p;
                    displayConfigPage.pendingChanges = Object.assign({}, displayConfigPage.pendingChanges);
                }
                StyledToolTip {
                    text: Translation.tr("Enables 10-bit colour output.\nRequires hardware and driver support.")
                }
            }

            // Apply
            ConfigRow {
                Layout.fillWidth: false
                Layout.alignment: Qt.AlignRight

                RippleButton {
                    implicitHeight: 30
                    implicitWidth: 140
                    colBackground: monitorSection.monColor
                    colBackgroundHover: Qt.lighter(monitorSection.monColor, 1.1)
                    colRipple: Qt.lighter(monitorSection.monColor, 1.2)

                    contentItem: StyledText {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Appearance.font.pixelSize.small
                        text: Translation.tr("Apply %1").arg(monitorSection.monName)
                        color: Appearance.colors.colOnPrimary
                    }

                    onClicked: displayConfigPage.applyMonitorChanges(monitorSection.monName)
                }
            }
        }
    }
}
