import qs.services
import qs.modules.common
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

DockButton {
    id: root
    property var appToplevel
    property var appListRoot
    property int delegateIndex: -1
    property int lastFocused: -1
    property real iconSize: 35
    property real countDotWidth: 10
    property real countDotHeight: 4
    property bool appIsActive: appToplevel.toplevels.find(t => (t.activated == true)) !== undefined

    readonly property bool isSeparator: appToplevel.appId === "SEPARATOR"
    property var desktopEntry: DesktopEntries.heuristicLookup(appToplevel.appId)

    Timer {
        // Retry looking up the desktop entry if it failed (e.g. database not loaded yet)
        property int retryCount: 5
        interval: 1000
        running: !root.isSeparator && root.desktopEntry === null && retryCount > 0
        repeat: true
        onTriggered: {
            retryCount--;
            root.desktopEntry = DesktopEntries.heuristicLookup(root.appToplevel.appId);
        }
    }

    // Drag-to-reorder
    readonly property bool isDragged: appListRoot.dragging && delegateIndex === appListRoot.dragSourceIndex
    readonly property real dragTranslateX: {
        if (!appListRoot.dragging) return 0;
        if (isDragged) return appListRoot.dragCursorX - appListRoot.dragStartCursorX;
        if (!appToplevel.pinned || isSeparator) return 0;
        var src = appListRoot.dragSourceIndex;
        var tgt = appListRoot.dragTargetIndex;
        var idx = delegateIndex;
        if (src < tgt && idx > src && idx <= tgt) return -appListRoot.slotWidth;
        if (src > tgt && idx >= tgt && idx < src) return appListRoot.slotWidth;
        return 0;
    }
    z: isDragged ? 100 : 0
    scale: isDragged ? 1.05 : 1

    enabled: !isSeparator
    property real hoverScale: 1.0
    property int buttonIndex: 0

    implicitWidth: isSeparator ? 1 : (implicitHeight - topInset - bottomInset)

    transform: Translate {
        x: root.dragTranslateX
        Behavior on x {
            enabled: !root.isDragged && !appListRoot._suppressTranslateAnim
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }

    Loader {
        active: isSeparator
        anchors {
            fill: parent
            topMargin: dockVisualBackground.margin + dockRow.padding + Appearance.rounding.normal
            bottomMargin: dockVisualBackground.margin + dockRow.padding + Appearance.rounding.normal
        }
        sourceComponent: DockSeparator {}
    }

    // Left-click overlay for all non-separator items.
    // Handles shift+click (context menu) and drag-to-reorder (pinned only).
    // Right/middle clicks fall through to the RippleButton's MouseArea.
    MouseArea {
        id: dragOverlay
        anchors.fill: parent
        z: 10
        enabled: !isSeparator
        acceptedButtons: Qt.LeftButton
        preventStealing: true
        property real pressX: 0
        property bool dragActive: false
        property bool shiftHeld: false

        onPressed: (event) => {
            if (event.modifiers & Qt.ShiftModifier) {
                shiftHeld = true;
                return; // Don't start ripple; open menu on release
            }
            shiftHeld = false;
            pressX = event.x;
            root.down = true;
            root.startRipple(event.x, event.y);
        }
        onPositionChanged: (event) => {
            if (!pressed || shiftHeld || !appToplevel.pinned) return;
            var dist = Math.abs(event.x - pressX);
            if (!dragActive && dist > 5) {
                dragActive = true;
                root.cancelRipple();
                root.down = false;
                appListRoot.buttonHovered = false;
                appListRoot.dragSourceIndex = root.delegateIndex;
                var mapped = mapToItem(appListRoot, event.x, event.y);
                appListRoot.dragStartCursorX = mapped.x;
                appListRoot.dragCursorX = mapped.x;
                appListRoot.slotWidth = root.width + 2;
                appListRoot.dragging = true;
            }
            if (dragActive) {
                var mapped = mapToItem(appListRoot, event.x, event.y);
                appListRoot.dragCursorX = mapped.x;
            }
        }
        onReleased: (event) => {
            if (shiftHeld) {
                shiftHeld = false;
                appListRoot.openContextMenu(root, appToplevel);
                return;
            }
            if (dragActive) {
                dragActive = false;
                appListRoot.finishDrag();
            } else {
                root.down = false;
                root.cancelRipple();
                root.click();
            }
        }
        onCanceled: {
            shiftHeld = false;
            if (dragActive) {
                dragActive = false;
                appListRoot.cancelDrag();
            }
            root.down = false;
            root.cancelRipple();
        }
    }

    onClicked: {
        if (appToplevel.toplevels.length > 0) {
            // Toggle preview
            if (appListRoot.clickedButton === root) {
                appListRoot.hidePreview();
            } else {
                appListRoot.showPreview(root);
            }
        } else {
            root.desktopEntry?.execute();
        }
    }

    // Hover tracker — magnification only
    MouseArea {
        id: hoverTracker
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        z: 1
        onPositionChanged: mouse => {
            appListRoot.listHovered = true;
            const mapped = mapToItem(appListRoot.listViewRef, mouse.x, mouse.y);
            appListRoot.mouseXInList = mapped.x + appListRoot.listViewRef.contentX;
        }
        onEntered: appListRoot.listHovered = true
        onExited: Qt.callLater(() => { appListRoot.listHovered = false; })
    }

    middleClickAction: () => {
        root.desktopEntry?.execute();
    }

    altAction: () => {
        TaskbarApps.togglePin(appToplevel.appId);
    }

    contentItem: Loader {
        active: !isSeparator
        sourceComponent: Item {
            anchors.centerIn: parent
            width: root.iconSize
            height: root.iconSize
            scale: root.hoverScale
            transformOrigin: Item.Bottom

            Behavior on scale {
                NumberAnimation { duration: 130; easing.type: Easing.OutCubic }
            }

            Loader {
                id: iconImageLoader
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }
                active: !root.isSeparator
                sourceComponent: IconImage {
                    source: Quickshell.iconPath(AppSearch.guessIcon(appToplevel.appId), "image-missing")
                    implicitSize: root.iconSize
                }
            }

            Loader {
                active: Config.options.dock.monochromeIcons
                anchors.fill: iconImageLoader
                sourceComponent: Item {
                    Desaturate {
                        id: desaturatedIcon
                        visible: false
                        anchors.fill: parent
                        source: iconImageLoader
                        desaturation: 0.8
                    }
                    ColorOverlay {
                        anchors.fill: desaturatedIcon
                        source: desaturatedIcon
                        color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.9)
                    }
                }
            }

            RowLayout {
                spacing: 3
                anchors {
                    top: iconImageLoader.bottom
                    topMargin: 2
                    horizontalCenter: parent.horizontalCenter
                }
                Repeater {
                    model: Math.min(appToplevel.toplevels.length, 3)
                    delegate: Rectangle {
                        required property int index
                        radius: Appearance.rounding.full
                        implicitWidth: (appToplevel.toplevels.length <= 3) ?
                            root.countDotWidth : root.countDotHeight
                        implicitHeight: root.countDotHeight
                        color: appIsActive ? Appearance.colors.colPrimary : ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.4)
                    }
                }
            }
        }
    }
}