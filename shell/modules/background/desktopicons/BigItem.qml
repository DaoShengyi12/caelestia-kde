pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.services

// A desktop item bigger than one cell: a large folder or a widget. Draws the
// card, takes selection, dragging, the context menu and resizing, and loads
// the actual content on top.
Item {
    id: root

    required property var controller
    required property string key

    readonly property bool isGroup: controller.isGroupKey(key)
    readonly property string itemId: controller.nameOf(key)
    readonly property var widget: isGroup ? null : (DesktopLayout.widgets[itemId] ?? null)
    readonly property var config: widget?.config ?? ({})
    readonly property var info: controller.widgetCatalog.info(isGroup ? "group" : (widget?.type ?? ""))
    readonly property var span: controller.displaySpans[key] ?? info.size

    property bool selected: false
    property bool focusVisible: false
    property bool dimmed: false
    property bool mergeTarget: false
    readonly property bool hovered: hover.hovered
    readonly property bool resizing: grip.pressed
    readonly property alias content: loader.item

    signal pressed(var mouse)
    signal clicked(var mouse)
    signal doubleClicked(var mouse)
    signal contextMenuRequested(real x, real y)
    signal dragRequested(real x, real y)

    function setConfig(patch: var): void {
        if (!isGroup)
            DesktopLayout.setWidgetConfig(itemId, patch);
    }

    // Renaming only applies to large folders, through their title.
    function startRename(text: string, selectUntil: int): void {
        loader.item?.startRename?.(text);
    }

    function commitRename(): void {
        loader.item?.commitRename?.();
    }

    function cancelRename(): void {
        loader.item?.cancelRename?.();
    }

    function overIcon(x: real, y: real): bool {
        return true;
    }

    property real appear: 0

    opacity: (dimmed ? 0.4 : 1) * appear
    scale: (0.9 + 0.1 * appear) * (mergeTarget ? 1.02 : 1)
    Component.onCompleted: appear = 1

    Behavior on appear {
        Anim {
            type: Anim.DefaultEffects
        }
    }

    Behavior on scale {
        Anim {
            type: Anim.FastSpatial
        }
    }

    HoverHandler {
        id: hover
    }

    StyledRect {
        id: card

        anchors.fill: parent
        anchors.margins: Tokens.padding.small
        radius: Tokens.rounding.large
        color: GlobalConfig.appearance.pitchBlack ? Qt.alpha("#000000", 0.85) : Qt.alpha(Colours.palette.m3surfaceContainer, 0.82)
        border.width: root.selected || root.mergeTarget || root.focusVisible ? 2 : 0
        border.color: Colours.palette.m3primary

        // Background of the card: selects, opens, drags and resizes the item.
        // Controls inside the content take their own clicks first.
        MouseArea {
            id: bgArea

            property point pressPos
            property bool dragSent: false

            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onPressed: mouse => {
                pressPos = Qt.point(mouse.x, mouse.y);
                dragSent = false;
                root.pressed({
                    x: mouse.x + card.x,
                    y: mouse.y + card.y,
                    button: mouse.button,
                    modifiers: mouse.modifiers
                });
            }
            onPositionChanged: mouse => {
                if (!(pressedButtons & Qt.LeftButton) || dragSent)
                    return;
                const dx = mouse.x - pressPos.x;
                const dy = mouse.y - pressPos.y;
                if (dx * dx + dy * dy >= Qt.styleHints.startDragDistance * Qt.styleHints.startDragDistance) {
                    dragSent = true;
                    root.dragRequested(pressPos.x + card.x, pressPos.y + card.y);
                }
            }
            onClicked: mouse => {
                if (dragSent)
                    return;
                if (mouse.button === Qt.RightButton)
                    root.contextMenuRequested(mouse.x + card.x, mouse.y + card.y);
                else
                    root.clicked(mouse);
            }
            onDoubleClicked: mouse => {
                if (mouse.button === Qt.LeftButton)
                    root.doubleClicked(mouse);
            }
        }

        Loader {
            id: loader

            anchors.fill: parent
            anchors.margins: Tokens.padding.medium
            asynchronous: true
            readonly property string wanted: root.info.source

            function load(): void {
                if (wanted !== "")
                    setSource(Qt.resolvedUrl(wanted), {
                        frame: root,
                        controller: root.controller
                    });
                else
                    source = "";
            }

            onWantedChanged: load()
            Component.onCompleted: load()
        }
    }

    // Drag the corner to resize in whole cells.
    MouseArea {
        id: grip

        property point origin
        property var startSpan

        anchors.right: card.right
        anchors.bottom: card.bottom
        width: Tokens.padding.large * 2
        height: width
        hoverEnabled: true
        cursorShape: Qt.SizeFDiagCursor
        visible: opacity > 0
        opacity: root.hovered || root.selected || pressed ? 1 : 0
        preventStealing: true
        onPressed: mouse => {
            origin = mapToItem(root.controller, mouse.x, mouse.y);
            startSpan = root.span;
            const p = mapToItem(root, mouse.x, mouse.y);
            root.pressed({
                x: p.x,
                y: p.y,
                button: Qt.LeftButton,
                modifiers: Qt.NoModifier
            });
        }
        onPositionChanged: mouse => {
            if (!pressed)
                return;
            const p = mapToItem(root.controller, mouse.x, mouse.y);
            const w = Math.max(root.info.min.w, Math.min(root.info.max.w, Math.round(startSpan.w + (p.x - origin.x) / root.controller.cellWidth)));
            const h = Math.max(root.info.min.h, Math.min(root.info.max.h, Math.round(startSpan.h + (p.y - origin.y) / root.controller.cellHeight)));
            root.controller.previewResize(root.key, w, h);
        }
        onReleased: {
            const s = root.controller.displaySpans[root.key] ?? startSpan;
            root.controller.resizeItem(root.key, s.w, s.h);
        }
        onCanceled: root.controller.endResizePreview()

        Behavior on opacity {
            Anim {
                type: Anim.FastEffects
            }
        }

        MaterialIcon {
            anchors.centerIn: parent
            text: "drag_handle"
            rotation: -45
            color: Colours.palette.m3onSurfaceVariant
        }
    }
}
