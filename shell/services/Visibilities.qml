pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.components
import qs.services
import qs.utils

Singleton {
    property var screens: new Map()
    property var bars: new Map()
    property string launcherInitialSearch: ""
    // Tab to show the next time the sidebar opens, when the opener asks for a
    // specific one; "" means the configured default (see sidebarOpenTab).
    property string initialSidebarTab: ""
    // Shell file dialogs currently open. They are separate windows, so focusing
    // one must not count as focus leaving the drawers.
    property int openDialogs: 0
    // A pinned sidebar only closes when the user closes it: losing focus or
    // clicking elsewhere leaves it open, and the rest of the screen stays usable.
    property bool sidebarPinned: false
    // Tab the sidebar opens on: "last" for wherever it was left, or a tab id.
    property string sidebarDefaultTab: "last"
    property string lastSidebarTab: "notifications"
    // Width the pinned sidebar was dragged to, or 0 for the default. Unpinned, the
    // sidebar always uses the default width.
    property int sidebarWidth: 0
    // True while the edge of the sidebar is being dragged; consumers that are
    // expensive to update (the exclusion zone) wait until the drag ends.
    property bool sidebarResizing: false

    function sidebarWidthFor(defaultWidth: real): real {
        return sidebarPinned && sidebarWidth > 0 ? sidebarWidth : defaultWidth;
    }

    function setSidebarWidth(width: int): void {
        sidebarWidth = Math.max(0, width);
        saveSidebarState();
    }

    function setSidebarPinned(pinned: bool): void {
        sidebarPinned = pinned;
        saveSidebarState();
    }

    function setSidebarDefaultTab(tab: string): void {
        sidebarDefaultTab = tab;
        saveSidebarState();
    }

    function setLastSidebarTab(tab: string): void {
        if (tab === lastSidebarTab)
            return;
        lastSidebarTab = tab;
        saveSidebarState();
    }

    function sidebarOpenTab(): string {
        return sidebarDefaultTab === "last" ? lastSidebarTab : sidebarDefaultTab;
    }

    function saveSidebarState(): void {
        sidebarStateFile.setText(JSON.stringify({
            pinned: sidebarPinned,
            defaultTab: sidebarDefaultTab,
            lastTab: lastSidebarTab,
            width: sidebarWidth
        }));
    }

    FileView {
        id: sidebarStateFile

        path: `${Paths.state}/sidebar.json`
        printErrors: false
        onLoaded: {
            try {
                const s = JSON.parse(text());
                sidebarPinned = s.pinned === true;
                sidebarDefaultTab = s.defaultTab || "last";
                lastSidebarTab = s.lastTab || "notifications";
                sidebarWidth = Math.max(0, Math.round(s.width || 0));
            } catch (e) {}
            if (sidebarPinned)
                pinRestore.start();
        }
    }

    // A pinned sidebar is part of the desktop: bring it back when the shell starts,
    // once the screens have registered their drawers.
    Timer {
        id: pinRestore

        interval: 1500
        onTriggered: {
            const v = getForActive();
            if (v && sidebarPinned)
                v.sidebar = true;
        }
    }
    property string preOverviewActiveWindowAddress: ""
    property string dragAddress: ""
    property string dragOriginScreen: ""
    property real dragX: 0
    property real dragY: 0
    property real dragWidth: 0
    property real dragHeight: 0
    property string streamClaim: ""

    signal cycleOverview(bool backwards)

    function load(screen: ShellScreen, visibilities: DrawerVisibilities): void {
        screens.set(Kwin.monitorFor(screen), visibilities);
        screens = new Map(screens);
        visibilities.launcherChanged.connect(() => {
            if (!visibilities.launcher) {
                Kwin.clearHighlight();
                return;
            }
            for (const other of screens.values()) {
                if (other !== visibilities)
                    other.launcher = false;
            }
        });
        visibilities.overviewChanged.connect(() => {
            if (visibilities.overview)
                Kwin.clearHighlight();
        });
        visibilities.sessionChanged.connect(() => {
            if (visibilities.session)
                Kwin.clearHighlight();
        });
    }
    function registerBar(screen: ShellScreen, barWrapper: var): void {
        bars.set(screen.name, barWrapper);
        bars = new Map(bars);
    }
    function getForActive(): DrawerVisibilities {
        const monitor = Kwin.monitors[Kwin.cursorOutputName()] || Kwin.focusedMonitor;
        return screens.get(monitor) || screens.values().next().value;
    }
    function setDrag(address: string, x: real, y: real, w: real, h: real, originScreen: string): void {
        dragAddress = address;
        dragX = x;
        dragY = y;
        dragWidth = w;
        dragHeight = h;
        dragOriginScreen = originScreen;
    }
    function clearDrag(): void {
        dragAddress = "";
        dragOriginScreen = "";
    }
    function setOverview(visible: bool): void {
        for (const visibilities of screens.values())
            visibilities.overview = visible;
    }
}
