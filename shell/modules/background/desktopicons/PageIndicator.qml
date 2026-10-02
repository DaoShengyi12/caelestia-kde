pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.services

// Pill of dots under the desktop grid, one per page. Clicking a dot goes there.
// With more pages than fit, only a window of dots around the current page is
// shown, and the dots at an end with more pages beyond it are smaller.
StyledRect {
    id: root

    property int count: 1
    property int current: 0
    property real maxWidth: Infinity

    readonly property real slot: Tokens.padding.large
    readonly property int maxDots: Math.max(3, Math.min(11, Math.floor((maxWidth - Tokens.padding.small * 2) / slot)))
    readonly property int shownDots: Math.min(count, maxDots)
    readonly property int windowStart: Math.max(0, Math.min(count - shownDots, current - Math.floor(shownDots / 2)))
    readonly property bool moreBefore: windowStart > 0
    readonly property bool moreAfter: windowStart + shownDots < count

    signal pageRequested(int page)

    function dotScale(index: int): real {
        const fromStart = index - windowStart;
        const fromEnd = windowStart + shownDots - 1 - index;
        const edge = Math.min(moreBefore ? fromStart : Infinity, moreAfter ? fromEnd : Infinity);
        return edge <= 0 ? 0.5 : edge === 1 ? 0.75 : 1;
    }

    implicitWidth: dotWindow.width + Tokens.padding.small * 2
    implicitHeight: slot + Tokens.padding.extraSmall * 2
    radius: Tokens.rounding.full
    color: Qt.alpha(Colours.palette.m3surfaceContainer, hover.hovered ? 0.75 : 0.5)

    HoverHandler {
        id: hover
    }

    Item {
        id: dotWindow

        anchors.centerIn: parent
        width: root.shownDots * root.slot
        height: root.slot
        clip: root.count > root.shownDots

        Row {
            x: -root.windowStart * root.slot

            Behavior on x {
                Anim {
                    type: Anim.FastSpatial
                }
            }

            Repeater {
                model: root.count

                Item {
                    id: dot

                    required property int index

                    implicitWidth: root.slot
                    implicitHeight: root.slot

                    StyledRect {
                        anchors.centerIn: parent
                        implicitWidth: Tokens.padding.small
                        implicitHeight: Tokens.padding.small
                        radius: Tokens.rounding.full
                        scale: root.dotScale(dot.index)
                        color: dot.index === root.current ? Colours.palette.m3onSurface : Qt.alpha(Colours.palette.m3onSurface, 0.35)

                        Behavior on scale {
                            Anim {
                                type: Anim.FastSpatial
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.pageRequested(dot.index)
                    }
                }
            }
        }
    }
}
