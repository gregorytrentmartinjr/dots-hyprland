import qs.services
import qs.modules.common
import qs.modules.common.widgets
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Item {
    id: root

    implicitHeight: contentColumn.implicitHeight
    implicitWidth: contentColumn.implicitWidth

    ColumnLayout {
        id: contentColumn
        anchors.fill: parent
        spacing: 0

        // The Pomodoro timer circle
        CircularProgress {
            Layout.alignment: Qt.AlignHCenter
            lineWidth: 8
            value: {
                return TimerService.pomodoroSecondsLeft / TimerService.pomodoroLapDuration;
            }
            implicitSize: 200
            enableAnimation: true

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 0

                Item {
                    id: timeItem
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 120
                    implicitHeight: 50

                    property bool editMode: false

                    function applyEdit() {
                        editMode = false;
                        let raw = timeField.text.replace(/[^0-9:]/g, "");
                        let parts = raw.split(":");
                        let newSeconds = 0;
                        if (parts.length >= 2) {
                            newSeconds = (parseInt(parts[0]) || 0) * 60 + (parseInt(parts[1]) || 0);
                        } else {
                            newSeconds = parseInt(parts[0]) || 0;
                        }
                        let delta = newSeconds - TimerService.pomodoroSecondsLeft;
                        TimerService.adjustPomodoroTime(delta);
                    }

                    StyledText {
                        visible: !timeItem.editMode
                        anchors.centerIn: parent
                        text: {
                            let minutes = Math.floor(TimerService.pomodoroSecondsLeft / 60).toString().padStart(2, '0');
                            let seconds = Math.floor(TimerService.pomodoroSecondsLeft % 60).toString().padStart(2, '0');
                            return `${minutes}:${seconds}`;
                        }
                        font.pixelSize: 40
                        color: Appearance.m3colors.m3onSurface
                    }

                    MouseArea {
                        anchors.fill: parent
                        visible: !timeItem.editMode
                        cursorShape: Qt.IBeamCursor
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton

                        onClicked: (mouse) => {
                            if (mouse.button === Qt.MiddleButton) {
                                if (mouse.modifiers & Qt.ShiftModifier) {
                                    TimerService.adjustPomodoroTime(-600);
                                } else {
                                    TimerService.adjustPomodoroTime(600);
                                }
                            } else if (mouse.button === Qt.LeftButton) {
                                let minutes = Math.floor(TimerService.pomodoroSecondsLeft / 60).toString().padStart(2, '0');
                                let seconds = Math.floor(TimerService.pomodoroSecondsLeft % 60).toString().padStart(2, '0');
                                timeField.text = `${minutes}:${seconds}`;
                                timeItem.editMode = true;
                                timeField.forceActiveFocus();
                                timeField.selectAll();
                            }
                        }
                    }

                    StyledTextInput {
                        id: timeField
                        visible: timeItem.editMode
                        anchors.centerIn: parent
                        width: parent.width
                        horizontalAlignment: TextInput.AlignHCenter
                        font.pixelSize: 40
                        font.hintingPreference: Font.PreferDefaultHinting
                        renderType: Text.NativeRendering
                        color: Appearance.m3colors.m3onSurface

                        Keys.onReturnPressed: timeItem.applyEdit()
                        Keys.onEnterPressed: timeItem.applyEdit()
                        Keys.onEscapePressed: timeItem.editMode = false

                        onActiveFocusChanged: {
                            if (!activeFocus && timeItem.editMode)
                                timeItem.applyEdit();
                        }
                    }
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: TimerService.pomodoroLongBreak ? Translation.tr("Long break") : TimerService.pomodoroBreak ? Translation.tr("Break") : Translation.tr("Focus")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colSubtext
                }
            }

            Rectangle {
                radius: Appearance.rounding.full
                color: Appearance.colors.colLayer2
                
                anchors {
                    right: parent.right
                    bottom: parent.bottom
                }
                implicitWidth: 36
                implicitHeight: implicitWidth

                StyledText {
                    id: cycleText
                    anchors.centerIn: parent
                    color: Appearance.colors.colOnLayer2
                    text: TimerService.pomodoroCycle + 1
                }
            }
        }

        // The Start/Stop and Reset buttons
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 10

            RippleButton {
                contentItem: StyledText {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: TimerService.pomodoroRunning ? Translation.tr("Pause") : (TimerService.pomodoroSecondsLeft === TimerService.pomodoroLapDuration) ? Translation.tr("Start") : Translation.tr("Resume")
                    color: TimerService.pomodoroRunning ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnPrimary
                }
                implicitHeight: 35
                implicitWidth: 90
                font.pixelSize: Appearance.font.pixelSize.larger
                onClicked: TimerService.togglePomodoro()
                colBackground: TimerService.pomodoroRunning ? Appearance.colors.colSecondaryContainer : Appearance.colors.colPrimary
                colBackgroundHover: TimerService.pomodoroRunning ? Appearance.colors.colSecondaryContainer : Appearance.colors.colPrimary
            }

            RippleButton {
                implicitHeight: 35
                implicitWidth: 90

                onClicked: TimerService.resetPomodoro()
                enabled: (TimerService.pomodoroSecondsLeft < TimerService.pomodoroLapDuration) || TimerService.pomodoroCycle > 0 || TimerService.pomodoroBreak

                font.pixelSize: Appearance.font.pixelSize.larger
                colBackground: Appearance.colors.colErrorContainer
                colBackgroundHover: Appearance.colors.colErrorContainerHover
                colRipple: Appearance.colors.colErrorContainerActive

                contentItem: StyledText {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: Translation.tr("Reset")
                    color: Appearance.colors.colOnErrorContainer
                }
            }
        }
    }
}
