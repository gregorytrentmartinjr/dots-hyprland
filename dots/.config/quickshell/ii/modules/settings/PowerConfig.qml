import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions as CF
import qs.modules.common.widgets

ContentPage {
    forceWidth: true

    property string powerProfile: "balanced"
    property string powerButtonAction: "suspend"
    property bool screenBlankEnabled: true
    property int screenBlankSecs: 300
    property bool autoSuspendEnabled: true
    property int autoSuspendSecs: 900

    readonly property string hyprIdleConf: `${CF.FileUtils.trimFileProtocol(Directories.config)}/hypr/hypridle.conf`

    Component.onCompleted: {
        powerProfileReader.running = true
        powerButtonReader.running = true
        screenBlankReader.running = true
        autoSuspendActionReader.running = true
        autoSuspendSecReader.running = true
    }

    // ── Readers ──────────────────────────────────────────────────────────────

    Process {
        id: powerProfileReader
        command: ["powerprofilesctl", "get"]
        onExited: (code) => {
            if (code === 0) {
                const v = stdout.trim()
                if (["performance", "balanced", "power-saver"].includes(v))
                    powerProfile = v
            }
        }
    }

    // Read HandlePowerKey from logind drop-in
    Process {
        id: powerButtonReader
        command: ["bash", "-c",
            "grep -h 'HandlePowerKey' /etc/systemd/logind.conf.d/10-power-key.conf 2>/dev/null | cut -d= -f2 | tr -d '[:space:]'"]
        onExited: (code) => {
            const v = stdout.trim()
            if (v.length > 0) powerButtonAction = v
        }
    }

    // Read DPMS timeout from hypridle.conf (targets the listener containing dpms off)
    Process {
        id: screenBlankReader
        command: ["perl", "-0777", "-ne",
            "if (/timeout\\s*=\\s*(\\d+)[^\\n]*\\n[^\\n]*on-timeout[^\\n]*dpms off/) { print $1 }",
            hyprIdleConf]
        onExited: (code) => {
            const v = parseInt(stdout.trim())
            if (!isNaN(v)) {
                if (v === 0) {
                    screenBlankEnabled = false
                } else {
                    screenBlankEnabled = true
                    screenBlankSecs = v
                }
            }
        }
    }

    // Read IdleAction (enabled/disabled) from logind drop-in
    Process {
        id: autoSuspendActionReader
        command: ["bash", "-c",
            "grep -h '^IdleAction=' /etc/systemd/logind.conf.d/10-idle-action.conf 2>/dev/null | cut -d= -f2 | tr -d '[:space:]'"]
        onExited: (code) => {
            if (stdout.trim() === "ignore") autoSuspendEnabled = false
        }
    }

    // Read IdleActionSec from logind drop-in
    Process {
        id: autoSuspendSecReader
        command: ["bash", "-c",
            "grep -h 'IdleActionSec' /etc/systemd/logind.conf.d/10-idle-action.conf 2>/dev/null | cut -d= -f2 | tr -d '[:space:]'"]
        onExited: (code) => {
            const v = parseInt(stdout.trim())
            if (!isNaN(v) && v > 0) autoSuspendSecs = v
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    // Write HandlePowerKey to logind drop-in and reload
    function applyPowerButton(action) {
        Quickshell.execDetached(["pkexec", "bash", "-c",
            `mkdir -p /etc/systemd/logind.conf.d && printf '[Login]\\nHandlePowerKey=${action}\\n' > /etc/systemd/logind.conf.d/10-power-key.conf && systemctl kill -s HUP systemd-logind`
        ])
    }

    // Update timeout in-place in hypridle.conf, then restart hypridle
    // Requires a listener block with: on-timeout = hyprctl dispatch dpms off
    function applyScreenBlank(enabled, secs) {
        const timeout = enabled ? secs : 0
        Quickshell.execDetached(["bash", "-c",
            `perl -i -0777 -pe 's/(timeout\\s*=\\s*)\\d+([^\\n]*\\n[^\\n]*on-timeout[^\\n]*dpms off)/${1}${timeout}${2}/g' '${hyprIdleConf}' && pkill -x hypridle; hypridle &`
        ])
    }

    // Write IdleAction + IdleActionSec to logind drop-in and reload
    function applyAutoSuspend(enabled, secs) {
        const action = enabled ? "suspend" : "ignore"
        Quickshell.execDetached(["pkexec", "bash", "-c",
            `mkdir -p /etc/systemd/logind.conf.d && printf '[Login]\\nIdleAction=${action}\\nIdleActionSec=${secs}\\n' > /etc/systemd/logind.conf.d/10-idle-action.conf && systemctl kill -s HUP systemd-logind`
        ])
    }

    // ── Power Mode ────────────────────────────────────────────────────────────
    ContentSection {
        icon: "bolt"
        title: Translation.tr("Power Mode")

        ConfigRow {
            ConfigSelectionArray {
                currentValue: powerProfile
                onSelected: newValue => {
                    powerProfile = newValue
                    Quickshell.execDetached(["powerprofilesctl", "set", newValue])
                }
                options: [
                    { displayName: Translation.tr("Performance"), icon: "speed",        value: "performance" },
                    { displayName: Translation.tr("Balanced"),    icon: "balance",       value: "balanced"    },
                    { displayName: Translation.tr("Power Saver"), icon: "battery_saver", value: "power-saver" }
                ]
            }
        }
    }

    // ── General ───────────────────────────────────────────────────────────────
    ContentSection {
        icon: "settings_power"
        title: Translation.tr("General")

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            ColumnLayout {
                spacing: 4
                ContentSubsectionLabel { text: Translation.tr("Power Button Behavior") }
                StyledComboBox {
                    textRole: "displayName"
                    model: [
                        { displayName: Translation.tr("Suspend"),    value: "suspend"   },
                        { displayName: Translation.tr("Hibernate"),  value: "hibernate" },
                        { displayName: Translation.tr("Shut Down"),  value: "poweroff"  },
                        { displayName: Translation.tr("Do Nothing"), value: "ignore"    }
                    ]
                    currentIndex: {
                        const idx = model.findIndex(item => item.value === powerButtonAction)
                        return idx !== -1 ? idx : 0
                    }
                    onActivated: index => {
                        powerButtonAction = model[index].value
                        applyPowerButton(model[index].value)
                    }
                }
            }

            Item { Layout.fillWidth: true }
        }
    }

    // ── Power Saving ──────────────────────────────────────────────────────────
    ContentSection {
        icon: "battery_charging_full"
        title: Translation.tr("Power Saving")

        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            uniformCellSizes: true

            // Screen Blank column
            ColumnLayout {
                spacing: 4
                ConfigSwitch {
                    Layout.fillWidth: true
                    buttonIcon: "monitor"
                    text: Translation.tr("Automatic Screen Blank")
                    checked: screenBlankEnabled
                    onCheckedChanged: {
                        screenBlankEnabled = checked
                        applyScreenBlank(checked, screenBlankSecs)
                    }
                }
                ConfigRow {
                    enabled: screenBlankEnabled
                    StyledText {
                        text: Translation.tr("Delay")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: screenBlankEnabled ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                        Layout.fillWidth: true
                    }
                    StyledComboBox {
                        enabled: screenBlankEnabled
                        textRole: "displayName"
                        model: [
                            { displayName: Translation.tr("1 minute"),   seconds: 60   },
                            { displayName: Translation.tr("2 minutes"),  seconds: 120  },
                            { displayName: Translation.tr("5 minutes"),  seconds: 300  },
                            { displayName: Translation.tr("10 minutes"), seconds: 600  },
                            { displayName: Translation.tr("15 minutes"), seconds: 900  },
                            { displayName: Translation.tr("30 minutes"), seconds: 1800 }
                        ]
                        currentIndex: {
                            const idx = model.findIndex(item => item.seconds === screenBlankSecs)
                            return idx !== -1 ? idx : 2
                        }
                        onActivated: index => {
                            screenBlankSecs = model[index].seconds
                            applyScreenBlank(screenBlankEnabled, model[index].seconds)
                        }
                    }
                }
            }

            // Auto Suspend column
            ColumnLayout {
                spacing: 4
                ConfigSwitch {
                    Layout.fillWidth: true
                    buttonIcon: "bedtime"
                    text: Translation.tr("Automatic Suspend")
                    checked: autoSuspendEnabled
                    onCheckedChanged: {
                        autoSuspendEnabled = checked
                        applyAutoSuspend(checked, autoSuspendSecs)
                    }
                }
                ConfigRow {
                    enabled: autoSuspendEnabled
                    StyledText {
                        text: Translation.tr("Delay")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: autoSuspendEnabled ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                        Layout.fillWidth: true
                    }
                    StyledComboBox {
                        enabled: autoSuspendEnabled
                        textRole: "displayName"
                        model: [
                            { displayName: Translation.tr("5 minutes"),  seconds: 300  },
                            { displayName: Translation.tr("10 minutes"), seconds: 600  },
                            { displayName: Translation.tr("15 minutes"), seconds: 900  },
                            { displayName: Translation.tr("30 minutes"), seconds: 1800 },
                            { displayName: Translation.tr("1 hour"),     seconds: 3600 }
                        ]
                        currentIndex: {
                            const idx = model.findIndex(item => item.seconds === autoSuspendSecs)
                            return idx !== -1 ? idx : 2
                        }
                        onActivated: index => {
                            autoSuspendSecs = model[index].seconds
                            applyAutoSuspend(autoSuspendEnabled, model[index].seconds)
                        }
                    }
                }
            }
        }
    }

    // ── Battery ───────────────────────────────────────────────────────────────
    ContentSection {
        icon: "battery_android_full"
        title: Translation.tr("Battery")

        ConfigRow {
            uniform: true
            ConfigSpinBox {
                icon: "warning"
                text: Translation.tr("Low warning")
                value: Config.options.battery.low
                from: 0
                to: 100
                stepSize: 5
                onValueChanged: {
                    Config.options.battery.low = value
                }
            }
            ConfigSpinBox {
                icon: "dangerous"
                text: Translation.tr("Critical warning")
                value: Config.options.battery.critical
                from: 0
                to: 100
                stepSize: 5
                onValueChanged: {
                    Config.options.battery.critical = value
                }
            }
        }
        ConfigRow {
            uniform: false
            ConfigSwitch {
                buttonIcon: "pause"
                text: Translation.tr("Automatic suspend")
                checked: Config.options.battery.automaticSuspend
                onCheckedChanged: {
                    Config.options.battery.automaticSuspend = checked
                }
                StyledToolTip {
                    text: Translation.tr("Automatically suspends the system when battery is low")
                }
            }
            ConfigSpinBox {
                enabled: Config.options.battery.automaticSuspend
                text: Translation.tr("at")
                value: Config.options.battery.suspend
                from: 0
                to: 100
                stepSize: 5
                onValueChanged: {
                    Config.options.battery.suspend = value
                }
            }
        }
        ConfigRow {
            uniform: true
            ConfigSpinBox {
                icon: "charger"
                text: Translation.tr("Full warning")
                value: Config.options.battery.full
                from: 0
                to: 101
                stepSize: 5
                onValueChanged: {
                    Config.options.battery.full = value
                }
            }
        }
    }

    // ── Sounds ────────────────────────────────────────────────────────────────
    ContentSection {
        icon: "notification_sound"
        title: Translation.tr("Sounds")

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            ColumnLayout {
                spacing: 4
                ConfigSwitch {
                    Layout.fillWidth: true
                    buttonIcon: "battery_android_full"
                    text: Translation.tr("Battery")
                    checked: Config.options.sounds.battery
                    onCheckedChanged: {
                        Config.options.sounds.battery = checked
                    }
                }
            }

            Item { Layout.fillWidth: true }
        }
    }
}
