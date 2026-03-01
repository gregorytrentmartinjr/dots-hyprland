pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.models
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Rectangle {
    id: root

    color: "transparent"
    property real openProgress: 0
    signal closed

    Component.onCompleted: openAnim.start()

    function close() {
        closeAnim.start();
    }

    PropertyAnimation {
        id: openAnim
        target: root
        property: "openProgress"
        to: 1
        duration: 250
        easing.type: Easing.OutCubic
    }

    SequentialAnimation {
        id: closeAnim
        PropertyAnimation {
            target: root
            property: "openProgress"
            to: 0
            duration: 200
            easing.type: Easing.InCubic
        }
        ScriptAction {
            script: root.closed()
        }
    }

    // Window layout constants
    property real maxWindowHeight: 280
    property real maxWindowWidth: 420
    property real contentPadding: 60
    property real windowSpacing: 30
    property int maxPerRow: 4

    readonly property list<var> toplevels: ToplevelManager.toplevels.values.filter(t => {
        const client = HyprlandData.clientForToplevel(t);
        return client && client.workspace.id === HyprlandData.activeWorkspace?.id;
    })

    // Arrange toplevels into rows of at most maxPerRow
    readonly property list<var> arrangedToplevels: {
        const count = toplevels.length;
        const result = [];
        for (var i = 0; i < count; i += maxPerRow) {
            result.push(toplevels.slice(i, Math.min(i + maxPerRow, count)));
        }
        return result;
    }

    // Click background to dismiss
    MouseArea {
        anchors.fill: parent
        onClicked: GlobalStates.activityViewOpen = false
    }

    // Dim background
    Rectangle {
        anchors.fill: parent
        color: Appearance.colors.colLayer0
        opacity: 0.85 * root.openProgress
    }

    // "No windows" message
    StyledText {
        anchors.centerIn: parent
        visible: root.toplevels.length === 0
        text: Translation.tr("No windows on this workspace")
        font.pixelSize: Appearance.font.pixelSize.larger
        color: ColorUtils.transparentize(Appearance.colors.colOnSurface, 0.5)
        opacity: root.openProgress
    }

    // Window grid - centered on screen
    Column {
        id: windowColumn
        anchors.centerIn: parent
        spacing: root.windowSpacing

        opacity: root.openProgress
        scale: 0.92 + 0.08 * root.openProgress
        transformOrigin: Item.Center

        Repeater {
            model: ScriptModel {
                values: root.arrangedToplevels
            }
            delegate: Row {
                id: clientRow
                required property var modelData
                spacing: root.windowSpacing
                anchors.horizontalCenter: parent?.horizontalCenter ?? undefined

                Repeater {
                    model: ScriptModel {
                        values: clientRow.modelData
                    }
                    delegate: ActivityViewWindow {
                        required property var modelData
                        toplevel: modelData
                        maxHeight: root.maxWindowHeight
                        maxWidth: root.maxWindowWidth
                    }
                }
            }
        }
    }
}
