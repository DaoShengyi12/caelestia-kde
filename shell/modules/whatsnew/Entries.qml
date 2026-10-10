import QtQuick
import Quickshell

QtObject {
    readonly property string assetDir: "../../assets/whatsnew/"

    readonly property var list: [
        {
            "id": "terminal_package_updater",
            "revision": 32,
            "icon": "terminal",
            "title": qsTr("Terminal Updates"),
            "description": qsTr("The system package updater is now configured to launch inside your preferred user terminal emulator, with an automatic fallback to Konsole.")
        },
        {
            "id": "builtin_uninstaller",
            "revision": 33,
            "icon": "delete_forever",
            "title": qsTr("Built-in Uninstaller"),
            "description": qsTr("A safe uninstaller action has been added directly to the About page in settings, providing a clean way to remove the shell and its owned resources.")
        },
        {
            "id": "follow_system_font",
            "revision": 34,
            "icon": "font_download",
            "title": qsTr("System Font Integration"),
            "description": qsTr("A new option allows the shell to automatically follow your system-wide KDE font settings, rather than using a static default font.")
        },
        {
            "id": "yaml_config_export",
            "revision": 35,
            "icon": "file_download",
            "title": qsTr("Export Configuration"),
            "description": qsTr("You can now export your complete shell configuration to a YAML file, providing a lossless backup of all your settings and preferences.")
        },
        {
            "id": "per_setting_reset_buttons",
            "revision": 36,
            "icon": "settings_backup_restore",
            "title": qsTr("Setting Reset Buttons"),
            "description": qsTr("Added persistent, inline reset buttons across Nexus settings pages, allowing you to instantly restore individual sliders, steppers, and toggles to their default values.")
        },
        {
            "id": "quick_toggles_reordering",
            "revision": 37,
            "icon": "toggle_on",
            "title": qsTr("Quick Toggles Overhaul"),
            "description": qsTr("Complete visual and functional overhaul of Quick Toggles. Supports custom order, multiple layouts, settings shortcut, and more.")
        },
        {
            "id": "desktop_icons_rework",
            "revision": 38,
            "icon": "desktop_windows",
            "title": qsTr("Interactive Desktop Icons"),
            "description": qsTr("A complete overhaul of desktop icons adding support for rectangle multi-selection, keyboard navigation, grid auto-alignment, grouping, and drag-and-drop.")
        },
        {
            "id": "sidebar_default_tab",
            "revision": 39,
            "icon": "tab",
            "title": qsTr("Sidebar Startup Tab"),
            "description": qsTr("The sidebar can now be configured to open on the last-used tab, or to always open on a specific default tab of your choice.")
        },
        {
            "id": "desktop_elements_offsets",
            "revision": 40,
            "icon": "tune",
            "title": qsTr("Desktop Elements Fine-Tuning"),
            "description": qsTr("Added configurable fine X and Y position offsets for the desktop clock and desktop lyrics, allowing precise placement of elements on your wallpaper.")
        },
        {
            "id": "desktop_background_menu",
            "revision": 41,
            "icon": "menu_open",
            "title": qsTr("Desktop Context Menus"),
            "description": qsTr("Multiple context menus have been added for Desktop, Icons, Folders & Widgets. You can also do a quick Middle-click action on desktop to toggle desktop icon visibility.")
        },
        {
            "id": "plugin_manager_enhancements",
            "revision": 42,
            "icon": "extension",
            "title": qsTr("Git Plugins & Updates"),
            "description": qsTr("The Plugin Manager now supports installing plugins directly from Git URLs. It also checks for updates, displaying notification badges and allowing in-place updates.")
        },
        {
            "id": "wifi_hotspot",
            "revision": 43,
            "icon": "wifi_tethering",
            "title": qsTr("Wi-Fi Hotspot"),
            "description": qsTr("A built-in Wi-Fi hotspot toggle switch has been added to the quick toggles and network popout, complete with auto-refresh state monitoring.")
        },
        {
            "id": "brightness_osd_dimming",
            "revision": 44,
            "icon": "brightness_medium",
            "title": qsTr("Advanced Brightness Control"),
            "description": qsTr("The Brightness OSD now perfectly synchronizes with KWin state during slider drags, and supports reading and displaying software dimming multipliers.")
        },
        {
            "id": "audio_visualizer_enhancements",
            "revision": 45,
            "icon": "equalizer",
            "title": qsTr("Audio Visualizer Enhancements"),
            "description": qsTr("The audio visualizer now allows you to choose the capture source (System Audio Output vs Microphone Input), and features configurable side widths and margin size scaling.")
        },
        {
            "id": "dock_ungrouped_windows",
            "revision": 46,
            "icon": "grid_view",
            "title": qsTr("Ungrouped Dock Icons"),
            "description": qsTr("An option has been added to the Dock to display separate, ungrouped icon tiles for each individual window instance instead of grouping them by application.")
        },
        {
            "id": "bar_item_settings_links",
            "revision": 47,
            "icon": "settings_applications",
            "title": qsTr("Bar Item Settings Links"),
            "description": qsTr("Right-clicking specific bar items (such as the OS Icon, Power Button, and Show Desktop) now instantly opens their respective configuration pages in Nexus settings.")
        },
        {
            "id": "launcher_drawer_prewarming",
            "revision": 48,
            "icon": "bolt",
            "title": qsTr("Launcher Pre-warming"),
            "description": qsTr("The launcher drawer is now pre-warmed in the background, eliminating open latency and preventing visual flicker when displaying the app grid.")
        },
        {
            "id": "app_browser_layouts",
            "revision": 49,
            "icon": "apps",
            "title": qsTr("App Browser Layouts"),
            "description": qsTr("The launcher now supports multiple app browser layouts. Choose between the standard categorized Grid, a Simple list, or a Compact list view via configuration.")
        },
        {
            "id": "dashboard_hourly_weather",
            "revision": 50,
            "icon": "partly_cloudy_day",
            "title": qsTr("Hourly Weather Forecast"),
            "description": qsTr("The Weather tab in the dashboard now includes an hourly forecast alongside the existing daily weather predictions.")
        },
        {
            "id": "claude_code_assistant",
            "revision": 51,
            "icon": "smart_toy",
            "title": qsTr("Claude Code Assistant"),
            "description": qsTr("The AI assistant now integrates with Claude Code. Background subagents are fully supported with live streaming, and tool invocations are rendered inline where they were called. Code blocks feature syntax highlighting and copy buttons.")
        },
        {
            "id": "ai_chat_persistence",
            "revision": 52,
            "icon": "history",
            "title": qsTr("AI Chat Persistence"),
            "description": qsTr("AI chats are now persistent. You can switch between active chats, and your Claude Code sessions and chat history are safely stored and managed across shell reloads.")
        },
        {
            "id": "pinned_sidebar",
            "revision": 53,
            "icon": "vertical_split",
            "title": qsTr("Pinned Sidebar"),
            "description": qsTr("The sidebar can now be pinned to stay open, reserving screen workarea space so windows don't overlap it. You can resize it dynamically by dragging its edge.")
        },
        {
            "id": "unified_capture_card",
            "revision": 54,
            "icon": "screenshot_monitor",
            "title": qsTr("Unified Capture Card"),
            "description": qsTr("Screen recording and screenshots are now combined into a single Capture Card in the utilities drawer. It provides quick access to fullscreen, active window, region snip, OCR, image search, and a history of saved captures.")
        },
        {
            "id": "dock_app_shortcuts",
            "revision": 55,
            "icon": "keyboard",
            "title": qsTr("Dock App Shortcuts"),
            "description": qsTr("You can now use keyboard shortcuts (like Meta + 1 through 9) to quickly focus or launch your pinned applications from the dock. Requires setting up the shortcuts in the Shortcut Manager.")
        },
        {
            "id": "new_bar_components",
            "revision": 56,
            "icon": "widgets",
            "title": qsTr("Bar Widgets"),
            "settingsPage": "panels",
            "settingsSubPage": 6,
            "description": qsTr("The Bar now features a full-featured media widget with cover art, live CAVA visualization, quick actions, and a complete popout player.")
        },
        {
            "id": "dashboard_notes_editors",
            "revision": 57,
            "icon": "edit_document",
            "title": qsTr("Note Types & Editors"),
            "description": qsTr("The Dashboard Notes tab now supports dedicated editors for different note types, including Plain Text, Markdown, and Checklists, allowing for richer note-taking right from the dashboard.")
        },
        {
            "id": "desktop_widgets_folders",
            "revision": 58,
            "icon": "widgets",
            "title": qsTr("Desktop Widgets & Large Folders"),
            "description": qsTr("You can now place interactive widgets and expandable large folders directly onto the desktop grid for quick access to tools and files."),
            "mediaUrl": "desktop_widgets_folder.png"
        },
        {
            "id": "quick_share",
            "revision": 59,
            "icon": "share",
            "title": qsTr("Quick Share (Nearby Share)"),
            "settingsPage": "utilities",
            "settingsSubPage": 7,
            "description": qsTr("Receive and send files natively via the Nearby Share protocol. Quick Share features a background transfer service, interactive notifications, a quick toggle switch, and a dedicated utilities card for transfer tracking.")
        }
    ]

    function mediaSource(entry: var): url {
        if (!entry || !entry.mediaUrl)
            return "";
        if (entry.mediaUrl.startsWith("root:"))
            return Qt.resolvedUrl(`${Quickshell.shellDir}${entry.mediaUrl.slice("root:".length)}`);
        return Qt.resolvedUrl(`${assetDir}${entry.mediaUrl}`);
    }
}
