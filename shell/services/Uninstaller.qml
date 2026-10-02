pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.utils

Singleton {
    id: root

    readonly property var candidatePaths: [
        Quickshell.env("CAELESTIA_DIR") ? Quickshell.env("CAELESTIA_DIR") + "/uninstall.sh" : "",
        Quickshell.env("HOME") + "/caelestia-kde/uninstall.sh",
        Quickshell.env("HOME") + "/.config/caelestia-update/repo/uninstall.sh",
        Quickshell.env("HOME") + "/.cache/caelestia-update-repo/uninstall.sh"
    ].filter(p => p !== "")

    readonly property var packageManagers: [
        { tool: "pacman", command: "sudo pacman -Rns caelestia-kde" },
        { tool: "dnf", command: "sudo dnf remove caelestia-kde" },
        { tool: "apt-get", command: "sudo apt-get remove caelestia-kde" }
    ]

    readonly property string state: {
        if (!root.probed)
            return "probing";
        if (root.scriptPath !== "")
            return "script";
        if (root.manualCommand !== "")
            return "package";
        return "unknown";
    }

    readonly property bool scriptFound: root.state === "script"

    property bool probed: false
    property string scriptPath: ""
    property string manualCommand: ""

    function launch(): void {
        if (!root.scriptFound)
            return;

        Launch.launchInTerminal(["bash", root.scriptPath], "");
    }

    Process {
        id: probe

        command: ["sh", "-c", `
candidates="$1"
shift
for candidate in "$@"; do
    if [ "$candidates" -gt 0 ] && [ -f "$candidate" ]; then
        printf 'SCRIPT %s\n' "$candidate"
        exit 0
    fi
    candidates=$((candidates - 1))
done
for manager in "$@"; do
    case "$manager" in
        pacman)
            pacman -Q caelestia-kde >/dev/null 2>&1 && printf 'PACKAGE pacman\n' && exit 0
            ;;
        dnf)
            dnf list installed caelestia-kde >/dev/null 2>&1 && printf 'PACKAGE dnf\n' && exit 0
            ;;
        apt-get)
            dpkg-query -W -f='\${Status}' caelestia-kde 2>/dev/null | grep -qx 'install ok installed' && printf 'PACKAGE apt-get\n' && exit 0
            ;;
    esac
done
echo UNKNOWN`, "--", String(root.candidatePaths.length), ...root.candidatePaths, ...root.packageManagers.map(m => m.tool)]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n");
                const script = lines.find(l => l.startsWith("SCRIPT "));
                const manager = lines.find(l => l.startsWith("PACKAGE "));
                if (script)
                    root.scriptPath = script.slice("SCRIPT ".length).trim();
                if (manager) {
                    const tool = manager.slice("PACKAGE ".length).trim();
                    const entry = root.packageManagers.find(m => m.tool === tool);
                    root.manualCommand = entry ? entry.command : "";
                }
                root.probed = true;
            }
        }
    }
}
