pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

// A group shown as a large folder: its apps sit right on the desktop and open
// with one click; whatever does not fit is behind the "more" tile.
Item {
    id: root

    property var frame
    property var controller

    readonly property string groupId: frame.itemId
    readonly property var group: DesktopLayout.groups[groupId] ?? null
    readonly property var entries: controller.groupEntries(groupId)
    readonly property real slotWidth: Math.max(controller.iconSize * 0.7, 48) + Tokens.padding.medium * 2
    readonly property real slotHeight: controller.iconSize * 0.7 + Tokens.padding.small * 2 + 28
    readonly property int columns: Math.max(1, Math.floor(grid.width / slotWidth))
    readonly property int capacity: Math.max(1, columns * Math.max(1, Math.floor(grid.height / slotHeight)))
    readonly property bool overflow: entries.length > capacity
    readonly property var shown: overflow ? entries.slice(0, capacity - 1) : entries

    function startRename(text: string): void {
        if (controller.renameActive && controller.renamingDelegate !== frame)
            controller.renamingDelegate.commitRename();
        controller.renamingDelegate = frame;
        title.startRename(text);
    }

    function commitRename(): void {
        title.commitRename();
    }

    function cancelRename(): void {
        title.cancelRename();
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Tokens.spacing.small

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            GroupTitle {
                id: title

                Layout.fillWidth: true
                text: root.group?.name ?? ""
                onRenameRequested: root.startRename(root.group?.name ?? "")
                onRenameCommitted: text => {
                    root.controller.finishRename(root.frame);
                    root.controller.renameGroup(root.groupId, text);
                }
                onRenameCancelled: root.controller.finishRename(root.frame)
            }

            IconButton {
                type: IconButton.Text
                icon: "open_in_full"
                onClicked: root.controller.openGroup(root.groupId)
            }
        }

        Item {
            id: grid

            Layout.fillWidth: true
            Layout.fillHeight: true

            Flow {
                anchors.horizontalCenter: parent.horizontalCenter
                width: root.columns * root.slotWidth

                Repeater {
                    model: root.shown

                    Item {
                        id: slot

                        required property var modelData
                        readonly property string memberKey: DesktopLayout.fileKey(modelData.fileName)

                        width: root.slotWidth
                        height: root.slotHeight
                        opacity: root.controller.dragGroup === root.groupId && root.controller.dragKeys.indexOf(memberKey) !== -1 ? 0.4 : 1

                        StyledRect {
                            anchors.fill: parent
                            radius: Tokens.rounding.medium
                            color: Qt.alpha(Colours.palette.m3onSurface, slotArea.containsMouse ? 0.1 : 0)
                        }

                        Column {
                            anchors.centerIn: parent
                            width: parent.width - Tokens.padding.small * 2
                            spacing: Tokens.spacing.extraSmall

                            EntryIcon {
                                id: slotIcon

                                anchors.horizontalCenter: parent.horizontalCenter
                                width: root.controller.iconSize * 0.7
                                height: width
                                entry: slot.modelData
                                materialYou: root.controller.materialYou
                                vibrant: root.controller.vibrant
                            }

                            StyledText {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                text: slot.modelData.displayName
                                elide: Text.ElideRight
                                font: Tokens.font.label.small
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
                                    root.controller.beginMemberDrag(root.groupId, slot.modelData.fileName, slot, pressPos.x, pressPos.y);
                                }
                            }
                            // Large folders act like a launcher: one click opens.
                            onClicked: mouse => {
                                if (dragSent)
                                    return;
                                if (mouse.button === Qt.RightButton) {
                                    const p = mapToItem(root.controller, mouse.x, mouse.y);
                                    root.controller.memberContextMenu(root.groupId, slot.modelData.fileName, p.x, p.y);
                                } else {
                                    slot.modelData.launch();
                                }
                            }
                        }
                    }
                }

                // Opens the full group when not everything fits.
                Item {
                    visible: root.overflow
                    width: root.slotWidth
                    height: root.slotHeight

                    StyledRect {
                        anchors.centerIn: parent
                        width: root.controller.iconSize * 0.7
                        height: width
                        radius: Tokens.rounding.medium
                        color: Qt.alpha(Colours.palette.m3primaryContainer, moreArea.containsMouse ? 1 : 0.8)

                        StyledText {
                            anchors.centerIn: parent
                            text: "+" + (root.entries.length - root.shown.length)
                            color: Colours.palette.m3onPrimaryContainer
                            font: Tokens.font.title.small
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
        }
    }
}
