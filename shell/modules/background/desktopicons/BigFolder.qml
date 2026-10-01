pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.services

// A group shown as a large folder: a grid of its app icons, each opening with
// one click. When they do not all fit, the last slot previews the rest and
// opens the full group. Names show when hovering, since the icons have none.
Item {
    id: root

    property var frame
    property var controller

    readonly property string groupId: frame.itemId
    readonly property var entries: controller.groupEntries(groupId)
    // Always three rows of icons, so the icons grow with the folder; a wider
    // folder adds columns at the same size.
    readonly property int rows: 3
    readonly property int columns: Math.max(3, Math.round(rows * width / Math.max(1, height)))
    readonly property real slot: Math.min(width / columns, height / rows)
    readonly property real iconSize: slot * 0.82
    readonly property int capacity: columns * rows
    readonly property bool overflow: entries.length > capacity
    readonly property var shown: overflow ? entries.slice(0, capacity - 1) : entries
    readonly property var rest: overflow ? entries.slice(capacity - 1) : []
    property Item hoveredSlot: null

    // Filled from the top left, the full grid centred in the card.
    Grid {
        id: grid

        x: (root.width - root.columns * root.slot) / 2
        y: (root.height - root.rows * root.slot) / 2
        columns: root.columns

        Repeater {
            model: root.shown

            Item {
                id: slotItem

                required property var modelData
                readonly property string memberKey: DesktopLayout.fileKey(modelData.fileName)
                readonly property bool dragged: root.controller.dragGroup === root.groupId && root.controller.dragKeys.indexOf(memberKey) !== -1

                width: root.slot
                height: root.slot
                opacity: dragged ? 0.35 : 1

                EntryIcon {
                    id: icon

                    anchors.centerIn: parent
                    width: root.iconSize
                    height: width
                    entry: slotItem.modelData
                    materialYou: root.controller.materialYou
                    vibrant: root.controller.vibrant
                    scale: slotArea.pressed ? 0.92 : slotArea.containsMouse ? 1.08 : 1

                    Behavior on scale {
                        Anim {
                            type: Anim.FastSpatial
                        }
                    }
                }

                MouseArea {
                    id: slotArea

                    property point pressPos
                    property bool dragSent: false

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onContainsMouseChanged: {
                        if (containsMouse)
                            root.hoveredSlot = slotItem;
                        else if (root.hoveredSlot === slotItem)
                            root.hoveredSlot = null;
                    }
                    onPressed: mouse => {
                        pressPos = Qt.point(mouse.x, mouse.y);
                        dragSent = false;
                        root.controller.grabKeyboard();
                    }
                    onPositionChanged: mouse => {
                        if (!(pressedButtons & Qt.LeftButton) || dragSent)
                            return;
                        const dx = mouse.x - pressPos.x;
                        const dy = mouse.y - pressPos.y;
                        if (dx * dx + dy * dy >= Qt.styleHints.startDragDistance * Qt.styleHints.startDragDistance) {
                            dragSent = true;
                            root.hoveredSlot = null;
                            root.controller.beginMemberDrag(root.groupId, slotItem.modelData.fileName, icon, pressPos.x - icon.x, pressPos.y - icon.y);
                        }
                    }
                    // Large folders act like a launcher: one click opens.
                    onClicked: mouse => {
                        if (dragSent)
                            return;
                        if (mouse.button === Qt.RightButton) {
                            const p = mapToItem(root.controller, mouse.x, mouse.y);
                            root.controller.memberContextMenu(root.groupId, slotItem.modelData.fileName, p.x, p.y);
                        } else {
                            slotItem.modelData.launch();
                        }
                    }
                }
            }
        }

        // The rest of the group in miniature; opens the whole group.
        Item {
            visible: root.overflow
            width: root.slot
            height: root.slot

            Grid {
                anchors.centerIn: parent
                columns: 2
                spacing: root.iconSize * 0.08
                scale: moreArea.pressed ? 0.92 : moreArea.containsMouse ? 1.08 : 1

                Behavior on scale {
                    Anim {
                        type: Anim.FastSpatial
                    }
                }

                Repeater {
                    model: root.rest.slice(0, 4)

                    EntryIcon {
                        required property var modelData

                        width: root.iconSize * 0.46
                        height: width
                        entry: modelData
                        materialYou: root.controller.materialYou
                        vibrant: root.controller.vibrant
                    }
                }
            }

            MouseArea {
                id: moreArea

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.controller.openGroup(root.groupId)
            }
        }
    }

    // Name of the hovered app.
    StyledRect {
        id: bubble

        readonly property Item target: root.hoveredSlot
        property string text

        x: target ? Math.max(-Tokens.padding.large, Math.min(root.width - width + Tokens.padding.large, target.mapToItem(root, 0, 0).x + target.width / 2 - width / 2)) : x
        y: target ? target.mapToItem(root, 0, 0).y - height + Tokens.padding.small : y
        z: 5
        implicitWidth: bubbleText.implicitWidth + Tokens.padding.medium * 2
        implicitHeight: bubbleText.implicitHeight + Tokens.padding.small * 2
        radius: Tokens.rounding.small
        color: Colours.palette.m3inverseSurface
        opacity: target && bubbleDelay.ready ? 1 : 0
        visible: opacity > 0

        onTargetChanged: {
            if (target) {
                text = target.modelData.displayName;
                bubbleDelay.restart();
            } else {
                bubbleDelay.ready = false;
                bubbleDelay.stop();
            }
        }

        Behavior on opacity {
            Anim {
                type: Anim.FastEffects
            }
        }

        Timer {
            id: bubbleDelay

            property bool ready: false

            interval: 350
            onTriggered: ready = true
        }

        StyledText {
            id: bubbleText

            anchors.centerIn: parent
            text: bubble.text
            color: Colours.palette.m3inverseOnSurface
            font: Tokens.font.label.medium
        }
    }
}
