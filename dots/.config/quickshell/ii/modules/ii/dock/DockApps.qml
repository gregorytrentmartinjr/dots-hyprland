import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Item {
    id: root
    property real maxWindowPreviewHeight: 200
    property real maxWindowPreviewWidth: 300
    property real windowControlsHeight: 30
    property real buttonPadding: 5

    property Item clickedButton: null
    property Item lastHoveredButton
    property bool buttonHovered: false
    property bool requestDockShow: previewPopup.show || contextMenu.isOpen

    // Magnification state
    property bool magnificationEnabled: Config.options.dock.magnification?.enable ?? false
    property alias listViewRef: listView
    property real mouseXInList: -9999
    property bool listHovered: false

    function scaleForX(itemCenterX) {
        if (!magnificationEnabled || !listHovered || _reordering || dragging) return 1.0;
        var maxScale = Config.options.dock.magnification?.maxScale ?? 1.0;
        var sigma = Config.options.dock.magnification?.sigma ?? 60;
        var dist = itemCenterX - mouseXInList;
        return 1.0 + maxScale * Math.exp(-(dist * dist) / (2 * sigma * sigma));
    }

    function showPreview(button) {
        clickedButton = button;
        previewPopup.fading = false;
        fadeTimer.stop();
        previewPopup.show = true;
        dismissTimer.restart();
    }
    function hidePreview() {
        dismissTimer.stop();
        previewPopup.fading = true;
        fadeTimer.restart();
    }

    // Drag-to-reorder state
    property bool dragging: false
    property bool _reordering: false
    property int dragSourceIndex: -1
    property real dragCursorX: 0
    property real dragStartCursorX: 0
    property real slotWidth: 0
    property int dragTargetIndex: {
        if (!dragging || slotWidth <= 0) return dragSourceIndex;
        var delta = dragCursorX - dragStartCursorX;
        var slots = Math.round(delta / slotWidth);
        var pinnedCount = Config.options.dock.pinnedApps.length;
        return Math.max(0, Math.min(dragSourceIndex + slots, pinnedCount - 1));
    }

    Timer {
        id: reorderSettleTimer
        // Must outlast Config file write (50ms) + file-change reload (50ms) cycle
        // to prevent add/remove transitions from firing on the reload-triggered
        // model rebuild.
        interval: 300
        onTriggered: {
            root._reordering = false;
        }
    }

    function finishDrag() {
        _reordering = true;
        // Capture indices before clearing drag state since dragTargetIndex
        // depends on dragging being true
        var src = dragSourceIndex;
        var tgt = dragTargetIndex;
        // Clear drag visual state first
        dragging = false;
        dragSourceIndex = -1;
        dragCursorX = 0;
        dragStartCursorX = 0;
        // Then update the model
        if (src >= 0 && src !== tgt) {
            TaskbarApps.reorderPinned(src, tgt);
        }
        reorderSettleTimer.restart();
    }

    function cancelDrag() {
        _reordering = true;
        dragging = false;
        dragSourceIndex = -1;
        dragCursorX = 0;
        dragStartCursorX = 0;
        reorderSettleTimer.restart();
    }

    function openContextMenu(button, appToplevelData) {
        contextMenu.open(button, appToplevelData);
    }

    Layout.fillHeight: true
    Layout.topMargin: Appearance.sizes.hyprlandGapsOut // why does this work
    implicitWidth: listView.implicitWidth

    // Hover-only overlay for magnification — acceptedButtons: Qt.NoButton means it never steals clicks
    MouseArea {
        id: listHoverArea
        anchors.fill: listView
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        z: 1
        onPositionChanged: mouse => {
            root.mouseXInList = mouse.x + listView.contentX;
        }
        onEntered: root.listHovered = true
        onExited: root.listHovered = false
    }

    StyledListView {
        id: listView
        spacing: 2
        clip: false
        interactive: false
        animateAppearance: !root._reordering
        orientation: ListView.Horizontal
        anchors {
            top: parent.top
            bottom: parent.bottom
        }
        implicitWidth: contentWidth

        Behavior on implicitWidth {
            enabled: !root._reordering
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        model: ScriptModel {
            objectProp: "appId"
            values: TaskbarApps.apps
        }
        delegate: DockAppButton {
            required property var modelData
            required property int index
            appToplevel: modelData
            appListRoot: root
            delegateIndex: {
                var pinnedApps = Config.options?.dock.pinnedApps ?? [];
                return pinnedApps.indexOf(modelData.appId.toLowerCase());
            }
            buttonIndex: index

            topInset: Appearance.sizes.hyprlandGapsOut + root.buttonPadding
            bottomInset: Appearance.sizes.hyprlandGapsOut + root.buttonPadding
            hoverScale: root.scaleForX(x + width / 2)
        }
    }

    PopupWindow {
        id: previewPopup
        property var appTopLevel: root.clickedButton?.appToplevel
        property bool show: false
        property bool fading: false

        onShowChanged: {
            if (show) {
                fading = false;
                dismissTimer.restart();
            }
        }

        Timer {
            id: dismissTimer
            interval: 3000
            onTriggered: {
                previewPopup.fading = true;
                fadeTimer.restart();
            }
        }

        Timer {
            id: fadeTimer
            interval: Appearance.animation.elementMoveFast.duration
            onTriggered: {
                previewPopup.show = false;
                previewPopup.fading = false;
                root.clickedButton = null;
            }
        }
        anchor {
            window: root.QsWindow.window
            adjustment: PopupAdjustment.None
            gravity: Edges.Top | Edges.Right
            edges: Edges.Top | Edges.Left

        }
        visible: popupBackground.visible
        color: "transparent"
        implicitWidth: root.QsWindow.window?.width ?? 1
        implicitHeight: popupMouseArea.implicitHeight + root.windowControlsHeight + Appearance.sizes.elevationMargin * 2

        MouseArea {
            id: popupMouseArea
            anchors.bottom: parent.bottom
            implicitWidth: popupBackground.implicitWidth + Appearance.sizes.elevationMargin * 2
            implicitHeight: root.maxWindowPreviewHeight + root.windowControlsHeight + Appearance.sizes.elevationMargin * 2
            hoverEnabled: true
            x: {
                const itemCenter = root.QsWindow?.mapFromItem(root.clickedButton, root.clickedButton?.width / 2, 0);
                return itemCenter.x - width / 2
            }

            StyledRectangularShadow {
                target: popupBackground
                opacity: (previewPopup.show && !previewPopup.fading) ? 1 : 0
                visible: opacity > 0
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
            Rectangle {
                id: popupBackground
                property real padding: 5
                opacity: (previewPopup.show && !previewPopup.fading) ? 1 : 0
                visible: opacity > 0
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                clip: true
                color: Appearance.m3colors.m3surfaceContainer
                radius: Appearance.rounding.normal
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Appearance.sizes.elevationMargin
                anchors.horizontalCenter: parent.horizontalCenter
                implicitHeight: previewRowLayout.implicitHeight + padding * 2
                implicitWidth: previewRowLayout.implicitWidth + padding * 2
                Behavior on implicitWidth {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on implicitHeight {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                RowLayout {
                    id: previewRowLayout
                    anchors.centerIn: parent
                    Repeater {
                        model: ScriptModel {
                            values: previewPopup.appTopLevel?.toplevels ?? []
                        }
                        RippleButton {
                            id: windowButton
                            required property var modelData
                            padding: 0
                            middleClickAction: () => {
                                windowButton.modelData?.close();
                            }
                            onClicked: {
                                root.hidePreview();
                                windowButton.modelData?.activate();
                            }
                            contentItem: ColumnLayout {
                                implicitWidth: screencopyView.implicitWidth
                                implicitHeight: screencopyView.implicitHeight

                                ButtonGroup {
                                    contentWidth: parent.width - anchors.margins * 2
                                    WrapperRectangle {
                                        Layout.fillWidth: true
                                        color: ColorUtils.transparentize(Appearance.colors.colSurfaceContainer)
                                        radius: Appearance.rounding.small
                                        margin: 5
                                        StyledText {
                                            Layout.fillWidth: true
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            text: windowButton.modelData?.title
                                            elide: Text.ElideRight
                                            color: Appearance.m3colors.m3onSurface
                                        }
                                    }
                                    GroupButton {
                                        id: closeButton
                                        colBackground: ColorUtils.transparentize(Appearance.colors.colSurfaceContainer)
                                        baseWidth: windowControlsHeight
                                        baseHeight: windowControlsHeight
                                        buttonRadius: Appearance.rounding.full
                                        contentItem: MaterialSymbol {
                                            anchors.centerIn: parent
                                            horizontalAlignment: Text.AlignHCenter
                                            text: "close"
                                            iconSize: Appearance.font.pixelSize.normal
                                            color: Appearance.m3colors.m3onSurface
                                        }
                                        onClicked: {
                                            root.hidePreview();
                                            windowButton.modelData?.close();
                                        }
                                    }
                                }
                                ScreencopyView {
                                    id: screencopyView
                                    captureSource: previewPopup.show ? windowButton.modelData : null
                                    live: true
                                    paintCursor: true
                                    constraintSize: Qt.size(root.maxWindowPreviewWidth, root.maxWindowPreviewHeight)
                                    layer.enabled: true
                                    layer.effect: OpacityMask {
                                        maskSource: Rectangle {
                                            width: screencopyView.width
                                            height: screencopyView.height
                                            radius: Appearance.rounding.small
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    DockContextMenu {
        id: contextMenu
    }
}
