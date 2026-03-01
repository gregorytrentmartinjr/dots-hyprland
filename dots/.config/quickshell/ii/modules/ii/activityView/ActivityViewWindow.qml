pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Item {
    id: root

    required property var toplevel
    required property real maxHeight
    required property real maxWidth

    property var hyprlandClient: HyprlandData.clientForToplevel(root.toplevel)
    property string address: hyprlandClient?.address ?? ""
    property string iconName: AppSearch.guessIcon(hyprlandClient?.class)
    property string iconPath: Quickshell.iconPath(iconName, "image-missing")

    // Scale the window to fit within bounds while preserving aspect ratio
    property real clientWidth: hyprlandClient?.size[0] ?? maxWidth
    property real clientHeight: hyprlandClient?.size[1] ?? maxHeight
    property real scaleX: maxWidth / clientWidth
    property real scaleY: maxHeight / clientHeight
    property real fitScale: Math.min(scaleX, scaleY)
    property real scaledWidth: clientWidth * fitScale
    property real scaledHeight: clientHeight * fitScale

    property bool hovered: mouseArea.containsMouse

    implicitWidth: scaledWidth
    implicitHeight: scaledHeight + iconRow.height + 8

    scale: mouseArea.containsPress ? 0.96 : 1
    Behavior on scale {
        NumberAnimation {
            duration: 150
            easing.type: Easing.OutCubic
        }
    }

    // Background mouse area — declared first so it sits underneath everything
    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: event => {
            if (event.button === Qt.MiddleButton) {
                Hyprland.dispatch(`closewindow address:${root.hyprlandClient?.address}`);
            } else {
                GlobalStates.activityViewOpen = false;
                Hyprland.dispatch(`focuswindow address:${root.hyprlandClient?.address}`);
            }
        }
    }

    // Window preview card (clipped content)
    Item {
        id: previewCard
        anchors {
            top: parent.top
            horizontalCenter: parent.horizontalCenter
        }
        width: root.scaledWidth
        height: root.scaledHeight

        // Clipped inner content (screenshot + hover overlay)
        Rectangle {
            id: previewClipped
            anchors.fill: parent
            radius: Appearance.rounding.large
            color: Appearance.colors.colSurfaceContainerLow

            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: previewClipped.width
                    height: previewClipped.height
                    radius: previewClipped.radius
                }
            }

            ScreencopyView {
                anchors.fill: parent
                captureSource: GlobalStates.activityViewOpen ? root.toplevel : null
                live: true
            }

            // Semi-transparent overlay (matches regular overview windows)
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: mouseArea.containsPress
                    ? ColorUtils.transparentize(Appearance.colors.colLayer2Active, 0.5)
                    : root.hovered
                        ? ColorUtils.transparentize(Appearance.colors.colLayer2Hover, 0.7)
                        : ColorUtils.transparentize(Appearance.colors.colLayer2)
            }
        }

        // Border outline (outside the mask so it's not clipped)
        Rectangle {
            anchors.fill: parent
            radius: Appearance.rounding.large
            color: "transparent"
            border.color: ColorUtils.transparentize(Appearance.m3colors.m3outline, 0.88)
            border.width: 1
        }

        // Close button — on top of previewCard and above mouseArea
        Rectangle {
            id: closeButton
            anchors {
                top: parent.top
                right: parent.right
                margins: 8
            }
            width: 28
            height: 28
            radius: Appearance.rounding.full
            color: closeArea.containsPress
                ? Appearance.colors.colError
                : closeArea.containsMouse
                    ? ColorUtils.transparentize(Appearance.colors.colError, 0.3)
                    : ColorUtils.transparentize(Appearance.colors.colOnSurface, 0.3)
            visible: root.hovered
            opacity: root.hovered ? 1 : 0

            Behavior on opacity {
                NumberAnimation { duration: 150 }
            }

            MaterialSymbol {
                anchors.centerIn: parent
                text: "close"
                iconSize: 16
                color: closeArea.containsMouse
                    ? Appearance.colors.colOnError
                    : Appearance.colors.colOnSurface
            }

            MouseArea {
                id: closeArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    Hyprland.dispatch(`closewindow address:${root.hyprlandClient?.address}`);
                }
            }
        }
    }

    // App icon below the preview
    Row {
        id: iconRow
        anchors {
            top: previewCard.bottom
            topMargin: 8
            horizontalCenter: parent.horizontalCenter
        }
        spacing: 6

        Image {
            id: appIcon
            width: 24
            height: 24
            source: root.iconPath
            sourceSize: Qt.size(24, 24)
            anchors.verticalCenter: parent.verticalCenter
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: root.hyprlandClient?.title ?? ""
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnSurface
            elide: Text.ElideRight
            width: Math.min(implicitWidth, root.scaledWidth - appIcon.width - 6)
            opacity: root.hovered ? 1 : 0.7

            Behavior on opacity {
                NumberAnimation { duration: 150 }
            }
        }
    }
}
