pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.services

// Pill of dots under the desktop grid, one per page. Clicking a dot goes there.
StyledRect {
    id: root

    property int count: 1
    property int current: 0

    signal pageRequested(int page)

    implicitWidth: dots.implicitWidth + Tokens.padding.small * 2
    implicitHeight: dots.implicitHeight + Tokens.padding.extraSmall * 2
    radius: Tokens.rounding.full
    color: Qt.alpha(Colours.palette.m3surfaceContainer, hover.hovered ? 0.75 : 0.5)

    HoverHandler {
        id: hover
    }

    Row {
        id: dots

        anchors.centerIn: parent

        Repeater {
            model: root.count

            Item {
                id: dot

                required property int index

                implicitWidth: Tokens.padding.large
                implicitHeight: Tokens.padding.large

                StyledRect {
                    anchors.centerIn: parent
                    implicitWidth: Tokens.padding.small
                    implicitHeight: Tokens.padding.small
                    radius: Tokens.rounding.full
                    color: dot.index === root.current ? Colours.palette.m3onSurface : Qt.alpha(Colours.palette.m3onSurface, 0.35)
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
