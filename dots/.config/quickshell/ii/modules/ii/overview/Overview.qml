import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import Qt.labs.synchronizer
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: overviewScope
    property bool dontAutoCancelSearch: false

    PanelWindow {
        id: panelWindow
        property string searchingText: ""
        readonly property HyprlandMonitor monitor: Hyprland.monitorFor(panelWindow.screen)
        property bool monitorIsFocused: (Hyprland.focusedMonitor?.id == monitor?.id)
        // Stay visible during fade-out; hideTimer cuts visibility after animation
        visible: GlobalStates.overviewOpen || contentFade.opacity > 0

        WlrLayershell.namespace: "quickshell:overview"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: GlobalStates.overviewOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        color: "transparent"

        // Full-screen so the dim overlay covers app windows behind the overview.
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        Connections {
            target: GlobalStates
            function onOverviewOpenChanged() {
                if (!GlobalStates.overviewOpen) {
                    searchWidget.disableExpandAnimation();
                    overviewScope.dontAutoCancelSearch = false;
                    // Reset drawer state
                    appDrawer.expanded = false;
                    appDrawer.searchText = "";
                    flickable.contentY = 0;
                    GlobalFocusGrab.dismiss();
                } else {
                    if (!overviewScope.dontAutoCancelSearch) {
                        searchWidget.cancelSearch();
                    }
                    // Reset drawer state on open
                    appDrawer.expanded = false;
                    appDrawer.searchText = "";
                    GlobalFocusGrab.addDismissable(panelWindow);
                }
            }
        }

        Connections {
            target: GlobalFocusGrab
            function onDismissed() {
                GlobalStates.overviewOpen = false;
            }
        }
        function setSearchingText(text) {
            searchWidget.setSearchingText(text);
            searchWidget.focusFirstItem();
        }

        // Wraps all content so a single opacity animation fades everything together
        Item {
            id: contentFade
            anchors.fill: parent
            opacity: GlobalStates.overviewOpen ? 1 : 0
            Behavior on opacity {
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }

            // Full-screen dim overlay — fixed opacity; contentFade handles the fade
            Rectangle {
                anchors.fill: parent
                color: Appearance.colors.colLayer0
                opacity: 0.90
            }

        StyledFlickable {
            id: flickable
            anchors.fill: parent
            contentWidth: columnLayout.implicitWidth
            contentHeight: columnLayout.implicitHeight
            clip: true
            visible: true
            // DragAndOvershootBounds lets a touch drag overshoot past the top
            // (contentY < 0), which we use as a fallback collapse trigger.
            boundsBehavior: Flickable.DragAndOvershootBounds

            onContentYChanged: {
                // Drag-overshoot past the top while expanded → collapse.
                // Wheel-based collapse is handled by wheelOverlay below.
                if (appDrawer.expanded && contentY < -30) {
                    appDrawer.expanded = false;
                    appDrawer.searchText = "";
                    Qt.callLater(() => { flickable.contentY = 0; });
                }
            }
            
            ColumnLayout {
                id: columnLayout
                width: flickable.width
                spacing: 20
                property real cachedOverviewWidth: Math.min(1200, flickable.width - 40)

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        if (appDrawer.expanded) {
                            appDrawer.expanded = false;
                            appDrawer.searchText = "";
                            Qt.callLater(() => { flickable.contentY = 0; });
                            columnLayout.forceActiveFocus();
                        } else {
                            GlobalStates.overviewOpen = false;
                        }
                    } else if (event.key === Qt.Key_Left) {
                        if (!panelWindow.searchingText)
                            Hyprland.dispatch("workspace r-1");
                    } else if (event.key === Qt.Key_Right) {
                        if (!panelWindow.searchingText)
                            Hyprland.dispatch("workspace r+1");
                    }
                }
                    
                // Spacer to prevent drawer from overlapping top bar when expanded
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: appDrawer.expanded ? 10 : 0
                    visible: appDrawer.expanded
                    
                    Behavior on Layout.preferredHeight {
                        NumberAnimation {
                            duration: Appearance.animation.elementResize.duration
                            easing.type: Appearance.animation.elementResize.type
                            easing.bezierCurve: Appearance.animation.elementResize.bezierCurve
                        }
                    }
                }

                SearchWidget {
                    id: searchWidget
                    anchors.horizontalCenter: parent.horizontalCenter
                    Layout.alignment: Qt.AlignHCenter
                    visible: !appDrawer.expanded
                    Layout.maximumHeight: appDrawer.expanded ? 0 : implicitHeight
                    opacity: appDrawer.expanded ? 0 : 1
                    Behavior on opacity {
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Appearance.animation.elementMoveFast.type
                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                        }
                    }
                    Behavior on Layout.maximumHeight {
                        NumberAnimation {
                            duration: Appearance.animation.elementResize.duration
                            easing.type: Appearance.animation.elementResize.type
                            easing.bezierCurve: Appearance.animation.elementResize.bezierCurve
                        }
                    }
                    Synchronizer on searchingText {
                        property alias source: panelWindow.searchingText
                    }
                }

                Loader {
                    id: overviewLoader
                    Layout.alignment: Qt.AlignHCenter
                    anchors.horizontalCenter: parent.horizontalCenter
                    active: GlobalStates.overviewOpen && (Config?.options.overview.enable ?? true) && !appDrawer.expanded
                    Layout.maximumHeight: appDrawer.expanded ? 0 : (item ? item.implicitHeight : 0)
                    opacity: appDrawer.expanded ? 0 : 1
                    Behavior on opacity {
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Appearance.animation.elementMoveFast.type
                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                        }
                    }
                    Behavior on Layout.maximumHeight {
                        NumberAnimation {
                            duration: Appearance.animation.elementResize.duration
                            easing.type: Appearance.animation.elementResize.type
                            easing.bezierCurve: Appearance.animation.elementResize.bezierCurve
                        }
                    }
                    // Cache width so the drawer can match it after this loader deactivates
                    onWidthChanged: if (width > 0) columnLayout.cachedOverviewWidth = width
                    sourceComponent: OverviewWidget {
                        screen: panelWindow.screen
                        visible: (panelWindow.searchingText == "")
                    }
                }
                    
                ApplicationDrawer {
                    id: appDrawer
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: false
                    Layout.preferredWidth: appDrawer.expanded
                        ? columnLayout.cachedOverviewWidth
                        : Math.min(1200, flickable.width - 40)
                    visible: (panelWindow.searchingText == "")
                    // But hide it when searching and not expanded (search results take priority)
                    opacity: (panelWindow.searchingText != "" && !appDrawer.expanded) ? 0 : 1
                    Layout.maximumHeight: (panelWindow.searchingText != "" && !appDrawer.expanded) ? 0 : implicitHeight
                        
                    Behavior on opacity {
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Appearance.animation.elementMoveFast.type
                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                        }
                    }
                    Behavior on Layout.maximumHeight {
                        NumberAnimation {
                            duration: Appearance.animation.elementResize.duration
                            easing.type: Appearance.animation.elementResize.type
                            easing.bezierCurve: Appearance.animation.elementResize.bezierCurve
                        }
                    }
                    
                    availableHeight: flickable.height
                    availableWidth: appDrawer.expanded
                        ? columnLayout.cachedOverviewWidth
                        : Math.min(1200, flickable.width - 40)
                }
            }
        }

        // ── Wheel-event interceptor ──────────────────────────────────────────
        // Sits at z:100 — above the StyledFlickable and all its descendants,
        // including StyledFlickable's inner MouseArea (which would otherwise
        // consume every wheel event). Qt hit-tests siblings by z-order, so
        // this MouseArea is evaluated first.
        //
        //  acceptedButtons: Qt.NoButton  — mouse presses pass through to lower-z
        //                                  items (app icon buttons, etc.)
        //  propagateComposedEvents: true — click/release also fall through
        //
        //  Scroll DOWN while collapsed     → expand drawer
        //  Scroll UP  at grid+outer top    → collapse drawer
        //  Otherwise                       → scroll grid (expanded)
        //                                    or outer flickable (collapsed)
        MouseArea {
            id: wheelOverlay
            anchors.fill: flickable
            z: 100
            enabled: GlobalStates.overviewOpen
            acceptedButtons: Qt.NoButton
            propagateComposedEvents: true

            onWheel: function(event) {
                const scrollingDown = event.angleDelta.y < 0;
                const scrollingUp   = event.angleDelta.y > 0;

                if (!appDrawer.expanded && scrollingDown && panelWindow.searchingText === "") {
                    appDrawer.expanded = true;
                    flickable.contentY = 0;
                    event.accepted = true;
                    return;
                }

                if (appDrawer.expanded && scrollingUp
                        && flickable.scrollTargetY <= 0
                        && appDrawer.isGridAtTop()) {
                    appDrawer.expanded = false;
                    appDrawer.searchText = "";
                    Qt.callLater(() => { flickable.contentY = 0; });
                    columnLayout.forceActiveFocus();
                    event.accepted = true;
                    return;
                }

                const threshold    = flickable.mouseScrollDeltaThreshold;
                const delta        = event.angleDelta.y / threshold;
                const scrollFactor = Math.abs(event.angleDelta.y) >= threshold
                                     ? flickable.mouseScrollFactor
                                     : flickable.touchpadScrollFactor;

                if (appDrawer.expanded) {
                    appDrawer.scrollGrid(delta, scrollFactor);
                } else {
                    const maxY    = Math.max(0, flickable.contentHeight - flickable.height);
                    const targetY = Math.max(0, Math.min(
                        flickable.scrollTargetY - delta * scrollFactor, maxY));
                    flickable.scrollTargetY = targetY;
                    flickable.contentY      = targetY;
                }
                event.accepted = true;
            }
        }

        }   // end contentFade

    }   // end PanelWindow

    function toggleClipboard() {
        if (GlobalStates.overviewOpen && overviewScope.dontAutoCancelSearch) {
            GlobalStates.overviewOpen = false;
            return;
        }
        overviewScope.dontAutoCancelSearch = true;
        panelWindow.setSearchingText(Config.options.search.prefix.clipboard);
        GlobalStates.overviewOpen = true;
    }

    function toggleEmojis() {
        if (GlobalStates.overviewOpen && overviewScope.dontAutoCancelSearch) {
            GlobalStates.overviewOpen = false;
            return;
        }
        overviewScope.dontAutoCancelSearch = true;
        panelWindow.setSearchingText(Config.options.search.prefix.emojis);
        GlobalStates.overviewOpen = true;
    }

    IpcHandler {
        target: "search"

        function toggle() {
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
        function workspacesToggle() {
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
        function close() {
            GlobalStates.overviewOpen = false;
        }
        function open() {
            GlobalStates.overviewOpen = true;
        }
        function toggleReleaseInterrupt() {
            GlobalStates.superReleaseMightTrigger = false;
        }
        function clipboardToggle() {
            overviewScope.toggleClipboard();
        }
    }

    GlobalShortcut {
        name: "searchToggle"
        description: "Toggles search on press"

        onPressed: {
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
    }
    GlobalShortcut {
        name: "overviewWorkspacesClose"
        description: "Closes overview on press"

        onPressed: {
            GlobalStates.overviewOpen = false;
        }
    }
    GlobalShortcut {
        name: "overviewWorkspacesToggle"
        description: "Toggles overview on press"

        onPressed: {
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
    }
    GlobalShortcut {
        name: "searchToggleRelease"
        description: "Toggles search on release"

        onPressed: {
            GlobalStates.superReleaseMightTrigger = true;
        }

        onReleased: {
            if (!GlobalStates.superReleaseMightTrigger) {
                GlobalStates.superReleaseMightTrigger = true;
                return;
            }
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
    }
    GlobalShortcut {
        name: "searchToggleReleaseInterrupt"
        description: "Interrupts possibility of search being toggled on release. " + "This is necessary because GlobalShortcut.onReleased in quickshell triggers whether or not you press something else while holding the key. " + "To make sure this works consistently, use binditn = MODKEYS, catchall in an automatically triggered submap that includes everything."

        onPressed: {
            GlobalStates.superReleaseMightTrigger = false;
        }
    }
    GlobalShortcut {
        name: "overviewClipboardToggle"
        description: "Toggle clipboard query on overview widget"

        onPressed: {
            overviewScope.toggleClipboard();
        }
    }

    GlobalShortcut {
        name: "overviewEmojiToggle"
        description: "Toggle emoji query on overview widget"

        onPressed: {
            overviewScope.toggleEmojis();
        }
    }
}
