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
    property Item anchorButton: null
    property Item lastHoveredButton: null
    property bool buttonHovered: false
    property bool previewShow: false
    property bool previewFading: false
    property bool requestDockShow: previewShow || contextMenu.isOpen

    function showPreview(button) {
        clickedButton = button;
        anchorButton = button;
        previewFading = false;
        previewLoader.active = true;
        previewShow = true;
        dismissTimer.restart();
    }
    function hidePreview() {
        previewFading = true;
        fadeTimer.restart();
    }

    // Drag-to-reorder state
    property bool dragging: false
    property bool _reordering: false
    property bool _suppressTranslateAnim: false
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

    // Timer to re-enable animations after the model has fully settled.
    // Qt.callLater can race with deferred model updates, causing transitions
    // to fire on items that are still being added/removed (the flicker).
    Timer {
        id: reorderSettleTimer
        interval: 50
        onTriggered: {
            root._reordering = false;
            root._suppressTranslateAnim = false;
        }
    }

    function finishDrag() {
        _suppressTranslateAnim = true;
        if (dragging && dragSourceIndex !== dragTargetIndex) {
            _reordering = true;
            TaskbarApps.reorderPinned(dragSourceIndex, dragTargetIndex);
            // Process the model change synchronously while transitions are disabled
            listViewRef.forceLayout();
        }
        dragging = false;
        dragSourceIndex = -1;
        dragCursorX = 0;
        dragStartCursorX = 0;
        // Allow the ListView to fully process delegate changes before
        // re-enabling transitions, preventing the opacity-flicker on add.
        reorderSettleTimer.restart();
    }

    function cancelDrag() {
        _suppressTranslateAnim = true;
        dragging = false;
        dragSourceIndex = -1;
        dragCursorX = 0;
        dragStartCursorX = 0;
        Qt.callLater(function() { _suppressTranslateAnim = false; });
    }

    function openContextMenu(button, appToplevelData) {
        // Immediately tear down the preview popup rather than fading it out.
        // Having two PopupWindows alive at the same time crashes Quickshell.
        dismissTimer.stop();
        fadeTimer.stop();
        previewShow = false;
        previewFading = false;
        previewLoader.active = false;
        clickedButton = null;
        anchorButton = null;
        contextMenu.open(button, appToplevelData);
    }

    property alias listViewRef: listView
    property real mouseXInList: -9999
    property bool listHovered: false
    property real maxScale: 2.2
    property real sigma: 60

    function scaleForX(itemCenterX) {
        if (!listHovered || previewShow) return 1.0;
        const dist = itemCenterX - mouseXInList;
        return 1.0 + (maxScale - 1.0) * Math.exp(-(dist * dist) / (2 * sigma * sigma));
    }

    // Hover-only overlay — acceptedButtons: Qt.NoButton means it never steals clicks
    // but still receives hover position changes independently of dragEater
    MouseArea {
        id: listHoverArea
        anchors.fill: listView
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        z: 1
        onPositionChanged: mouse => {
            root.mouseXInList = mouse.x + listView.contentX;
        }
        onEntered:  root.listHovered = true
        onExited:   root.listHovered = false
    }

    Layout.fillHeight: true
    Layout.topMargin: Appearance.sizes.hyprlandGapsOut
    implicitWidth: listView.implicitWidth

    Timer {
        id: dismissTimer
        interval: 3000
        onTriggered: {
            root.hidePreview();
        }
    }

    Timer {
        id: fadeTimer
        interval: Appearance.animation.elementMoveFast.duration
        onTriggered: {
            root.previewShow = false;
            root.previewFading = false;
            previewLoader.active = false;
            root.clickedButton = null;
            root.anchorButton = null;
        }
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
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        model: ScriptModel {
            objectProp: "appId"
            values: TaskbarApps.apps
        }
        delegate: DockAppButton {
            id: delegateButton
            required property var modelData
            required property int index
            appToplevel: modelData
            appListRoot: root
            delegateIndex: {
                // Index within pinnedApps only (not the full list)
                var pinnedApps = Config.options?.dock.pinnedApps ?? [];
                return pinnedApps.indexOf(modelData.appId.toLowerCase());
            }
            buttonIndex: index

            topInset: Appearance.sizes.hyprlandGapsOut + root.buttonPadding
            bottomInset: Appearance.sizes.hyprlandGapsOut + root.buttonPadding
            hoverScale: root.scaleForX(x + width / 2)
        }
    }

    Loader {
        id: previewLoader
        active: false
        sourceComponent: PopupWindow {
            id: previewPopup
            visible: true

            anchor {
                item: root.anchorButton
                gravity: Edges.Top
                edges: Edges.Top
                adjustment: PopupAdjustment.SlideX
            }
            color: "transparent"
            implicitWidth: popupBackground.implicitWidth + Appearance.sizes.elevationMargin * 2
            implicitHeight: popupBackground.implicitHeight + Appearance.sizes.elevationMargin * 2

            MouseArea {
                id: popupMouseArea
                anchors.fill: parent
                hoverEnabled: true

                StyledRectangularShadow {
                    target: popupBackground
                    opacity: (root.previewShow && !root.previewFading) ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                }
                Rectangle {
                    id: popupBackground
                    property real padding: 5
                    opacity: (root.previewShow && !root.previewFading) ? 1 : 0
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

                    RowLayout {
                        id: previewRowLayout
                        anchors.centerIn: parent
                        Repeater {
                            model: ScriptModel {
                                values: root.clickedButton?.appToplevel?.toplevels ?? []
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
                                        captureSource: windowButton.modelData
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
    }

    DockContextMenu {
        id: contextMenu
    }
}
