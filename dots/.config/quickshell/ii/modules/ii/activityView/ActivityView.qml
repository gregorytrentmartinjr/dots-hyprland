import qs
import qs.services
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: activityViewScope

    Loader {
        id: panelLoader
        active: false

        Connections {
            target: GlobalStates
            function onActivityViewOpenChanged() {
                if (GlobalStates.activityViewOpen)
                    panelLoader.active = true;
            }
        }

        sourceComponent: PanelWindow {
            id: panelWindow
            readonly property HyprlandMonitor monitor: Hyprland.monitorFor(panelWindow.screen)

            WlrLayershell.namespace: "quickshell:activityView"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            exclusionMode: ExclusionMode.Ignore
            color: Qt.rgba(0, 0, 0, 0.01)

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            ActivityViewContent {
                id: activityViewContent
                anchors.fill: parent
                screen: panelWindow.screen

                Component.onCompleted: {
                    activityViewContent.forceActiveFocus();
                }

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        GlobalStates.activityViewOpen = false;
                    }
                }

                Connections {
                    target: GlobalStates
                    function onActivityViewOpenChanged() {
                        if (!GlobalStates.activityViewOpen)
                            activityViewContent.close();
                    }
                    function onOverviewOpenChanged() {
                        if (GlobalStates.overviewOpen)
                            GlobalStates.activityViewOpen = false;
                    }
                }
                onClosed: panelLoader.active = false
            }
        }
    }

    GlobalShortcut {
        name: "activityViewToggle"
        description: "Toggle activities overview"

        onPressed: {
            GlobalStates.activityViewOpen = !GlobalStates.activityViewOpen;
        }
    }
}
