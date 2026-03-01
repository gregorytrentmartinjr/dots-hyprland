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

    readonly property list<var> toplevels: ToplevelManager.toplevels.values.filter(t => {
        const client = HyprlandData.clientForToplevel(t);
        return client && client.workspace.id === HyprlandData.activeWorkspace?.id;
    })

    // Arrange toplevels into rows that fit the available width
    readonly property list<var> arrangedToplevels: {
        const maxRowWidth = width - contentPadding * 2;
        const count = toplevels.length;
        const result = [];
        var i = 0;
        while (i < count) {
            var row = [];
            var rowWidth = 0;
            var j = i;
            while (j < count) {
                const toplevel = toplevels[j];
                const client = HyprlandData.clientForToplevel(toplevel);
                if (!client) { j++; continue; }
                const cw = client.size[0];
                const ch = client.size[1];
                const s = Math.min(maxWindowWidth / cw, maxWindowHeight / ch);
                const scaledW = cw * s;
                if (rowWidth + scaledW + (row.length > 0 ? windowSpacing : 0) <= maxRowWidth || row.length === 0) {
                    row.push(toplevel);
                    rowWidth += scaledW + (row.length > 1 ? windowSpacing : 0);
                    j++;
                } else {
                    break;
                }
            }
            result.push(row);
            i = j;
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

    // Window grid
    Flickable {
        id: windowFlickable
        anchors.fill: parent
        contentWidth: width
        contentHeight: windowColumn.implicitHeight + root.contentPadding * 2
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: windowColumn
            anchors {
                top: parent.top
                topMargin: root.contentPadding
                horizontalCenter: parent.horizontalCenter
            }
            spacing: root.windowSpacing

            opacity: root.openProgress
            scale: 0.92 + 0.08 * root.openProgress
            transformOrigin: Item.Center

            Behavior on opacity {
                NumberAnimation { duration: 200 }
            }

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
}
