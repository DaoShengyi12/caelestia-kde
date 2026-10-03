pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.modules.launcher.services

Item {
    id: root

    required property ShellScreen screen
    required property DrawerVisibilities visibilities
    required property var panels
    Config.screen: root.screen.name
    readonly property real maxWidth: screen.width
    readonly property bool shouldBeActive: visibilities.launcher && Config.launcher.enabled && !visibilities.overview
    readonly property real maxHeight: {
        let max = screen.height - Config.border.thickness * 2 + Tokens.padding.extraLarge;
        if (visibilities.dashboard)
            max -= panels.dashboard.nonAnimHeight;
        return max;
    }
    property real offsetScale: shouldBeActive ? 0 : 1
    // Building the content blocks the shell for over 100 ms, so it is built in
    // the background ahead of time: shortly after startup, and again each time
    // the launcher has closed. Every open still gets a fresh launcher (empty
    // search, first item selected), only without waiting for it.
    property bool prebuild: false
    property bool rebuilding: false

    onShouldBeActiveChanged: {
        if (shouldBeActive) {
            implicitHeight = Qt.binding(() => content.implicitHeight);
        } else
            implicitHeight = implicitHeight;
    }
    clip: Config.bar.position === "bottom"
    visible: offsetScale < 1
    onVisibleChanged: {
        if (!visible && prebuild) {
            rebuilding = true;
            Qt.callLater(() => rebuilding = false);
        }
    }
    anchors.bottomMargin: (Config.bar.position === "bottom" ? 0 : -implicitHeight - 5) * offsetScale
    height: Config.bar.position === "bottom" ? implicitHeight * (1 - offsetScale) : implicitHeight
    implicitHeight: content.implicitHeight
    implicitWidth: content.implicitWidth || 630
    opacity: 1 - offsetScale
    Component.onCompleted: Qt.callLater(() => Apps)

    Behavior on offsetScale {
        enabled: !visibilities.skipLauncherAnim

        Anim {}
    }
    Timer {
        running: true
        interval: 5000
        onTriggered: root.prebuild = true
    }
    Loader {
        id: content

        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        active: root.shouldBeActive || root.visible || (root.prebuild && !root.rebuilding && Config.launcher.enabled)
        // Opening the launcher mid-build finishes the build at once.
        asynchronous: !root.shouldBeActive
        sourceComponent: Component {
            Content {
                visibilities: root.visibilities
                panels: root.panels
                maxWidth: root.maxWidth
                maxHeight: root.maxHeight
            }
        }
    }
}
