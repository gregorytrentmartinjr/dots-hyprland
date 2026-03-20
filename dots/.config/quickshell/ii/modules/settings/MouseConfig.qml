import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions as CF

ContentPage {
    id: root
    forceWidth: true

    property bool ready:           false
    property bool leftHanded:      false
    property bool accelEnabled:    true
    property bool naturalScroll:   false
    property bool naturalScrollTP: true
    property real sensitivity:     0.0

    // 2 cards * 150px + 16px gap

    readonly property string envConf:
        Quickshell.env("HOME") + "/.config/hypr/custom/env.conf"

    Component.onCompleted: {
        mouseProc.running = false; mouseProc.running = true
        tpProc.running    = false; tpProc.running    = true
    }

    Process {
        id: mouseProc
        command: ["awk",
            "/touchpad/{exit} /^[[:space:]]*(sensitivity|left_handed|accel_profile|natural_scroll)[[:space:]]*=/{print}",
            root.envConf
        ]
        stdout: SplitParser {
            onRead: data => {
                const m = data.match(/^\s*(\w+)\s*=\s*(.+?)\s*$/)
                if (!m) return
                const key = m[1]; const val = m[2]
                if (key === "sensitivity")    root.sensitivity   = parseFloat(val) || 0.0
                if (key === "left_handed")    root.leftHanded    = val === "1" || val === "true"
                if (key === "accel_profile")  root.accelEnabled  = val !== "flat"
                if (key === "natural_scroll") root.naturalScroll = val === "1" || val === "true"
            }
        }
        onExited: root.ready = true
    }

    Process {
        id: tpProc
        command: ["bash", "-c",
            "grep -A5 touchpad \"$1\" 2>/dev/null | grep natural_scroll || true",
            "--", root.envConf
        ]
        stdout: SplitParser {
            onRead: data => {
                const m = data.match(/natural_scroll\s*=\s*(\S+)/)
                if (m) root.naturalScrollTP = m[1] === "1" || m[1] === "true"
            }
        }
    }

    function applyInput(key, value) {
        if (!root.ready) return
        Quickshell.execDetached(["hyprctl", "keyword", "input:" + key, String(value)])
        // Python script replaces only first occurrence of key (before touchpad block)
        const mouseScript =
            "import sys\n" +
            "key, val, conf = sys.argv[1], sys.argv[2], sys.argv[3]\n" +
            "lines = open(conf).read().split('\\n')\n" +
            "in_tp = False\n" +
            "done = False\n" +
            "result = []\n" +
            "for line in lines:\n" +
            "    if 'touchpad' in line:\n" +
            "        in_tp = True\n" +
            "    if not in_tp and not done and line.strip().startswith(key):\n" +
            "        line = '    ' + key + ' = ' + val\n" +
            "        done = True\n" +
            "    result.append(line)\n" +
            "if not done:\n" +
            "    result.append('    ' + key + ' = ' + val)\n" +
            "open(conf, 'w').write('\\n'.join(result))\n"
        Quickshell.execDetached(["python3", "-c", mouseScript, String(key), String(value), root.envConf])
    }

    // Write mouse natural_scroll - skips inside touchpad block
    // chr(123)='{' chr(125)='}' avoids QML brace counting
    function applyMouseNaturalScroll(value) {
        if (!root.ready) return
        Quickshell.execDetached(["hyprctl", "keyword", "input:natural_scroll", String(value)])
        const py =
            "import sys\n" +
            "val, conf = sys.argv[1], sys.argv[2]\n" +
            "ob = chr(123)\n" +
            "cb = chr(125)\n" +
            "lines = open(conf).read().split('\\n')\n" +
            "in_tp = False\n" +
            "result = []\n" +
            "for line in lines:\n" +
            "    if 'touchpad' in line and ob in line:\n" +
            "        in_tp = True\n" +
            "    if in_tp and cb in line and ob not in line:\n" +
            "        in_tp = False\n" +
            "    if not in_tp and 'natural_scroll' in line:\n" +
            "        line = '    natural_scroll = ' + val\n" +
            "    result.append(line)\n" +
            "open(conf, 'w').write('\\n'.join(result))\n"
        Quickshell.execDetached(["python3", "-c", py, String(value), root.envConf])
    }

    // Write touchpad natural_scroll - only inside touchpad block
    function applyTouchpadInput(value) {
        if (!root.ready) return
        Quickshell.execDetached(["hyprctl", "keyword", "input:touchpad:natural_scroll", String(value)])
        const py =
            "import sys\n" +
            "val, conf = sys.argv[1], sys.argv[2]\n" +
            "ob = chr(123)\n" +
            "lines = open(conf).read().split('\\n')\n" +
            "in_tp = False\n" +
            "result = []\n" +
            "for line in lines:\n" +
            "    if 'touchpad' in line and ob in line:\n" +
            "        in_tp = True\n" +
            "    if in_tp and 'natural_scroll' in line:\n" +
            "        line = '        natural_scroll = ' + val\n" +
            "        in_tp = False\n" +
            "    result.append(line)\n" +
            "open(conf, 'w').write('\\n'.join(result))\n"
        Quickshell.execDetached(["python3", "-c", py, String(value), root.envConf])
    }

    // ── General ───────────────────────────────────────────────────────────────
    ContentSection {
        icon: "mouse"
        title: Translation.tr("General")

        ConfigRow {
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Primary Button")
                font.pixelSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colOnLayer1
            }
            ConfigSelectionArray {
                currentValue: root.leftHanded ? "right" : "left"
                onSelected: val => {
                    root.leftHanded = val === "right"
                    root.applyInput("left_handed", root.leftHanded ? 1 : 0)
                }
                options: [
                    { displayName: Translation.tr("Left"),  value: "left"  },
                    { displayName: Translation.tr("Right"), value: "right" },
                ]
            }
        }
    }

    // ── Mouse ─────────────────────────────────────────────────────────────────
    ContentSection {
        icon: "mouse"
        title: Translation.tr("Mouse")

        ConfigRow {
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Pointer Speed")
                font.pixelSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colOnLayer1
            }
            StyledComboBox {
                textRole: "displayName"
                model: [
                    { displayName: Translation.tr("Slowest"), value: -1.0 },
                    { displayName: Translation.tr("Slow"),    value: -0.5 },
                    { displayName: Translation.tr("Default"), value:  0.0 },
                    { displayName: Translation.tr("Fast"),    value:  1.0 },
                    { displayName: Translation.tr("Fastest"), value:  2.0 },
                ]
                currentIndex: {
                    const idx = model.findIndex(item => Math.abs(item.value - root.sensitivity) < 0.26)
                    return idx !== -1 ? idx : 2
                }
                onActivated: index => {
                    root.sensitivity = model[index].value
                    root.applyInput("sensitivity", model[index].value.toFixed(1))
                }
            }
        }

        ConfigRow {
            ConfigSwitch {
                Layout.fillWidth: true
                buttonIcon: "trending_flat"
                text: Translation.tr("Mouse Acceleration")
                checked: root.accelEnabled
                onCheckedChanged: {
                    root.accelEnabled = checked
                    root.applyInput("accel_profile", checked ? "adaptive" : "flat")
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Scroll Direction")
            RowLayout {
                spacing: 16
                MouseArea {
                    cursorShape: Qt.PointingHandCursor
                    implicitWidth: childrenRect.width; implicitHeight: childrenRect.height
                    onClicked: { root.naturalScroll = false; root.applyMouseNaturalScroll(0) }
                    ColumnLayout {
                        spacing: 6
                        Rectangle {
                            implicitWidth: 150; implicitHeight: 120
                            radius: Appearance.rounding.normal
                            color: !root.naturalScroll ? Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.1) : Appearance.colors.colLayer2
                            border.width: !root.naturalScroll ? 2 : 1
                            border.color: !root.naturalScroll ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                            MouseArea { anchors.fill: parent; z: 1; cursorShape: Qt.PointingHandCursor; onClicked: { root.naturalScroll = false; root.applyMouseNaturalScroll(0) } }
                            Rectangle {
                                x: 12; y: 12; width: 76; height: 84; radius: 4
                                color: Appearance.colors.colLayer3; border.width: 1; border.color: Appearance.colors.colOutlineVariant
                                Rectangle { width: parent.width; height: 13; radius: 4; color: Appearance.colors.colLayer2
                                    Rectangle { x: 4; anchors.verticalCenter: parent.verticalCenter; width: 5; height: 5; radius: 3; color: Appearance.colors.colSubtext; opacity: 0.4 }
                                }
                                Column { x: 6; y: 18; spacing: 4
                                    Repeater { model: [50,38,52,34]; Rectangle { width: modelData; height: 5; radius: 2; color: Appearance.colors.colSubtext; opacity: 0.3 } }
                                }
                                Rectangle { x: parent.width-7; y: 13; width: 4; height: parent.height-13; radius: 2; color: Appearance.colors.colLayer2
                                    Rectangle { width: 4; height: 18; radius: 2; y: 2; color: !root.naturalScroll ? Appearance.colors.colPrimary : Appearance.colors.colSubtext; opacity: 0.7 }
                                }
                                MaterialSymbol { anchors.horizontalCenter: parent.horizontalCenter; y: 44; text: "arrow_upward"; iconSize: 18; color: !root.naturalScroll ? Appearance.colors.colPrimary : Appearance.colors.colSubtext; opacity: 0.7 }
                            }
                            Rectangle { x: 100; y: 12; width: 28; height: 52; radius: 14
                                color: !root.naturalScroll ? Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.18) : Appearance.colors.colLayer3
                                border.width: 1; border.color: !root.naturalScroll ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                                Rectangle { x: 13; y: 0; width: 1; height: 22; color: Appearance.colors.colOutlineVariant }
                                Rectangle { anchors.horizontalCenter: parent.horizontalCenter; y: 7; width: 5; height: 14; radius: 3; color: Appearance.colors.colSubtext; opacity: 0.6 }
                            }
                            MaterialSymbol { x: 107; y: 68; text: "arrow_upward"; iconSize: 16; color: !root.naturalScroll ? Appearance.colors.colPrimary : Appearance.colors.colSubtext }
                        }
                        RowLayout {
                            spacing: 6; Layout.alignment: Qt.AlignHCenter
                            Rectangle {
                                width: 16; height: 16; radius: 8; border.width: 2
                                border.color: !root.naturalScroll ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                                color: !root.naturalScroll ? Appearance.colors.colPrimary : "transparent"
                                Rectangle { anchors.centerIn: parent; width: 6; height: 6; radius: 3; color: Appearance.colors.colOnPrimary; visible: !root.naturalScroll }
                            }
                            ColumnLayout {
                                spacing: 1
                                StyledText { text: Translation.tr("Traditional"); font.pixelSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colOnLayer1 }
                                StyledText { text: Translation.tr("Scrolling moves the view"); font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colSubtext }
                            }
                        }
                    }
                }
                MouseArea {
                    cursorShape: Qt.PointingHandCursor
                    implicitWidth: childrenRect.width; implicitHeight: childrenRect.height
                    onClicked: { root.naturalScroll = true; root.applyMouseNaturalScroll(1) }
                    ColumnLayout {
                        spacing: 6
                        Rectangle {
                            implicitWidth: 150; implicitHeight: 120
                            radius: Appearance.rounding.normal
                            color: root.naturalScroll ? Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.1) : Appearance.colors.colLayer2
                            border.width: root.naturalScroll ? 2 : 1
                            border.color: root.naturalScroll ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                            MouseArea { anchors.fill: parent; z: 1; cursorShape: Qt.PointingHandCursor; onClicked: { root.naturalScroll = true; root.applyMouseNaturalScroll(1) } }
                            Rectangle {
                                x: 12; y: 12; width: 76; height: 84; radius: 4
                                color: Appearance.colors.colLayer3; border.width: 1; border.color: Appearance.colors.colOutlineVariant
                                Rectangle { width: parent.width; height: 13; radius: 4; color: Appearance.colors.colLayer2
                                    Rectangle { x: 4; anchors.verticalCenter: parent.verticalCenter; width: 5; height: 5; radius: 3; color: Appearance.colors.colSubtext; opacity: 0.4 }
                                }
                                Column { x: 6; y: 18; spacing: 4
                                    Repeater { model: [50,38,52,34]; Rectangle { width: modelData; height: 5; radius: 2; color: Appearance.colors.colSubtext; opacity: 0.3 } }
                                }
                                Rectangle { x: parent.width-7; y: 13; width: 4; height: parent.height-13; radius: 2; color: Appearance.colors.colLayer2
                                    Rectangle { width: 4; height: 18; radius: 2; y: 48; color: root.naturalScroll ? Appearance.colors.colPrimary : Appearance.colors.colSubtext; opacity: 0.7 }
                                }
                                MaterialSymbol { anchors.horizontalCenter: parent.horizontalCenter; y: 44; text: "arrow_downward"; iconSize: 18; color: root.naturalScroll ? Appearance.colors.colPrimary : Appearance.colors.colSubtext; opacity: 0.7 }
                            }
                            Rectangle { x: 100; y: 12; width: 28; height: 52; radius: 14
                                color: root.naturalScroll ? Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.18) : Appearance.colors.colLayer3
                                border.width: 1; border.color: root.naturalScroll ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                                Rectangle { x: 13; y: 0; width: 1; height: 22; color: Appearance.colors.colOutlineVariant }
                                Rectangle { anchors.horizontalCenter: parent.horizontalCenter; y: 7; width: 5; height: 14; radius: 3; color: Appearance.colors.colSubtext; opacity: 0.6 }
                            }
                            MaterialSymbol { x: 107; y: 68; text: "arrow_downward"; iconSize: 16; color: root.naturalScroll ? Appearance.colors.colPrimary : Appearance.colors.colSubtext }
                        }
                        RowLayout {
                            spacing: 6; Layout.alignment: Qt.AlignHCenter
                            Rectangle {
                                width: 16; height: 16; radius: 8; border.width: 2
                                border.color: root.naturalScroll ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                                color: root.naturalScroll ? Appearance.colors.colPrimary : "transparent"
                                Rectangle { anchors.centerIn: parent; width: 6; height: 6; radius: 3; color: Appearance.colors.colOnPrimary; visible: root.naturalScroll }
                            }
                            ColumnLayout {
                                spacing: 1
                                StyledText { text: Translation.tr("Natural"); font.pixelSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colOnLayer1 }
                                StyledText { text: Translation.tr("Scrolling moves the content"); font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colSubtext }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Touchpad ──────────────────────────────────────────────────────────────
    ContentSection {
        icon: "touch_app"
        title: Translation.tr("Touchpad")

        ContentSubsection {
            title: Translation.tr("Scroll Direction")
            RowLayout {
                spacing: 16
                MouseArea {
                    cursorShape: Qt.PointingHandCursor
                    implicitWidth: childrenRect.width; implicitHeight: childrenRect.height
                    onClicked: { root.naturalScrollTP = false; root.applyTouchpadInput(0) }
                    ColumnLayout {
                        spacing: 6
                        Rectangle {
                            implicitWidth: 150; implicitHeight: 120
                            radius: Appearance.rounding.normal
                            color: !root.naturalScrollTP ? Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.1) : Appearance.colors.colLayer2
                            border.width: !root.naturalScrollTP ? 2 : 1
                            border.color: !root.naturalScrollTP ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                            MouseArea { anchors.fill: parent; z: 1; cursorShape: Qt.PointingHandCursor; onClicked: { root.naturalScrollTP = false; root.applyTouchpadInput(0) } }
                            Rectangle {
                                x: 12; y: 12; width: 76; height: 84; radius: 4
                                color: Appearance.colors.colLayer3; border.width: 1; border.color: Appearance.colors.colOutlineVariant
                                Rectangle { width: parent.width; height: 13; radius: 4; color: Appearance.colors.colLayer2
                                    Rectangle { x: 4; anchors.verticalCenter: parent.verticalCenter; width: 5; height: 5; radius: 3; color: Appearance.colors.colSubtext; opacity: 0.4 }
                                }
                                Column { x: 6; y: 18; spacing: 4
                                    Repeater { model: [50,38,52,34]; Rectangle { width: modelData; height: 5; radius: 2; color: Appearance.colors.colSubtext; opacity: 0.3 } }
                                }
                                Rectangle { x: parent.width-7; y: 13; width: 4; height: parent.height-13; radius: 2; color: Appearance.colors.colLayer2
                                    Rectangle { width: 4; height: 18; radius: 2; y: 2; color: !root.naturalScrollTP ? Appearance.colors.colPrimary : Appearance.colors.colSubtext; opacity: 0.7 }
                                }
                                MaterialSymbol { anchors.horizontalCenter: parent.horizontalCenter; y: 44; text: "arrow_upward"; iconSize: 18; color: !root.naturalScrollTP ? Appearance.colors.colPrimary : Appearance.colors.colSubtext; opacity: 0.7 }
                            }
                            Rectangle { x: 100; y: 12; width: 28; height: 52; radius: 14
                                color: !root.naturalScrollTP ? Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.18) : Appearance.colors.colLayer3
                                border.width: 1; border.color: !root.naturalScrollTP ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                                Rectangle { x: 13; y: 0; width: 1; height: 22; color: Appearance.colors.colOutlineVariant }
                                Rectangle { anchors.horizontalCenter: parent.horizontalCenter; y: 7; width: 5; height: 14; radius: 3; color: Appearance.colors.colSubtext; opacity: 0.6 }
                            }
                            MaterialSymbol { x: 107; y: 68; text: "arrow_upward"; iconSize: 16; color: !root.naturalScrollTP ? Appearance.colors.colPrimary : Appearance.colors.colSubtext }
                        }
                        RowLayout {
                            spacing: 6; Layout.alignment: Qt.AlignHCenter
                            Rectangle {
                                width: 16; height: 16; radius: 8; border.width: 2
                                border.color: !root.naturalScrollTP ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                                color: !root.naturalScrollTP ? Appearance.colors.colPrimary : "transparent"
                                Rectangle { anchors.centerIn: parent; width: 6; height: 6; radius: 3; color: Appearance.colors.colOnPrimary; visible: !root.naturalScrollTP }
                            }
                            ColumnLayout {
                                spacing: 1
                                StyledText { text: Translation.tr("Traditional"); font.pixelSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colOnLayer1 }
                                StyledText { text: Translation.tr("Scrolling moves the view"); font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colSubtext }
                            }
                        }
                    }
                }
                MouseArea {
                    cursorShape: Qt.PointingHandCursor
                    implicitWidth: childrenRect.width; implicitHeight: childrenRect.height
                    onClicked: { root.naturalScrollTP = true; root.applyTouchpadInput(1) }
                    ColumnLayout {
                        spacing: 6
                        Rectangle {
                            implicitWidth: 150; implicitHeight: 120
                            radius: Appearance.rounding.normal
                            color: root.naturalScrollTP ? Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.1) : Appearance.colors.colLayer2
                            border.width: root.naturalScrollTP ? 2 : 1
                            border.color: root.naturalScrollTP ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                            MouseArea { anchors.fill: parent; z: 1; cursorShape: Qt.PointingHandCursor; onClicked: { root.naturalScrollTP = true; root.applyTouchpadInput(1) } }
                            Rectangle {
                                x: 12; y: 12; width: 76; height: 84; radius: 4
                                color: Appearance.colors.colLayer3; border.width: 1; border.color: Appearance.colors.colOutlineVariant
                                Rectangle { width: parent.width; height: 13; radius: 4; color: Appearance.colors.colLayer2
                                    Rectangle { x: 4; anchors.verticalCenter: parent.verticalCenter; width: 5; height: 5; radius: 3; color: Appearance.colors.colSubtext; opacity: 0.4 }
                                }
                                Column { x: 6; y: 18; spacing: 4
                                    Repeater { model: [50,38,52,34]; Rectangle { width: modelData; height: 5; radius: 2; color: Appearance.colors.colSubtext; opacity: 0.3 } }
                                }
                                Rectangle { x: parent.width-7; y: 13; width: 4; height: parent.height-13; radius: 2; color: Appearance.colors.colLayer2
                                    Rectangle { width: 4; height: 18; radius: 2; y: 48; color: root.naturalScrollTP ? Appearance.colors.colPrimary : Appearance.colors.colSubtext; opacity: 0.7 }
                                }
                                MaterialSymbol { anchors.horizontalCenter: parent.horizontalCenter; y: 44; text: "arrow_downward"; iconSize: 18; color: root.naturalScrollTP ? Appearance.colors.colPrimary : Appearance.colors.colSubtext; opacity: 0.7 }
                            }
                            Rectangle { x: 100; y: 12; width: 28; height: 52; radius: 14
                                color: root.naturalScrollTP ? Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.18) : Appearance.colors.colLayer3
                                border.width: 1; border.color: root.naturalScrollTP ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                                Rectangle { x: 13; y: 0; width: 1; height: 22; color: Appearance.colors.colOutlineVariant }
                                Rectangle { anchors.horizontalCenter: parent.horizontalCenter; y: 7; width: 5; height: 14; radius: 3; color: Appearance.colors.colSubtext; opacity: 0.6 }
                            }
                            MaterialSymbol { x: 107; y: 68; text: "arrow_downward"; iconSize: 16; color: root.naturalScrollTP ? Appearance.colors.colPrimary : Appearance.colors.colSubtext }
                        }
                        RowLayout {
                            spacing: 6; Layout.alignment: Qt.AlignHCenter
                            Rectangle {
                                width: 16; height: 16; radius: 8; border.width: 2
                                border.color: root.naturalScrollTP ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                                color: root.naturalScrollTP ? Appearance.colors.colPrimary : "transparent"
                                Rectangle { anchors.centerIn: parent; width: 6; height: 6; radius: 3; color: Appearance.colors.colOnPrimary; visible: root.naturalScrollTP }
                            }
                            ColumnLayout {
                                spacing: 1
                                StyledText { text: Translation.tr("Natural"); font.pixelSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colOnLayer1 }
                                StyledText { text: Translation.tr("Scrolling moves the content"); font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colSubtext }
                            }
                        }
                    }
                }
            }
        }
    }
}
