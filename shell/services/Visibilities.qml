pragma Singleton

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
    // Tab the sidebar opens on: "last" for wherever it was left, or a tab id.
    property string sidebarDefaultTab: "last"
    property string lastSidebarTab: "notifications"
    // Persisted sidebar state (state dir, sidebar.json).
    property var sidebarState: ({})
    property string preOverviewActiveWindowAddress: ""
    property string dragAddress: ""
    property string dragOriginScreen: ""
    property real dragX: 0
    property real dragY: 0
    property real dragWidth: 0
    property real dragHeight: 0
    property string streamClaim: ""

    signal cycleOverview(bool backwards)

    function setSidebarDefaultTab(tab: string): void {
        sidebarDefaultTab = tab;
        saveSidebarState("defaultTab", tab);
    }

    function setLastSidebarTab(tab: string): void {
        if (tab === lastSidebarTab)
            return;
        lastSidebarTab = tab;
        saveSidebarState("lastTab", tab);
    }

    function sidebarOpenTab(): string {
        return sidebarDefaultTab === "last" ? lastSidebarTab : sidebarDefaultTab;
    }

    function saveSidebarState(key: string, value: var): void {
        sidebarState[key] = value;
        sidebarStateFile.setText(JSON.stringify(sidebarState));
    }

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

    FileView {
        id: sidebarStateFile

        path: `${Paths.state}/sidebar.json`
        printErrors: false
        onLoaded: {
            try {
                sidebarState = JSON.parse(text()) || {};
            } catch (e) {
                sidebarState = {};
            }
            sidebarDefaultTab = sidebarState.defaultTab || "last";
            lastSidebarTab = sidebarState.lastTab || "notifications";
        }
    }
}
