pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import M3Shapes
import Caelestia.Blobs
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.components.effects
import qs.components.filedialog
import qs.services
import qs.utils

Item {
    id: root

    ListModel { id: chatHistory }
    ListModel { id: historySessionsModel }

    property bool isHistoryTab: false

    property string currentChatId: ""

    property var currentRequest: null
    

    Timer {
        id: typingTimer

        interval: 16
        repeat: true

        property string fullText: ""

        property string currentText: ""

        property int charIndex: 0

        property int targetIdx: -1
        
        onTriggered: {
            if (targetIdx < 0 || targetIdx >= chatHistory.count) {
                stop();
                isTyping = false;
                isThinking = false;
                inAgentLoop = false;
                return;
            }
            if (charIndex >= fullText.length) {
                stop();
                chatHistory.setProperty(targetIdx, "text", fullText);
                chatHistory.setProperty(targetIdx, "isFinished", true);
                saveHistory();
                isTyping = false;
                isThinking = false;
                inAgentLoop = false;
                return;
            }
            var chunkSize = Math.max(1, Math.ceil(fullText.length / 30));
            currentText += fullText.substr(charIndex, chunkSize);
            charIndex += chunkSize;
            chatHistory.setProperty(targetIdx, "text", currentText);
            listView.positionViewAtEnd();
        }
    }
    
    property real savedContentY: -1

    onProviderChanged: {
        cancelRateLimitRetry();
        if (isOpenaiCompat)
            fetchOpenaiCompatModels(provider);
        else if (isClaude)
            fetchClaudeModels();
    }

    onVisibleChanged: {
        if (visible) {
            refreshAllModels();
            if (savedContentY >= 0) {
                Qt.callLater(function() { listView.contentY = savedContentY; });
            }
        } else {
            savedContentY = listView.contentY;
        }
    }

    function startTypingAnimation(text) {
        isThinking = false;
        typingTimer.targetIdx = chatHistory.count - 1;
        typingTimer.fullText = text;
        typingTimer.currentText = "";
        typingTimer.charIndex = 0;
        typingTimer.start();
        listView.positionViewAtEnd();
    }

    // Ask every enabled provider what it offers, rather than shipping lists that
    // go stale each time a vendor releases a model.
    function refreshAllModels() {
        fetchOllamaModels();
        fetchClaudeCodeModels();
        fetchClaudeModels();
        const compat = root.openaiCompatProviders;
        for (var i = 0; i < compat.length; i++) {
            if (providerList.indexOf(compat[i]) !== -1)
                fetchOpenaiCompatModels(compat[i]);
        }
    }

    Component.onCompleted: {
        loadAllKeys();
        refreshAllModels();
        loadHistory();
    }


    function logFetchError(provider) {
        Logger.log("[AI] Network error fetching models from " + (provider || "unknown"));
    }

    function handleSendError() {
        isTyping = false;
        isThinking = false;
        inAgentLoop = false;
        currentActionText = "";
        for (var ei = chatHistory.count - 1; ei >= 0; ei--) {
            var em = chatHistory.get(ei);
            if (!em.isUser && !em.isFinished) {
                chatHistory.setProperty(ei, "isFinished", true);
                if (!em.text)
                    chatHistory.setProperty(ei, "text",
                        "⚠️ Network error - check your connection and try again.");
                break;
            }
        }
    }

    property var ollamaModelsList: []

    property var claudeModelsList: []

    function fetchClaudeModels() {
        const key = root.getApiKeyFor("claude");
        if (key === "")
            return;
        const base = GlobalConfig.ai.anthropicUrl || "https://api.anthropic.com";
        var xhr = new XMLHttpRequest();
        xhr.open("GET", base + "/v1/models?limit=100", true);
        xhr.setRequestHeader("x-api-key", key);
        xhr.setRequestHeader("anthropic-version", "2023-06-01");
        xhr.setRequestHeader("anthropic-dangerous-direct-browser-access", "true");
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            if (xhr.status !== 200) {
                Logger.log("[AI] Claude model list failed (status " + xhr.status + ")");
                return;
            }
            try {
                const parsed = JSON.parse(xhr.responseText);
                var list = [];
                for (var i = 0; i < (parsed.data || []).length; i++) {
                    if (parsed.data[i].id)
                        list.push(parsed.data[i].id);
                }
                if (list.length === 0)
                    return;
                list.reverse();
                root.claudeModelsList = list;
                if (list.indexOf(GlobalConfig.ai.defaultClaudeModel) === -1)
                    GlobalConfig.ai.defaultClaudeModel = list[0];
            } catch (e) {
                Logger.log("[AI] Error parsing Claude models: " + e.message);
            }
        };
        xhr.onerror = () => { root.logFetchError("Claude"); };
        xhr.send();
    }

    property var claudeCodeModelsList: ["default"]

    function effortLevelsFor(model) {
        var m = String(model || "default").toLowerCase();
        if (m === "haiku")
            return [];
        if (m === "default" || m === "opus" || m === "sonnet" || m === "fable")
            return ["low", "medium", "high", "xhigh", "max"];

        var fam = m.indexOf("opus") !== -1 ? "opus"
                : m.indexOf("sonnet") !== -1 ? "sonnet"
                : m.indexOf("haiku") !== -1 ? "haiku"
                : m.indexOf("fable") !== -1 ? "fable" : "";
        var nums = (m.match(/\d+/g) || []).map(Number);
        var major = nums.length >= 1 ? nums[0] : 0;
        var minor = nums.length >= 2 ? nums[1] : 0;

        if (fam === "haiku")
            return [];
        if (fam === "fable")
            return ["low", "medium", "high", "xhigh", "max"];
        if (fam === "opus") {
            if (major > 4 || (major === 4 && minor >= 7))
                return ["low", "medium", "high", "xhigh", "max"];
            if (major === 4 && minor === 6)
                return ["low", "medium", "high", "max"];
            if (major === 4 && minor === 5)
                return ["low", "medium", "high"];
            return [];
        }
        if (fam === "sonnet") {
            if (major >= 5)
                return ["low", "medium", "high", "xhigh", "max"];
            if (major === 4 && minor === 6)
                return ["low", "medium", "high", "max"];
            return [];
        }
        return [];
    }

    readonly property var claudeCodeEffortOptions: {
        var lv = effortLevelsFor(activeModel());
        return lv.length > 0 ? ["default"].concat(lv) : [];
    }

    function fetchClaudeCodeModels() {
        var bin = claudeCodeBinPath();
        var script =
            "t=\"$(readlink -f " + JSON.stringify(bin) + " 2>/dev/null)\"; [ -z \"$t\" ] && t=" + JSON.stringify(bin) + "; " +
            "strings \"$t\" 2>/dev/null | grep -oE 'claude-(opus|sonnet|haiku|fable)-[0-9]+(-[0-9]+)?' | sort -u";
        var commandStr = JSON.stringify(["sh", "-c", script]);
        var qml =
            "import QtQuick\n" +
            "import Quickshell.Io\n" +
            "Process {\n" +
            "    id: mp\n" +
            "    command: " + commandStr + "\n" +
            "    stdout: StdioCollector { onStreamFinished: root.applyClaudeCodeModels(text || \"\"); }\n" +
            "    onExited: code => mp.destroy()\n" +
            "}";
        try {
            var o = Qt.createQmlObject(qml, root, "ccModelsProc");
            o.running = true;
        } catch (e) {
            Logger.log("[AI] claude-code model fetch error: " + e.message);
        }
    }

    function applyClaudeCodeModels(text) {
        var ids = [];
        var seen = {};
        const lines = (text || "").split("\n");
        for (var i = 0; i < lines.length; i++) {
            const id = lines[i].trim();
            if (id === "" || seen[id])
                continue;
            if (/-\d{5,}$/.test(id) || /-0$/.test(id))
                continue;
            seen[id] = true;
            ids.push(id);
        }

        ids = ids.filter(id => !ids.some(other => other !== id && other.indexOf(id + "-") === 0));

        ids.sort((a, b) => {
            const va = (a.match(/\d+/g) || []).map(Number);
            const vb = (b.match(/\d+/g) || []).map(Number);
            for (var k = 0; k < Math.max(va.length, vb.length); k++) {
                const d = (vb[k] || 0) - (va[k] || 0);
                if (d !== 0)
                    return d;
            }
            return a.localeCompare(b);
        });

        claudeCodeModelsList = ["default"].concat(ids);
    }

    readonly property string provider: GlobalConfig.ai.defaultProvider || "ollama"

    readonly property bool isClaude: provider === "claude"

    readonly property bool isClaudeCode: provider === "claude-code"

    property var claudeCodeSessions: ({})

    property var currentClaudeCodeProc: null

    // Working directory and permission mode of the current Claude Code chat. Both are
    // stored per chat (a CLI session only resumes from the directory it was created
    // in); a new chat inherits whatever was selected last.
    property string claudeCodeChatCwd: Quickshell.env("HOME") || "."
    property string claudeCodePermissionMode: defaultClaudeCodePermissionMode()
    // Bypass is only offered once it has been allowed in the AI settings.
    readonly property var claudeCodePermissionModes: GlobalConfig.ai.claudeCodeSkipPermissions
        ? ["bypassPermissions", "acceptEdits", "auto", "plan", "default"]
        : ["acceptEdits", "auto", "plan", "default"]
    readonly property var claudeCodeSidebarAllowedTools: ["Bash", "WebFetch", "WebSearch", "Read"]

    function defaultClaudeCodePermissionMode() {
        return GlobalConfig.ai.claudeCodeSkipPermissions ? "bypassPermissions" : "default";
    }

    // The mode actually used for a request: a chat saved in bypass mode falls back
    // to the CLI default once bypass is no longer allowed.
    function effectiveClaudeCodePermissionMode(mode) {
        mode = mode || defaultClaudeCodePermissionMode();
        if (mode === "bypassPermissions" && !GlobalConfig.ai.claudeCodeSkipPermissions)
            return "default";
        return mode;
    }

    function permissionModeLabel(mode) {
        switch (mode) {
        case "bypassPermissions": return qsTr("Bypass");
        case "acceptEdits": return qsTr("Accept edits");
        case "auto": return qsTr("Auto");
        case "plan": return qsTr("Plan");
        case "default": return qsTr("Default");
        }
        return mode;
    }

    function sessionEntry(chatId) {
        for (var i = 0; i < allChatSessions.length; i++)
            if (allChatSessions[i].id === chatId)
                return allChatSessions[i];
        return null;
    }

    function setClaudeCodeCwd(dir) {
        dir = (dir || "").replace(/\/+$/, "") || "/";
        if (dir === claudeCodeChatCwd)
            return;
        claudeCodeChatCwd = dir;
        // The old session lives under the previous directory's project, so --resume
        // would fail; the next send seeds a fresh session with the transcript instead.
        delete claudeCodeSessions[currentChatId];
        var s = sessionEntry(currentChatId);
        if (s) {
            s.claudeCodeSessionId = "";
            s.claudeCodeCwd = dir;
            if (GlobalConfig.ai.saveChatHistory)
                GlobalConfig.ai.ollamaHistoryJson = JSON.stringify(allChatSessions);
        }
    }

    function setClaudeCodePermissionMode(mode) {
        claudeCodePermissionMode = mode;
        var s = sessionEntry(currentChatId);
        if (s) {
            s.claudeCodePermissionMode = mode;
            if (GlobalConfig.ai.saveChatHistory)
                GlobalConfig.ai.ollamaHistoryJson = JSON.stringify(allChatSessions);
        }
    }

    // A file dialog is open (keeps the sidebar loaded, see Content.aiBusy).
    readonly property bool dialogOpen: cwdDialog.activeAsync || attachDialog.activeAsync

    function shortPath(p) {
        var home = Quickshell.env("HOME") || "";
        if (home !== "" && (p === home || p.indexOf(home + "/") === 0))
            return "~" + p.substring(home.length);
        return p;
    }

    // Files attached to the next message: [{ path, isImage }].
    property var pendingAttachments: []
    readonly property bool canSend: inputArea.text.length > 0 || pendingAttachments.length > 0
    readonly property string attachmentDir: (Quickshell.env("XDG_CACHE_HOME") || ((Quickshell.env("HOME") || "") + "/.cache")) + "/caelestia/ai-attachments"

    function isImagePath(p) {
        return /\.(png|jpe?g|gif|webp|bmp)$/i.test(p || "");
    }

    function addAttachment(path) {
        path = (path || "").trim();
        if (path.indexOf("file://") === 0)
            path = decodeURIComponent(path.substring(7));
        if (path === "")
            return;
        for (var i = 0; i < pendingAttachments.length; i++)
            if (pendingAttachments[i].path === path)
                return;
        pendingAttachments = pendingAttachments.concat([{ path: path, isImage: isImagePath(path) }]);
    }

    function removeAttachment(path) {
        pendingAttachments = pendingAttachments.filter(a => a.path !== path);
    }

    // Save a clipboard image to the attachment cache and attach it; without an
    // image on the clipboard this falls back to a normal text paste.
    function pasteClipboardImage() {
        var file = attachmentDir + "/paste-" + Date.now() + ".png";
        var script = "t=$(wl-paste --list-types 2>/dev/null | grep -m1 '^image/') || exit 3; "
            + "mkdir -p \"$1\" && wl-paste --no-newline --type \"$t\" > \"$2\" && echo \"$2\"";
        var cmd = ["sh", "-c", script, "--", attachmentDir, file];
        var qml =
            "import QtQuick\n" +
            "import Quickshell.Io\n" +
            "Process {\n" +
            "    id: pp\n" +
            "    command: " + JSON.stringify(cmd) + "\n" +
            "    stdout: StdioCollector { id: ppOut }\n" +
            "    onExited: code => { root.onClipboardImageSaved(code, ppOut.text || \"\"); pp.destroy(); }\n" +
            "}";
        try {
            var o = Qt.createQmlObject(qml, root, "pasteImageProc");
            o.running = true;
        } catch (e) {
            Logger.log("[AI] paste process error: " + e.message);
        }
    }

    function onClipboardImageSaved(code, out) {
        if (code === 0 && out.trim() !== "")
            addAttachment(out.trim());
        else
            inputArea.paste();
    }

    // Open the current Claude Code session in a terminal (`claude --resume`).
    function openClaudeCodeInTerminal() {
        var sid = claudeCodeSessionFor(currentChatId);
        var dir = activeClaudeConfigDir();
        var inner = "cd " + shellQuote(claudeCodeCwd()) + " && ";
        if (dir && dir !== "")
            inner += "CLAUDE_CONFIG_DIR=" + shellQuote(dir) + " ";
        inner += "exec " + shellQuote(claudeCodeBinPath());
        if (sid !== "")
            inner += " --resume " + shellQuote(sid);
        var term = GlobalConfig.ai.loginTerminal || "konsole";
        Launch.exec([term, "-e", "sh", "-lc", inner]);
    }

    // Live status for a running Claude Code reply, shown under it the way the CLI
    // does: a rotating verb, elapsed time and output tokens.
    property real claudeCodeStartedAt: 0
    property int claudeCodeElapsed: 0
    property int claudeCodeOutTokens: 0
    property bool claudeCodeToolRunning: false
    readonly property var thinkingVerbs: [
        "Thinking", "Pondering", "Musing", "Mulling", "Cogitating", "Ruminating",
        "Brewing", "Simmering", "Percolating", "Noodling", "Tinkering", "Puzzling",
        "Untangling", "Connecting dots", "Crunching", "Sketching", "Weaving",
        "Conjuring", "Scheming", "Distilling", "Assembling", "Wrangling",
        "Spelunking", "Unravelling", "Contemplating", "Deliberating", "Figuring"
    ]

    function randomThinkingVerb() {
        var v;
        do {
            v = thinkingVerbs[Math.floor(Math.random() * thinkingVerbs.length)] + "…";
        } while (v === currentActionText && thinkingVerbs.length > 1);
        return v;
    }

    function formatElapsed(sec) {
        if (sec < 60)
            return sec + "s";
        return Math.floor(sec / 60) + "m " + (sec % 60) + "s";
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.isClaudeCode && root.isTyping && root.claudeCodeStartedAt > 0
        onTriggered: root.claudeCodeElapsed = Math.floor((Date.now() - root.claudeCodeStartedAt) / 1000)
    }

    // A new verb every few seconds while nothing more specific (a tool) is shown.
    Timer {
        interval: 4000
        repeat: true
        running: root.isClaudeCode && root.isTyping && !root.claudeCodeToolRunning
        onTriggered: root.currentActionText = root.randomThinkingVerb()
    }

    // Short one-line description of a tool call for its card header.
    function toolSummary(name, input) {
        if (!input)
            return "";
        if (isAgentTool(name))
            return input.description || "";
        var s = input.command || input.skill || input.file_path || input.notebook_path || input.pattern
            || input.url || input.query || input.description || input.prompt || "";
        if (s === "" && name === "TodoWrite" && Array.isArray(input.todos))
            s = input.todos.length + " todos";
        if (s === "") {
            try { s = JSON.stringify(input); } catch (e) {}
        }
        s = String(s).replace(/\s+/g, " ").trim();
        return s.length > 200 ? s.substring(0, 200) + "…" : s;
    }

    function isAgentTool(name) {
        return name === "Agent" || name === "Task";
    }

    // "2 tools · 23.9k tokens · 6.6s" for a subagent card.
    function agentStatsText(t) {
        var parts = [];
        if (t.toolUses)
            parts.push(t.toolUses + (t.toolUses === 1 ? " tool" : " tools"));
        if (t.tokens)
            parts.push(formatTokens(t.tokens) + " tokens");
        if (t.durationMs)
            parts.push((t.durationMs / 1000).toFixed(1) + "s");
        return parts.join(" · ");
    }

    // Find the top-level card a (possibly nested) subagent event belongs to.
    function agentCardFor(proc, parentId) {
        var top = proc.agentOf[parentId] || parentId;
        return claudeCodeTool(proc, top);
    }

    function toolResultText(content) {
        var t = "";
        if (typeof content === "string")
            t = content;
        else if (Array.isArray(content))
            for (var i = 0; i < content.length; i++) {
                if (content[i].type === "text")
                    t += (t ? "\n" : "") + (content[i].text || "");
                else if (content[i].type === "image")
                    t += (t ? "\n" : "") + "[image]";
            }
        t = t.trim();
        return t.length > 2000 ? t.substring(0, 2000) + "\n…" : t;
    }

    function formatTokens(n) {
        n = n || 0;
        if (n >= 1000000) return (n / 1000000).toFixed(1) + "M";
        if (n >= 1000) return (n / 1000).toFixed(1) + "k";
        return String(n);
    }

    // "12.3s · 4 turns · 1.2k in / 800 out · $0.04" from the CLI's result event.
    function usageSummary(evt) {
        var parts = [];
        if (evt.duration_ms)
            parts.push((evt.duration_ms / 1000).toFixed(1) + "s");
        if (evt.num_turns)
            parts.push(evt.num_turns + (evt.num_turns === 1 ? " turn" : " turns"));
        var u = evt.usage;
        if (u) {
            var inTok = (u.input_tokens || 0) + (u.cache_read_input_tokens || 0) + (u.cache_creation_input_tokens || 0);
            parts.push(formatTokens(inTok) + " in / " + formatTokens(u.output_tokens) + " out");
        }
        if (typeof evt.total_cost_usd === "number")
            parts.push("$" + evt.total_cost_usd.toFixed(evt.total_cost_usd < 1 ? 3 : 2));
        return parts.join(" · ");
    }

    property var promptSuggestions: []

    property bool loadingSuggestions: false

    function fetchPromptSuggestions() {
        if (!isClaudeCode || loadingSuggestions)
            return;
        loadingSuggestions = true;
        promptSuggestions = [];

        var lines = [];
        for (var li = 0; li < chatHistory.count; li++) {
            var lm = chatHistory.get(li);
            if (!lm.isUser && !lm.isFinished)
                continue;
            var lt = (lm.text || "").trim();
            if (lt === "")
                continue;
            lines.push((lm.isUser ? "User" : "Assistant") + ": " + lt);
        }
        if (lines.length > 6)
            lines = lines.slice(lines.length - 6);
        var context = lines.join("\n");
        var draft = "";
        try {
            draft = (inputArea.text || "").trim();
        } catch (e) {}

        var prompt;
        if (context === "" && draft === "") {
            prompt = "Suggest exactly 4 short, varied example prompts a user might ask a helpful AI desktop assistant. Reply with ONLY a JSON array of 4 short strings, nothing else.";
        } else {
            prompt = "You are suggesting what the user might type NEXT in this chat. Based only on the context below, propose exactly 4 short, specific follow-up prompts they are likely to want to send next. Reply with ONLY a JSON array of 4 short strings, nothing else.\n\n";
            if (context !== "")
                prompt += "Conversation so far:\n" + context + "\n\n";
            if (draft !== "")
                prompt += "The user has started typing: \"" + draft + "\"\n\n";
        }

        var cmd = [claudeCodeBinPath(), "-p", prompt, "--output-format", "json"];
        var qml =
            "import QtQuick\n" +
            "import Quickshell.Io\n" +
            "Process {\n" +
            "    id: sp\n" +
            "    command: " + JSON.stringify(cmd) + "\n" +
            "    workingDirectory: " + JSON.stringify(claudeCodeCwd()) + "\n" +
            claudeCodeEnvSnippet() +
            "    stdout: StdioCollector { onStreamFinished: root.applyPromptSuggestions(text || \"\"); }\n" +
            "    onExited: code => { root.loadingSuggestions = false; sp.destroy(); }\n" +
            "}";
        try {
            var o = Qt.createQmlObject(qml, root, "promptSugProc");
            o.running = true;
        } catch (e) {
            loadingSuggestions = false;
            Logger.log("[AI] suggestion process error: " + e.message);
        }
    }

    function applyPromptSuggestions(text) {
        loadingSuggestions = false;
        var resultStr = "";
        try {
            resultStr = JSON.parse(text).result || "";
        } catch (e) {
            return;
        }
        var arr = null;
        try {
            arr = JSON.parse(resultStr);
        } catch (e) {
            var m = resultStr.match(/\[[\s\S]*\]/);
            if (m)
                try { arr = JSON.parse(m[0]); } catch (e2) {}
        }
        if (Array.isArray(arr)) {
            var list = [];
            for (var i = 0; i < arr.length && i < 6; i++)
                list.push(String(arr[i]));
            promptSuggestions = list;
        }
    }

    function claudeCodeSessionFor(chatId) {
        var active = GlobalConfig.ai.activeClaudeAccount || "";
        var c = claudeCodeSessions[chatId];
        if (c && c.acc === active)
            return c.sid;
        for (var i = 0; i < allChatSessions.length; i++)
            if (allChatSessions[i].id === chatId) {
                if ((allChatSessions[i].claudeCodeSessionAccount || "") === active)
                    return allChatSessions[i].claudeCodeSessionId || "";
                return "";
            }
        return "";
    }

    function setClaudeCodeSession(chatId, sid) {
        if (!sid)
            return;
        var active = GlobalConfig.ai.activeClaudeAccount || "";
        claudeCodeSessions[chatId] = { sid: sid, acc: active };
        for (var i = 0; i < allChatSessions.length; i++) {
            if (allChatSessions[i].id === chatId) {
                allChatSessions[i].claudeCodeSessionId = sid;
                allChatSessions[i].claudeCodeSessionAccount = active;
                break;
            }
        }
    }

    function withAttachmentList(text, paths) {
        if (!paths || paths.length === 0)
            return text;
        return ((text || "").trim() + "\n\nAttached files (use the Read tool to view them):\n"
            + paths.map(p => "- " + p).join("\n")).trim();
    }

    function claudeCodeTranscript() {
        var lines = [];
        var count = 0;
        for (var i = 0; i < chatHistory.count; i++) {
            var m = chatHistory.get(i);
            if (!m.isUser && !m.isFinished)
                continue;
            var t = (m.text || "").trim();
            if (m.isUser && (m.attachments || "") !== "")
                t = withAttachmentList(t, m.attachments.split("\n"));
            if (t === "")
                continue;
            lines.push((m.isUser ? "User: " : "Assistant: ") + t);
            count++;
        }
        if (count <= 1)
            return "";
        return "Continue this conversation. Conversation so far:\n\n" + lines.join("\n\n") + "\n\nReply to the last user message.";
    }

    readonly property bool isOpenaiCompat: root.openaiCompatProviders.indexOf(provider) !== -1

    // opencode is the exception: it is in the list above because it shares all of
    // that, but only for part of its catalogue — the rest needs Anthropic Messages,
    // and it authenticates with x-api-key. See opencodeWire() and setAuthHeader().
    readonly property bool isOpencode: provider === "opencode" || provider === "opencode-go"

    readonly property var openaiCompatProviders: ["openai", "gemini", "openrouter", "opencode", "opencode-go"]

    function openaiCompatBase(p) {
        const which = p || provider;
        if (which === "gemini")
            return GlobalConfig.ai.geminiUrl || "https://generativelanguage.googleapis.com/v1beta/openai";
        if (which === "openrouter")
            return GlobalConfig.ai.openrouterUrl || "https://openrouter.ai/api/v1";
        if (which === "opencode")
            return GlobalConfig.ai.opencodeUrl || "https://opencode.ai/zen/v1";
        if (which === "opencode-go")
            return GlobalConfig.ai.opencodeGoUrl || "https://opencode.ai/zen/go/v1";
        return GlobalConfig.ai.openaiUrl || "https://api.openai.com/v1";
    }

    readonly property var opencodeAnthropicPrefixes: ({
        "opencode": ["claude-", "qwen"],
        "opencode-go": ["minimax-", "qwen"]
    })

    readonly property var opencodeUnsupportedPrefixes: ({
        "opencode": ["gpt-", "gemini-"],
        "opencode-go": []
    })

    function opencodeWire(p, model) {
        const prefixes = root.opencodeAnthropicPrefixes[p] || [];
        for (var i = 0; i < prefixes.length; i++)
            if ((model || "").indexOf(prefixes[i]) === 0)
                return "anthropic";
        return "openai";
    }

    function opencodeSupports(p, model) {
        const prefixes = root.opencodeUnsupportedPrefixes[p] || [];
        for (var i = 0; i < prefixes.length; i++)
            if ((model || "").indexOf(prefixes[i]) === 0)
                return false;
        return true;
    }

    readonly property bool anthropicWire: isClaude || (isOpencode && opencodeWire(provider, activeModel()) === "anthropic")

    function setAuthHeader(xhr, p) {
        const which = p || provider;
        const key = root.getApiKeyFor(which);
        if (which === "opencode" || which === "opencode-go")
            xhr.setRequestHeader("x-api-key", key);
        else
            xhr.setRequestHeader("Authorization", "Bearer " + key);
    }

    property var keyringKeys: ({})

    function keyringOwner(p) {
        const which = p || provider;
        return which === "opencode-go" ? "opencode" : which;
    }

    function keyringAttr(p) {
        return "caelestia-ai-" + root.keyringOwner(p);
    }

    function loadKeyring(p) {
        const which = p || provider;
        const cmd = ["secret-tool", "lookup", "service", "caelestia", "key", root.keyringAttr(which)];
        const qml = 'import QtQuick\nimport Quickshell.Io\n' +
            'Process {\n    id: kp\n    command: ' + JSON.stringify(cmd) + '\n' +
            '    stdout: StdioCollector { onStreamFinished: root.onKeyringKey(' + JSON.stringify(which) + ', (text || "").trim(), kp); }\n' +
            '    onExited: code => { if (code !== 0) kp.destroy(); }\n}';
        try {
            const o = Qt.createQmlObject(qml, root, "keyringProc");
            o.running = true;
        } catch (e) {}
    }

    function onKeyringKey(p, key, proc) {
        if (key !== "") {
            const m = root.keyringKeys;
            m[p] = key;
            root.keyringKeys = Object.assign({}, m);
        }
        if (proc)
            proc.destroy();
    }

    function storeKeyring(p, key) {
        const which = root.keyringOwner(p || provider);
        const m = root.keyringKeys;
        m[which] = key;
        root.keyringKeys = Object.assign({}, m);

        const attr = root.keyringAttr(which);
        const script = key === ""
            ? "secret-tool clear service caelestia key " + JSON.stringify(attr)
            : "printf %s \"$CAELESTIA_AI_KEY\" | secret-tool store --label=" + JSON.stringify("Caelestia " + which + " API key") +
              " service caelestia key " + JSON.stringify(attr);
        try {
            const o = Qt.createQmlObject('import QtQuick\nimport Quickshell.Io\nProcess { id: sp; command: ' +
                JSON.stringify(["sh", "-c", script]) +
                '\n environment: ({ CAELESTIA_AI_KEY: ' + JSON.stringify(key) + ' })\n' +
                ' onExited: code => sp.destroy() }', root, "keyringStore");
            o.running = true;
        } catch (e) {}
    }

    function migratePlaintextKey(p, configKey) {
        const existing = (GlobalConfig.ai[configKey] || "").trim();
        if (existing === "")
            return;
        root.storeKeyring(p, existing);
        GlobalConfig.ai[configKey] = "";
        Logger.log("[AI] moved " + p + " API key from shell.json into the keyring");
    }

    function getApiKeyFor(p) {
        const which = p || provider;
        var envName = "ANTHROPIC_API_KEY";
        var configured = GlobalConfig.ai.anthropicApiKey;
        if (which === "openai") {
            envName = "OPENAI_API_KEY";
            configured = GlobalConfig.ai.openaiApiKey;
        } else if (which === "gemini") {
            envName = "GEMINI_API_KEY";
            configured = GlobalConfig.ai.geminiApiKey;
        } else if (which === "openrouter") {
            envName = "OPENROUTER_API_KEY";
            configured = GlobalConfig.ai.openrouterApiKey;
        } else if (which === "opencode" || which === "opencode-go") {
            envName = "OPENCODE_API_KEY";
            configured = GlobalConfig.ai.opencodeApiKey;
        }
        const envKey = Quickshell.env(envName);
        if (envKey && envKey.trim() !== "")
            return envKey.trim();

        const stored = root.keyringKeys[root.keyringOwner(which)];
        if (stored && stored !== "")
            return stored;
        return (configured || "").trim();
    }

    readonly property var legacyKeyFields: ({
        "claude": "anthropicApiKey",
        "openai": "openaiApiKey",
        "gemini": "geminiApiKey",
        "openrouter": "openrouterApiKey",
        "opencode": "opencodeApiKey"
    })

    function loadAllKeys() {
        for (const p in root.legacyKeyFields) {
            root.loadKeyring(p);
            root.migratePlaintextKey(p, root.legacyKeyFields[p]);
        }
    }

    function getApiKey() {
        return root.getApiKeyFor(root.provider);
    }

    readonly property bool needsApiKey: isClaude || isOpenaiCompat

    function activeModel() {
        if (isClaudeCode)
            return GlobalConfig.ai.defaultClaudeCodeModel || "default";
        if (isClaude)
            return GlobalConfig.ai.defaultClaudeModel || root.claudeModelsList[0] || "";
        if (isOpenaiCompat)
            return GlobalConfig.ai[root.defaultModelField(provider)] || root.openaiCompatModelList()[0] || "";
        return GlobalConfig.ai.defaultOllamaModel || root.ollamaModelsList[0] || "";
    }

    function defaultModelField(p) {
        const which = p || provider;
        if (which === "gemini")
            return "defaultGeminiModel";
        if (which === "openrouter")
            return "defaultOpenrouterModel";
        if (which === "opencode")
            return "defaultOpencodeModel";
        if (which === "opencode-go")
            return "defaultOpencodeGoModel";
        return "defaultOpenaiModel";
    }

    readonly property var providerList: {
        var l = [];
        if (GlobalConfig.ai.enableOllama)
            l.push("ollama");
        if (GlobalConfig.ai.enableClaudeCode)
            l.push("claude-code");
        if (GlobalConfig.ai.enableClaude)
            l.push("claude");
        if (GlobalConfig.ai.enableOpenai)
            l.push("openai");
        if (GlobalConfig.ai.enableGemini)
            l.push("gemini");
        if (GlobalConfig.ai.enableOpenrouter)
            l.push("openrouter");
        if (GlobalConfig.ai.enableOpencode)
            l.push("opencode");
        if (GlobalConfig.ai.enableOpencodeGo)
            l.push("opencode-go");
        if (l.length === 0)
            l.push("ollama");
        return l;
    }

    function providerLabel(p) {
        if (p === "claude-code")
            return "Claude Code";
        if (p === "claude")
            return "Claude API";
        if (p === "openai")
            return "ChatGPT";
        if (p === "gemini")
            return "Gemini";
        if (p === "openrouter")
            return "OpenRouter";
        if (p === "opencode")
            return "opencode Zen";
        if (p === "opencode-go")
            return "opencode Go";
        return "Ollama";
    }

    property bool isTyping: false

    property bool isThinking: false

    property string currentThoughtText: ""

    property bool isThoughtExpanded: false

    onIsTypingChanged: {
        if (isTyping) listView.positionViewAtEnd();
    }

    property bool inAgentLoop: false

    property int rateLimitRetries: 0

    readonly property int maxRateLimitRetries: 3

    property bool onFreeTier: false

    property int rateLimitSecondsLeft: 0

    function cancelRateLimitRetry(): void {
        rateLimitRetryTimer.stop();
        rateLimitRetryTimer.retryFn = null;
        rateLimitSecondsLeft = 0;
        rateLimitRetries = 0;
    }

    Timer {
        id: rateLimitRetryTimer

        interval: 1000
        repeat: true

        property var retryFn: null

        property string forChat: ""

        property string forModel: ""
        onTriggered: {
            root.rateLimitSecondsLeft--;
            if (root.rateLimitSecondsLeft > 0) {
                root.currentActionText = qsTr("Rate limited - retrying in %1s…").arg(root.rateLimitSecondsLeft);
                return;
            }
            stop();
            if (forChat !== root.currentChatId || forModel !== root.activeModel()) {
                retryFn = null;
                root.currentActionText = "";
                root.isTyping = false;
                root.isThinking = false;
                root.inAgentLoop = false;
                return;
            }
            if (retryFn) { const f = retryFn; retryFn = null; f(); }
        }
    }

    function rateLimitDelayMs(xhr) {
        const header = xhr.getResponseHeader("Retry-After");
        if (header && !isNaN(parseFloat(header)))
            return Math.ceil(parseFloat(header) * 1000) + 500;
        const m = /retry in ([0-9.]+)\s*s/i.exec(xhr.responseText || "");
        if (m)
            return Math.ceil(parseFloat(m[1]) * 1000) + 500;
        return 15000;
    }

    function shellQuote(str) {
        if (str === null || str === undefined) return "''";
        return "'" + String(str).replace(/'/g, "'\\''") + "'";
    }

    function parseTextToolCalls(text) {
        var calls = [];
        var startTag = "<tool_call>";
        var endTag = "</tool_call>";
        var pos = 0;
        while (true) {
            var start = text.indexOf(startTag, pos);
            if (start === -1) break;
            var end = text.indexOf(endTag, start);
            if (end === -1) break;
            var jsonStr = text.substring(start + startTag.length, end).trim();
            jsonStr = jsonStr.replace(/^```[a-zA-Z]*\n?/, "");
            jsonStr = jsonStr.replace(/```$/, "");
            jsonStr = jsonStr.trim();

            try {
                var parsed = JSON.parse(jsonStr);
                if (parsed.name) calls.push(parsed);
            } catch(e) { Logger.log("[AI] Bad tool_call JSON: " + jsonStr); }
            pos = end + endTag.length;
        }
        return calls;
    }

    function stripToolCalls(text) {
        var startTag = "<tool_call>";
        var endTag = "</tool_call>";
        var result = text;
        while (true) {
            var s = result.indexOf(startTag);
            if (s === -1) break;
            var e = result.indexOf(endTag, s);
            if (e === -1) { result = result.substring(0, s); break; }
            result = result.substring(0, s) + result.substring(e + endTag.length);
        }
        return result.replace(/\s+$/, '');
    }

    function runAgentCommand(cmd, type) {
        var commandStr = Array.isArray(cmd) ? JSON.stringify(cmd) : '["sh", "-c", ' + JSON.stringify("exec </dev/null; " + cmd) + ']';
        var processQml = "import QtQuick\n" +
                         "import Quickshell.Io\n" +
                         "Process {\n" +
                         "    id: proc\n" +
                         "    command: " + commandStr + "\n" +
                         "    property string outStr: \"\"\n" +
                         "    property string errStr: \"\"\n" +
                         "    property bool hasExited: false\n" +
                         "    property bool outFinished: false\n" +
                         "    property bool errFinished: false\n" +
                         "    function checkDone() {\n" +
                         "        if (hasExited && outFinished && errFinished) {\n" +
                         "            root.handleAgentProcessResult(" + JSON.stringify(type) + ", proc.outStr, proc.errStr, " + JSON.stringify(cmd) + ");\n" +
                         "            proc.destroy();\n" +
                         "        }\n" +
                         "    }\n" +
                         "    stdout: StdioCollector { onStreamFinished: { proc.outStr = text || \"\"; proc.outFinished = true; proc.checkDone(); } }\n" +
                         "    stderr: StdioCollector { onStreamFinished: { proc.errStr = text || \"\"; proc.errFinished = true; proc.checkDone(); } }\n" +
                         "    onExited: code => { proc.hasExited = true; proc.checkDone(); }\n" +
                         "}";
        try {
            var obj = Qt.createQmlObject(processQml, root, "agentProcess");
            obj.running = true;
        } catch(e) {
            console.error("AGENT PROCESS ERROR: " + e.message);
            console.error("FAILED QML: \n" + processQml);
        }
    }

    property int runningToolsCount: 0

    property string accumulatedToolResults: ""

    property string accumulatedToolImage: ""

    function handleAgentProcessResult(type, stdout, stderr, cmd) {
        if (type === "screenshot_take") {
            var convertCmd = `magick ${Paths.runtimeTemp("orion_screenshot.png")} -resize '1024x1024>' -quality 85 ${Paths.runtimeTemp("orion_screenshot.jpg")} && base64 ${Paths.runtimeTemp("orion_screenshot.jpg")}`;
            runAgentCommand(convertCmd, "screenshot_encode");
        } else if (type === "screenshot_encode") {
            var b64 = stdout.replace(/\n/g, "").trim();
            accumulatedToolImage = b64;
            accumulatedToolResults += "Result of take_screenshot:\nScreenshot taken. Analyze the attached image.\n\n";
            runningToolsCount--;
            checkToolsFinished();
        } else if (type.startsWith("exec_")) {
            var toolName = type.substring(5);
            var outText = stdout.trim();
            var errText = stderr.trim();
            if (!outText && !errText) {
                outText = "(Command completed with no output. If it was a background task, it has been launched successfully.)";
            }
            accumulatedToolResults += "Result of " + toolName + ":\n" + outText + (errText ? "\n\nErrors reported:\n" + errText : "") + "\n\n";
            runningToolsCount--;
            checkToolsFinished();
        }
    }

    function checkToolsFinished() {
        if (runningToolsCount <= 0) {
            var b64 = accumulatedToolImage ? accumulatedToolImage : null;
            sendPrompt(accumulatedToolResults.trim(), true, b64, "multi_tool");
        }
    }


    function claudeCodeCwd() {
        return claudeCodeChatCwd || Quickshell.env("HOME") || ".";
    }

    function claudeCodeBinPath() {
        var b = (GlobalConfig.ai.claudeCodeBin || "claude").trim();
        if (b === "" || b === "claude") {
            var home = Quickshell.env("HOME") || "";
            if (home !== "")
                return home + "/.local/bin/claude";
            return "claude";
        }
        return b;
    }

    function claudeCodePermissionArgs(mode) {
        mode = effectiveClaudeCodePermissionMode(mode);
        if (mode === "bypassPermissions")
            return ["--dangerously-skip-permissions"];
        if (mode === "default")
            return [];
        var args = ["--permission-mode", mode];
        // There is no approval prompt in the sidebar, so in accept-edits mode
        // commands, web access and reads outside the working directory would just
        // be denied. Allow them for sidebar sessions only; edits outside the
        // working directory still need permission.
        if (mode === "acceptEdits")
            args = args.concat(["--allowedTools", claudeCodeSidebarAllowedTools.join(",")]);
        return args;
    }

    function claudeAccounts() {
        var list = [{ "id": "", "name": "Default", "dir": "" }];
        try {
            var parsed = JSON.parse(GlobalConfig.ai.claudeAccountsJson || "[]");
            if (Array.isArray(parsed)) {
                var home = Quickshell.env("HOME") || "";
                for (var i = 0; i < parsed.length; i++) {
                    var a = parsed[i];
                    if (a && a.id)
                        list.push({
                            "id": String(a.id),
                            "name": String(a.name || a.id),
                            "dir": home + "/.config/caelestia/claude/" + String(a.id)
                        });
                }
            }
        } catch (e) {}
        return list;
    }

    function activeClaudeAccountObj() {
        var id = GlobalConfig.ai.activeClaudeAccount || "";
        var list = claudeAccounts();
        for (var i = 0; i < list.length; i++)
            if (list[i].id === id)
                return list[i];
        return list[0];
    }

    function activeClaudeConfigDir() {
        return activeClaudeAccountObj().dir || "";
    }

    property var resolvedAccountNames: ({})

    function accountJsonPath(id) {
        var home = Quickshell.env("HOME") || "";
        if (!id || id === "")
            return home + "/.claude.json";
        return home + "/.config/caelestia/claude/" + id + "/.claude.json";
    }

    function accountLabel(id) {
        if (resolvedAccountNames[id])
            return resolvedAccountNames[id];
        var list = claudeAccounts();
        for (var i = 0; i < list.length; i++)
            if (list[i].id === id)
                return list[i].name;
        return "Default";
    }

    Instantiator {
        model: root.claudeAccountIds
        delegate: FileView {
            required property string modelData

            path: root.accountJsonPath(modelData)
            printErrors: false
            watchChanges: false
            onLoaded: {
                try {
                    var d = JSON.parse(text());
                    var oa = d.oauthAccount || {};
                    var nm = oa.displayName || oa.emailAddress || "";
                    if (nm) {
                        var map = root.resolvedAccountNames;
                        map[modelData] = nm;
                        root.resolvedAccountNames = Object.assign({}, map);
                    }
                } catch (e) {}
            }
        }
    }

    readonly property var claudeAccountIds: {
        var l = [];
        var a = claudeAccounts();
        for (var i = 0; i < a.length; i++)
            l.push(a[i].id);
        return l;
    }

    function claudeCodeEnvSnippet() {
        var dir = activeClaudeConfigDir();
        if (dir && dir !== "")
            return "    environment: ({ \"CLAUDE_CONFIG_DIR\": " + JSON.stringify(dir) + " })\n";
        return "";
    }

    function logClaudeCodeStderr(proc, line) {
        if (!line)
            return;
        var t = line.trim();
        if (t === "")
            return;
        proc.errAcc = (proc.errAcc || "") + t + "\n";
        Logger.log("[ClaudeCode] " + t);
    }

    function isClaudeCodeAuthError(text) {
        if (!text)
            return false;
        var t = String(text).toLowerCase();
        return t.indexOf("login") !== -1
            || t.indexOf("log in") !== -1
            || t.indexOf("logged in") !== -1
            || t.indexOf("not authenticated") !== -1
            || t.indexOf("unauthorized") !== -1
            || t.indexOf("authentication") !== -1
            || t.indexOf("oauth") !== -1
            || t.indexOf("invalid api key") !== -1
            || t.indexOf("api key") !== -1
            || t.indexOf("expired") !== -1
            || t.indexOf("sign in") !== -1
            || t.indexOf("credentials") !== -1;
    }

    function claudeCodeAuthHint() {
        return "It appears that Claude is not logged into your account.\n\nOpen a terminal, run the command `claude`, and log in with your subscription, then try again here.";
    }

    function generateClaudeCodeTitleAsync(chatId, firstMessage) {
        if (!firstMessage)
            return;
        var safeMsg = firstMessage.substring(0, 200);
        var prompt = "Output ONLY a concise 2-4 word title for the following message. No quotes, no trailing punctuation, no explanation.\n\nMessage: " + safeMsg;

        var cmd = [claudeCodeBinPath(), "-p", prompt, "--output-format", "json"];
        var commandStr = JSON.stringify(cmd);
        var cwdStr = JSON.stringify(claudeCodeCwd());
        var chatIdStr = JSON.stringify(chatId);
        var qml =
            "import QtQuick\n" +
            "import Quickshell.Io\n" +
            "Process {\n" +
            "    id: tproc\n" +
            "    command: " + commandStr + "\n" +
            "    workingDirectory: " + cwdStr + "\n" +
            claudeCodeEnvSnippet() +
            "    stdout: StdioCollector { onStreamFinished: root.handleClaudeCodeTitle(" + chatIdStr + ", text || \"\", tproc); }\n" +
            "    onExited: code => { if (code !== 0) tproc.destroy(); }\n" +
            "}";
        try {
            var obj = Qt.createQmlObject(qml, root, "claudeCodeTitleProc");
            obj.running = true;
        } catch (e) {
            Logger.log("[AI] claude-code title process error: " + e.message);
        }
    }

    function handleClaudeCodeTitle(chatId, text, proc) {
        try {
            var parsed = JSON.parse(text);
            if (parsed && parsed.result && !parsed.is_error)
                applyGeneratedTitle(chatId, String(parsed.result));
        } catch (e) {}
        if (proc)
            proc.destroy();
    }

    function stopClaudeCode() {
        if (root.currentClaudeCodeProc) {
            try {
                root.currentClaudeCodeProc.stopped = true;
                root.currentClaudeCodeProc.running = false;
            } catch (e) {}
            root.currentClaudeCodeProc = null;
        }
    }

    function sendClaudeCode(promptText, attachments) {
        claudeCodeStartedAt = Date.now();
        claudeCodeElapsed = 0;
        claudeCodeOutTokens = 0;
        claudeCodeToolRunning = false;
        currentActionText = randomThinkingVerb();
        for (var i = chatHistory.count - 1; i >= 0; i--) {
            var m = chatHistory.get(i);
            if (!m.isUser && !m.isFinished && m.text === "" && (m.toolsJson || "") === "")
                chatHistory.remove(i);
        }
        chatHistory.append({
            "isUser": false,
            "text": "",
            "isFinished": false,
            "thoughtText": "",
            "toolsJson": "",
            "usageText": "",
            "attachments": ""
        });
        listView.positionViewAtEnd();

        var bin = claudeCodeBinPath();
        var sid = claudeCodeSessionFor(currentChatId);

        // Fresh session (new chat, the active account changed, or the working
        // directory changed) → seed it with the prior transcript so the conversation
        // carries over.
        var promptToSend = promptText;
        if (sid === "") {
            var transcript = claudeCodeTranscript();
            if (transcript !== "")
                promptToSend = transcript;
        }

        var cmd = [bin, "-p", promptToSend];

        // Attachments usually live outside the working directory (e.g. pasted
        // screenshots in the cache); allow the CLI to read them in any mode.
        var dirs = [];
        for (var a = 0; a < (attachments || []).length; a++) {
            var d = attachments[a].replace(/\/[^\/]*$/, "") || "/";
            if (dirs.indexOf(d) === -1)
                dirs.push(d);
        }
        if (dirs.length > 0)
            cmd = cmd.concat(["--add-dir"], dirs);

        cmd = cmd.concat(["--output-format", "stream-json", "--verbose", "--include-partial-messages"]);

        cmd = cmd.concat(claudeCodePermissionArgs(claudeCodePermissionMode));

        var mdl = GlobalConfig.ai.defaultClaudeCodeModel || "default";
        if (mdl && mdl !== "default") {
            cmd.push("--model");
            cmd.push(mdl);
        }

        var eff = GlobalConfig.ai.claudeCodeEffort || "default";
        if (eff && eff !== "default" && effortLevelsFor(mdl).indexOf(eff) !== -1) {
            cmd.push("--effort");
            cmd.push(eff);
        }

        if (sid !== "") {
            cmd.push("--resume");
            cmd.push(sid);
        }

        var commandStr = JSON.stringify(cmd);
        var cwdStr = JSON.stringify(claudeCodeCwd());
        var processQml =
            "import QtQuick\n" +
            "import Quickshell.Io\n" +
            "Process {\n" +
            "    id: proc\n" +
            "    command: " + commandStr + "\n" +
            "    workingDirectory: " + cwdStr + "\n" +
            claudeCodeEnvSnippet() +
            "    property string chatId: " + JSON.stringify(currentChatId) + "\n" +
            "    property int idx: " + (chatHistory.count - 1) + "\n" +
            "    property string acc: \"\"\n" +
            "    property string thought: \"\"\n" +
            "    property string sess: \"\"\n" +
            "    property string errAcc: \"\"\n" +
            "    property string usage: \"\"\n" +
            "    property var tools: []\n" +
            "    property bool needSep: false\n" +
            "    property bool thoughtSep: false\n" +
            "    property int doneTokens: 0\n" +
            "    property var agentOf: ({})\n" +
            "    property int msgChars: 0\n" +
            "    property bool stopped: false\n" +
            "    property bool done: false\n" +
            "    stdout: SplitParser { onRead: line => root.onClaudeCodeLine(proc, line) }\n" +
            "    stderr: SplitParser { onRead: line => root.logClaudeCodeStderr(proc, line) }\n" +
            "    onExited: code => root.onClaudeCodeExit(proc, code)\n" +
            "}";
        try {
            var obj = Qt.createQmlObject(processQml, root, "claudeCodeProc");
            root.currentClaudeCodeProc = obj;
            obj.running = true;
        } catch (e) {
            console.error("CLAUDE CODE PROCESS ERROR: " + e.message);
            chatHistory.setProperty(chatHistory.count - 1, "text", "⚠️ Failed to launch Claude Code: " + e.message);
            chatHistory.setProperty(chatHistory.count - 1, "isFinished", true);
            isTyping = false;
            isThinking = false;
            inAgentLoop = false;
            saveHistory();
        }
    }

    // Write to the bubble this process streams into, unless the user has since
    // switched to another chat.
    function setClaudeCodeBubble(proc, role, value) {
        if (proc.chatId !== currentChatId || proc.idx < 0 || proc.idx >= chatHistory.count)
            return;
        chatHistory.setProperty(proc.idx, role, value);
    }

    function updateClaudeCodeTools(proc) {
        setClaudeCodeBubble(proc, "toolsJson", proc.tools.length > 0 ? JSON.stringify(proc.tools) : "");
        if (proc.chatId === currentChatId)
            listView.positionViewAtEnd();
    }

    function claudeCodeTool(proc, id) {
        for (var i = 0; i < proc.tools.length; i++)
            if (proc.tools[i].id === id)
                return proc.tools[i];
        return null;
    }

    function appendClaudeCodeText(proc, text) {
        if (!text)
            return;
        // A new text block after a tool call (or a new assistant turn) starts a
        // new paragraph instead of running on from the previous sentence.
        if (proc.needSep && proc.acc.trim() !== "")
            proc.acc = proc.acc.replace(/\s+$/, "") + "\n\n";
        proc.needSep = false;
        proc.acc += text;
        if (isThinking)
            isThinking = false;
        setClaudeCodeBubble(proc, "text", proc.acc.trim());
        if (proc.chatId === currentChatId)
            listView.positionViewAtEnd();
    }

    function onClaudeCodeLine(proc, line) {
        line = (line || "").trim();
        if (line === "")
            return;

        var evt;
        try {
            evt = JSON.parse(line);
        } catch (e) {
            return;
        }

        if (evt.session_id)
            proc.sess = evt.session_id;

        if (evt.type === "system") {
            onClaudeCodeTaskEvent(proc, evt);
            return;
        }

        // Events from subagents (Task/Agent tool) belong to that tool's card, not
        // to the main reply.
        if (evt.parent_tool_use_id) {
            onClaudeCodeSubagentEvent(proc, evt);
            return;
        }

        if (evt.type === "stream_event" && evt.event) {
            var ev = evt.event;
            if (ev.type === "message_start") {
                proc.needSep = true;
                proc.msgChars = 0;
            } else if (ev.type === "message_delta" && ev.usage && ev.usage.output_tokens) {
                // The real count arrives once per message; until then it is estimated.
                proc.doneTokens += ev.usage.output_tokens;
                proc.msgChars = 0;
                if (proc.chatId === currentChatId)
                    claudeCodeOutTokens = proc.doneTokens;
            } else if (ev.type === "content_block_start" && ev.content_block) {
                var cb = ev.content_block;
                if (cb.type === "thinking")
                    proc.thoughtSep = true;
                if (cb.type === "tool_use") {
                    proc.needSep = true;
                    if (!claudeCodeTool(proc, cb.id)) {
                        proc.tools.push({ id: cb.id, name: cb.name || "tool", summary: "", result: "", isError: false, done: false });
                        updateClaudeCodeTools(proc);
                    }
                    currentActionText = "Running " + (cb.name || "tool") + "…";
                    claudeCodeToolRunning = true;
                    isThinking = true;
                }
            } else if (ev.type === "content_block_delta" && ev.delta) {
                proc.msgChars += (ev.delta.text || ev.delta.thinking || ev.delta.partial_json || "").length;
                if (proc.chatId === currentChatId)
                    claudeCodeOutTokens = proc.doneTokens + Math.round(proc.msgChars / 3);
                if (ev.delta.type === "text_delta") {
                    appendClaudeCodeText(proc, ev.delta.text || "");
                } else if (ev.delta.type === "thinking_delta") {
                    if (proc.thoughtSep && proc.thought.trim() !== "")
                        proc.thought = proc.thought.replace(/\s+$/, "") + "\n\n";
                    proc.thoughtSep = false;
                    proc.thought += ev.delta.thinking || "";
                    root.currentThoughtText = proc.thought.trim();
                    setClaudeCodeBubble(proc, "thoughtText", proc.thought.trim());
                }
            }
            return;
        }

        // Whole assistant messages carry the complete tool_use inputs; they are also
        // the fallback when token-level partials aren't emitted.
        if (evt.type === "assistant" && evt.message && evt.message.content) {
            var hasTool = false;
            var textPart = "";
            for (var i = 0; i < evt.message.content.length; i++) {
                var b = evt.message.content[i];
                if (b.type === "tool_use") {
                    hasTool = true;
                    var t = claudeCodeTool(proc, b.id);
                    if (!t) {
                        t = { id: b.id, name: b.name || "tool", summary: "", result: "", isError: false, done: false };
                        proc.tools.push(t);
                    }
                    t.summary = toolSummary(b.name, b.input);
                    if (b.name) {
                        currentActionText = "Running " + b.name + "…";
                        claudeCodeToolRunning = true;
                    }
                } else if (b.type === "text") {
                    textPart += b.text || "";
                }
            }
            if (hasTool)
                updateClaudeCodeTools(proc);
            if (textPart.trim() !== "" && proc.acc.indexOf(textPart.trim()) === -1) {
                proc.needSep = true;
                appendClaudeCodeText(proc, textPart);
            }
            if (hasTool)
                isThinking = true;
            return;
        }

        // Tool results come back as a user message.
        if (evt.type === "user" && evt.message && Array.isArray(evt.message.content)) {
            var changed = false;
            for (var j = 0; j < evt.message.content.length; j++) {
                var r = evt.message.content[j];
                if (r.type !== "tool_result")
                    continue;
                var tr = claudeCodeTool(proc, r.tool_use_id);
                if (!tr)
                    continue;
                tr.result = toolResultText(r.content);
                var tur = evt.tool_use_result;
                if (isAgentTool(tr.name) && tur && typeof tur === "object") {
                    if (tur.content)
                        tr.result = toolResultText(tur.content);
                    tr.toolUses = tur.totalToolUseCount || tr.toolUses || 0;
                    tr.tokens = tur.totalTokens || tr.tokens || 0;
                    tr.durationMs = tur.totalDurationMs || tr.durationMs || 0;
                }
                tr.isError = r.is_error === true;
                tr.done = true;
                tr.progress = "";
                changed = true;
            }
            if (changed) {
                updateClaudeCodeTools(proc);
                claudeCodeToolRunning = false;
                currentActionText = randomThinkingVerb();
            }
            return;
        }

        if (evt.type === "result") {
            var resText = (evt.result !== undefined && evt.result !== null) ? String(evt.result) : "";
            var errored = (evt.is_error === true) || (evt.subtype && String(evt.subtype).indexOf("error") !== -1);
            if (errored && (isClaudeCodeAuthError(resText) || isClaudeCodeAuthError(proc.errAcc))) {
                proc.acc = claudeCodeAuthHint();
            } else if (proc.acc.trim() === "" && resText !== "") {
                proc.acc = resText;
            } else if (errored && resText !== "" && proc.acc.indexOf(resText) === -1) {
                proc.acc = proc.acc.replace(/\s+$/, "") + "\n\n⚠️ " + resText;
            }
            proc.usage = usageSummary(evt);
            finalizeClaudeCode(proc);
            return;
        }
    }

    // task_started / task_progress / task_notification for subagents.
    function onClaudeCodeTaskEvent(proc, evt) {
        if (!evt.tool_use_id || String(evt.subtype || "").indexOf("task_") !== 0)
            return;
        var t = claudeCodeTool(proc, evt.tool_use_id);
        if (!t) {
            // A nested subagent: its progress rolls up into the top-level card.
            var top = agentCardFor(proc, evt.tool_use_id);
            if (top && top.id !== evt.tool_use_id && evt.description && evt.subtype === "task_progress") {
                top.progress = evt.description;
                updateClaudeCodeTools(proc);
            }
            return;
        }
        if (evt.subagent_type)
            t.agentType = evt.subagent_type;
        if (evt.subtype === "task_progress" && evt.description)
            t.progress = evt.description;
        if (evt.usage) {
            t.toolUses = evt.usage.tool_uses || t.toolUses || 0;
            t.tokens = evt.usage.total_tokens || t.tokens || 0;
            t.durationMs = evt.usage.duration_ms || t.durationMs || 0;
        }
        if (evt.subtype === "task_notification" && evt.status && evt.status !== "completed")
            t.isError = true;
        if (proc.chatId === currentChatId && evt.subtype === "task_progress" && t.progress !== "")
            currentActionText = t.progress.length > 40 ? t.progress.substring(0, 40) + "…" : t.progress;
        updateClaudeCodeTools(proc);
    }

    // Tool calls and results made inside a subagent, listed on its card.
    function onClaudeCodeSubagentEvent(proc, evt) {
        var card = agentCardFor(proc, evt.parent_tool_use_id);
        if (!card || !evt.message || !Array.isArray(evt.message.content))
            return;
        if (!card.steps)
            card.steps = [];
        var changed = false;
        for (var i = 0; i < evt.message.content.length; i++) {
            var b = evt.message.content[i];
            if (evt.type === "assistant" && b.type === "tool_use") {
                proc.agentOf[b.id] = card.id;
                card.steps.push({ id: b.id, name: b.name || "tool", summary: toolSummary(b.name, b.input), done: false, isError: false });
                changed = true;
            } else if (evt.type === "user" && b.type === "tool_result") {
                for (var j = 0; j < card.steps.length; j++)
                    if (card.steps[j].id === b.tool_use_id) {
                        card.steps[j].done = true;
                        card.steps[j].isError = b.is_error === true;
                        changed = true;
                    }
            }
        }
        // Long-running subagents: keep only the latest steps on the card.
        if (card.steps.length > 30)
            card.steps = card.steps.slice(card.steps.length - 30);
        if (changed)
            updateClaudeCodeTools(proc);
    }

    function finalizeClaudeCode(proc) {
        if (proc.done)
            return;
        proc.done = true;
        // A tool the CLI never answered (stopped, crashed) is no longer running.
        for (var i = 0; i < proc.tools.length; i++) {
            proc.tools[i].done = true;
            proc.tools[i].progress = "";
            var st = proc.tools[i].steps || [];
            for (var k = 0; k < st.length; k++)
                st[k].done = true;
        }
        var finalText = (proc.acc || "").trim();
        if (finalText === "" && proc.tools.length === 0)
            finalText = proc.stopped ? qsTr("(stopped)") : "(no output)";
        if (proc.sess !== "")
            setClaudeCodeSession(proc.chatId, proc.sess);
        if (proc.chatId === currentChatId) {
            setClaudeCodeBubble(proc, "text", finalText);
            setClaudeCodeBubble(proc, "toolsJson", proc.tools.length > 0 ? JSON.stringify(proc.tools) : "");
            setClaudeCodeBubble(proc, "usageText", proc.usage);
            setClaudeCodeBubble(proc, "isFinished", true);
            isTyping = false;
            isThinking = false;
            inAgentLoop = false;
            claudeCodeToolRunning = false;
            claudeCodeStartedAt = 0;
            currentActionText = "Thinking...";
            saveHistory();
            listView.positionViewAtEnd();
        } else {
            // The user moved to another chat meanwhile: store the finished reply
            // straight into that chat's saved history.
            var s = sessionEntry(proc.chatId);
            if (s && s.messages && proc.idx < s.messages.length) {
                var msg = s.messages[proc.idx];
                msg.text = finalText;
                msg.toolsJson = proc.tools.length > 0 ? JSON.stringify(proc.tools) : "";
                msg.usageText = proc.usage;
                msg.isFinished = true;
                GlobalConfig.ai.ollamaHistoryJson = JSON.stringify(allChatSessions);
            }
        }
    }

    function onClaudeCodeExit(proc, code) {
        if (!proc.done) {
            if ((proc.acc || "").trim() === "" && !proc.stopped) {
                if (isClaudeCodeAuthError(proc.errAcc)) {
                    proc.acc = claudeCodeAuthHint();
                } else if (code !== 0) {
                    var err = (proc.errAcc || "").trim();
                    var lines = err.split("\n");
                    if (lines.length > 20)
                        err = lines.slice(lines.length - 20).join("\n");
                    proc.acc = "⚠️ Claude Code exited with code " + code + "."
                        + (err !== "" ? "\n\n```\n" + err + "\n```" : "\n\nIs the `claude` CLI installed and logged in? Try running `claude` in a terminal.");
                }
            }
            finalizeClaudeCode(proc);
        }
        if (root.currentClaudeCodeProc === proc)
            root.currentClaudeCodeProc = null;
        proc.destroy();
    }

    property string currentActionText: "Thinking..."

    function fetchOllamaModels() {
        var ollamaUrl = GlobalConfig.ai.ollamaUrl || "http://localhost:11434";
        var xhr = new XMLHttpRequest();
        xhr.open("GET", ollamaUrl + "/api/tags", true);
        xhr.onreadystatechange = () => {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    try {
                        var response = JSON.parse(xhr.responseText);
                        var list = [];
                        if (response.models) {
                            for (var i = 0; i < response.models.length; i++) {
                                list.push(response.models[i].name);
                            }
                        }
                        ollamaModelsList = list;
                        if (list.length > 0 && list.indexOf(GlobalConfig.ai.defaultOllamaModel) === -1)
                            GlobalConfig.ai.defaultOllamaModel = list[0];
                    } catch (e) {
                        Logger.log("Error parsing Ollama models: " + e.message);
                    }
                } else {
                    Logger.log("Ollama tags request failed (status " + xhr.status + ")");
                }
            }
        };
        xhr.onerror = () => { root.logFetchError("Ollama"); };
        xhr.send();
    }

    property var openaiCompatModels: ({})

    function openaiCompatModelList(p) {
        return root.openaiCompatModels[p || provider] || [];
    }

    property var modelsFetched: ({})

    function fetchOpenaiCompatModels(p, force = false) {
        const which = p || provider;
        if (!force && root.modelsFetched[which])
            return;
        const key = root.getApiKeyFor(which);
        const publicCatalogue = which === "openrouter" || which === "opencode" || which === "opencode-go";
        if (key === "" && !publicCatalogue)
            return;

        var xhr = new XMLHttpRequest();
        xhr.open("GET", root.openaiCompatBase(which) + "/models", true);
        if (key !== "")
            root.setAuthHeader(xhr, which);
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            if (xhr.status !== 200) {
                Logger.log("[AI] " + root.providerLabel(which) + " model list failed (status " + xhr.status + ")");
                return;
            }
            try {
                const parsed = JSON.parse(xhr.responseText);
                var list = [];
                for (var i = 0; i < (parsed.data || []).length; i++) {
                    const id = parsed.data[i].id;
                    if (!id)
                        continue;
                    list.push(id.indexOf("models/") === 0 ? id.substring(7) : id);
                }
                list = list.filter(m => !/embed|whisper|tts|audio|image|vision-preview|moderation|rerank|dall-e/i.test(m));
                if (which === "opencode" || which === "opencode-go")
                    list = list.filter(m => root.opencodeSupports(which, m));
                list.sort();
                if (list.length === 0)
                    return;
                var next = {};
                for (var k in root.openaiCompatModels)
                    next[k] = root.openaiCompatModels[k];
                next[which] = list;
                root.openaiCompatModels = next;

                const seen = root.modelsFetched;
                seen[which] = true;
                root.modelsFetched = seen;

                const cfgKey = root.defaultModelField(which);
                if (list.indexOf(GlobalConfig.ai[cfgKey]) === -1)
                    GlobalConfig.ai[cfgKey] = list[0];
            } catch (e) {
                Logger.log("[AI] Error parsing " + root.providerLabel(which) + " models: " + e.message);
            }
        };
        xhr.onerror = () => { root.logFetchError(which); };
        xhr.send();
    }

    property var allChatSessions: []
    // Set while a saved chat is being put back into the list (no pop-in animation).
    property bool loadingChat: false

    function createNewChat() {
        cancelRateLimitRetry();
        typingTimer.stop();
        stopClaudeCode();
        isTyping = false;
        isThinking = false;
        inAgentLoop = false;
        currentChatId = "chat_" + Date.now();
        chatHistory.clear();
        pendingAttachments = [];
        isHistoryTab = false;
    }

    function loadChat(id) {
        cancelRateLimitRetry();
        typingTimer.stop();
        stopClaudeCode();
        isTyping = false;
        isThinking = false;
        inAgentLoop = false;
        currentChatId = id;
        chatHistory.clear();
        loadingChat = true;
        var found = false;
        for (var i = 0; i < allChatSessions.length; i++) {
            if (allChatSessions[i].id === id) {
                var msgs = allChatSessions[i].messages;
                for (var j = 0; j < msgs.length; j++) {
                    chatHistory.append({
                        "isUser": msgs[j].isUser === true,
                        "text": msgs[j].text || "",
                        "isFinished": msgs[j].isFinished !== false,
                        "thoughtText": msgs[j].thoughtText || "",
                        "toolsJson": msgs[j].toolsJson || "",
                        "usageText": msgs[j].usageText || "",
                        "attachments": msgs[j].attachments || ""
                    });
                }
                claudeCodeChatCwd = allChatSessions[i].claudeCodeCwd || Quickshell.env("HOME") || ".";
                claudeCodePermissionMode = allChatSessions[i].claudeCodePermissionMode || defaultClaudeCodePermissionMode();
                found = true;
                break;
            }
        }
        if (!found) createNewChat();
        Qt.callLater(function() { root.loadingChat = false; });
        savedContentY = -1;
        Qt.callLater(function() { listView.positionViewAtEnd(); });
        isHistoryTab = false;
    }

    function loadHistory() {
        allChatSessions = [];
        var jsonStr = GlobalConfig.ai.ollamaHistoryJson;
        if (jsonStr) {
            try {
                var parsed = JSON.parse(jsonStr);
                if (Array.isArray(parsed)) {
                    allChatSessions = parsed.filter(s => s !== null && s.id);
                }
            } catch (e) {}
        }

        historySessionsModel.clear();
        for (var i = 0; i < allChatSessions.length; i++) {
            historySessionsModel.append({
                "id": allChatSessions[i].id || ("chat_" + Date.now()),
                "title": allChatSessions[i].title || "Chat"
            });
        }

        if (allChatSessions.length > 0) {
            loadChat(allChatSessions[0].id);
        } else {
            createNewChat();
        }
    }

    function saveHistory() {
        if (!GlobalConfig.ai.saveChatHistory)
            return;
        var msgs = [];
        for (var i = 0; i < chatHistory.count; i++) {
            var msg = chatHistory.get(i);
            msgs.push({
                "isUser": msg.isUser === true,
                "text": msg.text || "",
                "isFinished": msg.isFinished !== false,
                "thoughtText": msg.thoughtText || "",
                "toolsJson": msg.toolsJson || "",
                "usageText": msg.usageText || "",
                "attachments": msg.attachments || ""
            });
        }
        
        if (msgs.length === 0) return;
        
        var found = false;
        for (var j = 0; j < allChatSessions.length; j++) {
            if (allChatSessions[j].id === currentChatId) {
                allChatSessions[j].messages = msgs;
                allChatSessions[j].claudeCodeCwd = claudeCodeChatCwd;
                allChatSessions[j].claudeCodePermissionMode = claudeCodePermissionMode;
                
                var firstUser = null;
                for (var k = 0; k < msgs.length; k++) {
                    if (msgs[k].isUser) { firstUser = msgs[k]; break; }
                }
                if (msgs.length > 1 && (allChatSessions[j].title === "Legacy Chat" || allChatSessions[j].title === "New Chat" || allChatSessions[j].title.indexOf("New Chat") === 0 || !allChatSessions[j].title)) {
                    if (firstUser) {
                        generateChatTitleAsync(currentChatId, firstUser.text);
                    }
                }
                found = true;
                break;
            }
        }
        
        if (!found) {
            var firstUserMsg = null;
            for (var m = 0; m < msgs.length; m++) {
                if (msgs[m].isUser) { firstUserMsg = msgs[m]; break; }
            }
            
            var initialTitle = "New Chat";
            
            allChatSessions.unshift({
                "id": currentChatId || ("chat_" + Date.now()),
                "title": initialTitle,
                "messages": msgs,
                "claudeCodeCwd": claudeCodeChatCwd,
                "claudeCodePermissionMode": claudeCodePermissionMode
            });
            
            historySessionsModel.insert(0, {
                "id": currentChatId || ("chat_" + Date.now()),
                "title": initialTitle
            });
            
            if (firstUserMsg) {
                generateChatTitleAsync(currentChatId, firstUserMsg.text);
            }
        }
        
        GlobalConfig.ai.ollamaHistoryJson = JSON.stringify(allChatSessions);
    }

    function deleteChat(id) {
        cancelRateLimitRetry();
        var idx = -1;
        for (var i = 0; i < allChatSessions.length; i++) {
            if (allChatSessions[i].id === id) {
                idx = i;
                break;
            }
        }
        if (idx !== -1) {
            allChatSessions.splice(idx, 1);
            for (var j = 0; j < historySessionsModel.count; j++) {
                if (historySessionsModel.get(j).id === id) {
                    historySessionsModel.remove(j);
                    break;
                }
            }
            
            GlobalConfig.ai.ollamaHistoryJson = JSON.stringify(allChatSessions);

            if (currentChatId === id) {
                chatHistory.clear();
                if (allChatSessions.length > 0) {
                    loadChat(allChatSessions[0].id);
                } else {
                    createNewChat();
                }
            }
        }
    }

    function clearAllHistory() {
        cancelRateLimitRetry();
        allChatSessions = [];
        historySessionsModel.clear();
        GlobalConfig.ai.ollamaHistoryJson = "[]";
        createNewChat();
    }

    function applyGeneratedTitle(chatId, raw) {
        if (!raw)
            return;
        var title = raw.trim().replace(/^"|"$/g, '').replace(/\n/g, ' ');
        if (title.length > 40)
            title = title.substring(0, 40) + "...";
        if (title.length > 0)
            updateChatTitle(chatId, title);
    }

    function generateChatTitleAsync(chatId, firstMessage) {
        if (!firstMessage) return;

        if (root.isClaudeCode) {
            root.generateClaudeCodeTitleAsync(chatId, firstMessage);
            return;
        }

        var safeMsg = firstMessage.substring(0, 200);
        var titleSystem = "You are a title generator. Output ONLY a 2-4 word title representing the user's message. NO quotes, NO explanation.";
        var xhr = new XMLHttpRequest();

        if (root.isClaude) {
            if (root.getApiKey() === "")
                return;
            var claudeBase = GlobalConfig.ai.anthropicUrl || "https://api.anthropic.com";
            xhr.open("POST", claudeBase + "/v1/messages", true);
            xhr.setRequestHeader("Content-Type", "application/json");
            xhr.setRequestHeader("x-api-key", root.getApiKey());
            xhr.setRequestHeader("anthropic-version", "2023-06-01");
            xhr.setRequestHeader("anthropic-dangerous-direct-browser-access", "true");
            xhr.onreadystatechange = () => {
                if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                    try {
                        var parsed = JSON.parse(xhr.responseText);
                        if (parsed.content && parsed.content.length > 0 && parsed.content[0].text)
                            root.applyGeneratedTitle(chatId, parsed.content[0].text);
                    } catch (e) {}
                }
            };
            xhr.onerror = () => {};
            xhr.send(JSON.stringify({
                model: root.activeModel(),
                max_tokens: 32,
                system: titleSystem,
                messages: [{ role: "user", content: "Message: " + safeMsg + "\nTitle:" }]
            }));
            return;
        }

        if (root.isOpenaiCompat) {
            if (root.getApiKey() === "")
                return;
            const useAnthropic = root.anthropicWire;
            xhr.open("POST", root.openaiCompatBase() + (useAnthropic ? "/messages" : "/chat/completions"), true);
            xhr.setRequestHeader("Content-Type", "application/json");
            root.setAuthHeader(xhr);
            if (useAnthropic)
                xhr.setRequestHeader("anthropic-version", "2023-06-01");
            xhr.onreadystatechange = () => {
                if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                    try {
                        var oaiParsed = JSON.parse(xhr.responseText);
                        if (useAnthropic) {
                            if (oaiParsed.content && oaiParsed.content.length > 0 && oaiParsed.content[0].text)
                                root.applyGeneratedTitle(chatId, oaiParsed.content[0].text);
                        } else if (oaiParsed.choices && oaiParsed.choices.length > 0 && oaiParsed.choices[0].message) {
                            root.applyGeneratedTitle(chatId, oaiParsed.choices[0].message.content || "");
                        }
                    } catch (e) {}
                }
            };
            xhr.onerror = () => {};
            xhr.send(JSON.stringify(useAnthropic ? {
                model: root.activeModel(),
                max_tokens: 32,
                system: titleSystem,
                messages: [{ role: "user", content: "Message: " + safeMsg + "\nTitle:" }]
            } : {
                model: root.activeModel(),
                messages: [
                    { role: "system", content: titleSystem },
                    { role: "user", content: "Message: " + safeMsg + "\nTitle:" }
                ],
                stream: false
            }));
            return;
        }

        var url = (GlobalConfig.ai.ollamaUrl || "http://localhost:11434") + "/api/generate";
        xhr.open("POST", url, true);
        xhr.setRequestHeader("Content-Type", "application/json");
        xhr.onreadystatechange = () => {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                try {
                    var parsed = JSON.parse(xhr.responseText);
                    if (parsed.response)
                        root.applyGeneratedTitle(chatId, parsed.response);
                } catch (e) {}
            }
        };
        xhr.onerror = () => {};
        xhr.send(JSON.stringify({
            model: GlobalConfig.ai.defaultOllamaModel || "llama3",
            system: titleSystem,
            prompt: "Message: " + safeMsg + "\nTitle:",
            stream: false
        }));
    }

    function updateChatTitle(chatId, title) {
        if (!title || !chatId) return;
        
        for (var i = 0; i < allChatSessions.length; i++) {
            if (allChatSessions[i].id === chatId) {
                allChatSessions[i].title = title;
                
                var inModel = false;
                for (var j = 0; j < historySessionsModel.count; j++) {
                    if (historySessionsModel.get(j).id === chatId) {
                        historySessionsModel.setProperty(j, "title", title);
                        inModel = true;
                        break;
                    }
                }
                
                if (!inModel) {
                    historySessionsModel.insert(0, {
                        "id": chatId || "",
                        "title": title || "New Chat"
                    });
                }
                
                GlobalConfig.ai.ollamaHistoryJson = JSON.stringify(allChatSessions);
                break;
            }
        }
    }

    function addAiMessage(message) {
        chatHistory.append({
            "isUser": false,
            "text": message || "",
            "isFinished": true,
            "thoughtText": "",
            "toolsJson": "",
            "usageText": "",
            "attachments": ""
        });
        listView.positionViewAtEnd();
        saveHistory();
    }

    function sendPrompt(promptText, isSystemToolResult = false, base64Image = null, toolName = "", isRetry = false) {
        var attachments = (!isSystemToolResult && !isRetry && root.isClaudeCode) ? pendingAttachments.map(a => a.path) : [];
        if (!promptText.trim() && !base64Image && attachments.length === 0) return;
        pendingAttachments = [];

        promptSuggestions = [];

        if (!isRetry)
            cancelRateLimitRetry();

        if (!isSystemToolResult && !isRetry) {
            chatHistory.append({
                "isUser": true,
                "text": promptText || "",
                "isFinished": true,
                "thoughtText": "",
                "toolsJson": "",
                "usageText": "",
                "attachments": attachments.join("\n")
            });
            listView.positionViewAtEnd();
            saveHistory();
        }

        if (root.needsApiKey && root.getApiKey() === "") {
            const envNames = {
                "claude": "ANTHROPIC_API_KEY",
                "openai": "OPENAI_API_KEY",
                "gemini": "GEMINI_API_KEY",
                "openrouter": "OPENROUTER_API_KEY",
                "opencode": "OPENCODE_API_KEY",
                "opencode-go": "OPENCODE_API_KEY"
            };
            addAiMessage("⚠️ No " + root.providerLabel(root.provider) + " API key configured. Set the "
                + (envNames[root.provider] || "API") + " environment variable, or add a key in the AI settings.");
            return;
        }

        isTyping = true;
        isThinking = true;
        inAgentLoop = true;
        currentThoughtText = "";
        isThoughtExpanded = false;
        
        if (isSystemToolResult) {
            if (toolName === "web_search" || toolName === "read_webpage") {
                currentActionText = "Reading results...";
            } else if (toolName === "take_screenshot") {
                currentActionText = "Analyzing screen...";
            } else if (toolName === "get_weather") {
                currentActionText = "Analyzing weather...";
            } else {
                currentActionText = "Thinking...";
            }
        } else {
            currentActionText = "Thinking...";
        }

        if (root.isClaudeCode) {
            root.sendClaudeCode(withAttachmentList(promptText, attachments), attachments);
            return;
        }

        var xhr = new XMLHttpRequest();
        root.currentRequest = xhr;

        var model = root.activeModel();
        const useAnthropic = root.anthropicWire;
        if (root.isClaude) {
            var claudeBase = GlobalConfig.ai.anthropicUrl || "https://api.anthropic.com";
            xhr.open("POST", claudeBase + "/v1/messages", true);
            xhr.setRequestHeader("Content-Type", "application/json");
            xhr.setRequestHeader("x-api-key", root.getApiKey());
            xhr.setRequestHeader("anthropic-version", "2023-06-01");
            xhr.setRequestHeader("anthropic-dangerous-direct-browser-access", "true");
        } else if (root.isOpenaiCompat) {
            xhr.open("POST", root.openaiCompatBase() + (useAnthropic ? "/messages" : "/chat/completions"), true);
            xhr.setRequestHeader("Content-Type", "application/json");
            root.setAuthHeader(xhr);
            if (useAnthropic)
                xhr.setRequestHeader("anthropic-version", "2023-06-01");
            if (root.provider === "openrouter") {
                xhr.setRequestHeader("HTTP-Referer", "https://github.com/ladybug-me/caelestia-kde");
                xhr.setRequestHeader("X-Title", "Caelestia Shell");
            }
        } else {
            var ollamaUrl = GlobalConfig.ai.ollamaUrl || "http://localhost:11434";
            xhr.open("POST", ollamaUrl + "/api/chat", true);
            xhr.setRequestHeader("Content-Type", "application/json");
        }
        
        var processedTextLength = 0;
        var accumulatedThoughtText = "";
        var accumulatedContentText = "";
        var rawAccumulatedContentText = "";
        var finalToolCalls = null;
        
        for (var i = chatHistory.count - 1; i >= 0; i--) {
            var m = chatHistory.get(i);
            if (!m.isUser && !m.isFinished && m.text === "") {
                chatHistory.remove(i);
            }
        }
        
        chatHistory.append({
            "isUser": false,
            "text": "",
            "isFinished": false,
            "thoughtText": "",
            "toolsJson": "",
            "usageText": "",
            "attachments": ""
        });
        
        listView.positionViewAtEnd();
        
        xhr.onerror = () => { root.handleSendError(); };
        xhr.onreadystatechange = () => {
            if (xhr.readyState === 3 || xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    var currentText = xhr.responseText;
                    var unparsed = currentText.substring(processedTextLength);
                    var lines = unparsed.split('\n');
                    
                    var linesToProcess = (xhr.readyState === XMLHttpRequest.DONE) ? lines.length : lines.length - 1;
                    
                    for (var i = 0; i < linesToProcess; i++) {
                        var rawLine = lines[i];
                        var line = rawLine.trim();
                        if (line === "") {
                            processedTextLength += rawLine.length + 1;
                            continue;
                        }

                        var chunkContent = "";
                        var chunkReasoning = "";

                        if (useAnthropic) {
                            if (line.indexOf("event:") === 0) {
                                processedTextLength += rawLine.length + 1;
                                continue;
                            }
                            if (line.indexOf("data:") !== 0) {
                                processedTextLength += rawLine.length + 1;
                                continue;
                            }
                            var jsonStr = line.substring(5).trim();
                            if (jsonStr === "" || jsonStr === "[DONE]") {
                                processedTextLength += rawLine.length + 1;
                                continue;
                            }
                            try {
                                var evt = JSON.parse(jsonStr);
                                processedTextLength += rawLine.length + 1;
                                if (evt.type === "content_block_delta" && evt.delta) {
                                    if (evt.delta.type === "text_delta")
                                        chunkContent = evt.delta.text || "";
                                    else if (evt.delta.type === "thinking_delta")
                                        chunkReasoning = evt.delta.thinking || "";
                                } else if (evt.type === "error") {
                                    Logger.log("[AI] Claude stream error: " + JSON.stringify(evt.error || {}));
                                }
                            } catch (e) {
                                break;
                            }
                        } else if (root.isOpenaiCompat) {
                            if (line.indexOf("data:") !== 0) {
                                processedTextLength += rawLine.length + 1;
                                continue;
                            }
                            var oaiJson = line.substring(5).trim();
                            if (oaiJson === "" || oaiJson === "[DONE]") {
                                processedTextLength += rawLine.length + 1;
                                continue;
                            }
                            try {
                                var oaiEvt = JSON.parse(oaiJson);
                                processedTextLength += rawLine.length + 1;
                                if (oaiEvt.error) {
                                    Logger.log("[AI] " + root.providerLabel(root.provider) + " stream error: " + JSON.stringify(oaiEvt.error));
                                } else if (oaiEvt.choices && oaiEvt.choices.length > 0) {
                                    var delta = oaiEvt.choices[0].delta || {};
                                    chunkContent = delta.content || "";
                                    chunkReasoning = delta.reasoning_content || delta.reasoning || "";
                                }
                            } catch (e) {
                                break;
                            }
                        } else {
                            try {
                                var parsed = JSON.parse(line);
                                processedTextLength += rawLine.length + 1;
                                if (parsed.message) {
                                    chunkReasoning = parsed.message.thinking || parsed.message.reasoning || parsed.message.reasoning_content || "";
                                    chunkContent = parsed.message.content || "";
                                }
                            } catch (e) {
                                break;
                            }
                        }

                        if (chunkReasoning)
                            accumulatedThoughtText += chunkReasoning;
                        if (chunkContent)
                            rawAccumulatedContentText += chunkContent;

                        if (chunkContent === "" && chunkReasoning === "")
                            continue;

                        var displayContent = stripToolCalls(rawAccumulatedContentText);
                        var displayThought = accumulatedThoughtText;

                        if (accumulatedThoughtText === "") {
                            var openThinkIdx = displayContent.indexOf("<think>");
                            var closeThinkIdx = displayContent.indexOf("</think>");

                            if (openThinkIdx !== -1) {
                                if (closeThinkIdx !== -1) {
                                    displayThought = displayContent.substring(openThinkIdx + 7, closeThinkIdx).trim();
                                    displayContent = displayContent.substring(0, openThinkIdx) + displayContent.substring(closeThinkIdx + 8);
                                } else {
                                    displayThought = displayContent.substring(openThinkIdx + 7).trim();
                                    displayContent = displayContent.substring(0, openThinkIdx);
                                }
                            }
                        }

                        root.currentThoughtText = displayThought.trim();

                        if (displayContent.trim() !== "") {
                            if (isThinking) isThinking = false;
                        }

                        chatHistory.setProperty(chatHistory.count - 1, "thoughtText", displayThought.trim());
                        chatHistory.setProperty(chatHistory.count - 1, "text", displayContent.trim());
                        listView.positionViewAtEnd();
                    }
                }
                
                if (xhr.readyState === XMLHttpRequest.DONE) {
                    if (xhr.status === 200) {
                            root.rateLimitRetries = 0;
                    chatHistory.setProperty(chatHistory.count - 1, "isFinished", true);
                        saveHistory();
                        
                        var enableTools = GlobalConfig.ai.enableCelestialMode;
                        var textToolCalls = enableTools ? parseTextToolCalls(rawAccumulatedContentText) : [];

                        if (textToolCalls.length > 0) {
                            if (enableTools) {
                                currentActionText = "Using tools...";
                                accumulatedToolResults = "";
                                accumulatedToolImage = "";
                                runningToolsCount = 0;

                                for (var t = 0; t < textToolCalls.length; t++) {
                                    var toolCall = textToolCalls[t];
                                    var toolName = toolCall.name;
                                    var args = toolCall.args || {};

                                    if (toolName === "take_screenshot" || toolName === "web_search" || toolName === "read_webpage" || toolName === "open_app" || toolName === "caelestia_command") {
                                        runningToolsCount++;
                                    }

                                    if (toolName === "take_screenshot") {
                                        currentActionText = "Analyzing screen...";
                                        var screenCmd = `spectacle -b -m -n -o ${Paths.runtimeTemp("orion_screenshot.png")}`;
                                        runAgentCommand(screenCmd, "screenshot_take");

                                    } else if (toolName === "web_search") {
                                        currentActionText = "Searching the web...";
                                        var query = String(args.query || "");
                                        var page = args.page || 1;
                                        runAgentCommand(["env", "PYTHONIOENCODING=utf8", "python3", Quickshell.shellDir + "/scripts/orion_search.py", "--mode", "search", "--query", query, "--page", String(page)], "exec_" + toolName);

                                    } else if (toolName === "read_webpage") {
                                        currentActionText = "Reading webpage...";
                                        var url = String(args.url || "");
                                        runAgentCommand(["env", "PYTHONIOENCODING=utf8", "python3", Quickshell.shellDir + "/scripts/orion_search.py", "--mode", "read", "--url", url], "exec_" + toolName);

                                    } else if (toolName === "open_app") {
                                        currentActionText = "Opening app...";
                                        var app = String(args.app_name || "");
                                        var safeApp = shellQuote("Name=.*" + app);
                                        runAgentCommand(["sh", "-c", 'grep -i -m 1 "^Exec=" $(find /usr/share/applications ~/.local/share/applications -name "*.desktop" -exec grep -il "$1" {} + 2>/dev/null) | cut -d "=" -f 2- | sed "s/ %[a-zA-Z]//g" | xargs -I {} sh -c "setsid {} >/dev/null 2>&1 &"', "--", safeApp], "exec_" + toolName);

                                    } else if (toolName === "set_timer") {
                                        currentActionText = "Setting timer...";
                                        var secs = Number(args.seconds) || 5;
                                        var msg = String(args.message || "Timer finished");
                                        var timerQml = "import QtQuick; Timer { interval: " + (secs * 1000) + "; running: true; onTriggered: { root.runAgentCommand(['notify-send', 'Orion Timer', " + JSON.stringify(msg) + "], 'timer_trigger'); destroy(); } }";
                                        Qt.createQmlObject(timerQml, root, "timer_" + Date.now());
                                        accumulatedToolResults += "Tool: set_timer\nResult: Timer set for " + secs + " seconds with message: " + msg + "\n\n";

                                    } else if (toolName === "get_weather") {
                                        currentActionText = "Checking weather...";
                                        var weatherStr = Weather.city + ": " + Weather.temp + " (" + Weather.description + "). Humidity: " + Weather.humidity + "%, Wind: " + Weather.windSpeed + " km/h";
                                        accumulatedToolResults += "Tool: get_weather\nResult: Local weather from system dashboard: " + weatherStr + "\n\n";

                                    } else if (toolName === "caelestia_command") {
                                        currentActionText = "Running caelestia...";
                                        var subcmd = String(args.subcommand || "");
                                        var subargs = String(args.args || "").trim();
                                        var cmdArr = ["caelestia", subcmd];
                                        if (subargs) cmdArr = cmdArr.concat(subargs.split(/\s+/));
                                        runAgentCommand(cmdArr, "exec_" + toolName);

                                    } else {
                                        Logger.log("[AI] Unknown tool: " + toolName);
                                        runningToolsCount--;
                                    }
                                }

                                if (runningToolsCount === 0) {
                                    if (accumulatedToolResults !== "") {
                                        checkToolsFinished();
                                    } else {
                                        currentActionText = "Thinking...";
                                        isTyping = false;
                                        isThinking = false;
                                        inAgentLoop = false;
                                    }
                                }
                            } else {
                                currentActionText = "Thinking...";
                                isTyping = false;
                                isThinking = false;
                                inAgentLoop = false;
                            }
                        } else {
                            currentActionText = "Thinking...";
                            isTyping = false;
                            isThinking = false;
                            inAgentLoop = false;
                        }
                    } else {
                        var providerName = root.providerLabel(root.provider);
                        var apiDetail = "";
                        try {
                            const errBody = JSON.parse(xhr.responseText);
                            const e = Array.isArray(errBody) ? (errBody[0] || {}).error : errBody.error;
                            if (e) {
                                const raw = e.metadata && e.metadata.raw ? String(e.metadata.raw) : "";
                                const provider = e.metadata && e.metadata.provider_name ? String(e.metadata.provider_name) : "";
                                if (raw)
                                    apiDetail = " " + (provider ? provider + ": " : "") + raw.split("\n")[0];
                                else if (e.message)
                                    apiDetail = " " + String(e.message).split("\n")[0];
                            }
                        } catch (e) {}
                        const perDayQuota = /PerDay|per day/i.test(xhr.responseText || "");
                        if (xhr.status === 429 && perDayQuota)
                            root.cancelRateLimitRetry();

                        if (xhr.status === 429 && !perDayQuota && root.rateLimitRetries < root.maxRateLimitRetries) {
                            if ((xhr.responseText || "").indexOf("free_tier") !== -1)
                                root.onFreeTier = true;
                            const waitMs = root.rateLimitDelayMs(xhr);
                            root.rateLimitRetries++;
                            root.rateLimitSecondsLeft = Math.max(1, Math.round(waitMs / 1000));
                            root.currentActionText = qsTr("Rate limited - retrying in %1s…").arg(root.rateLimitSecondsLeft);
                            root.isTyping = true;
                            root.isThinking = true;
                            rateLimitRetryTimer.forChat = root.currentChatId;
                            rateLimitRetryTimer.forModel = root.activeModel();
                            rateLimitRetryTimer.retryFn = () => root.sendPrompt(promptText, isSystemToolResult, base64Image, toolName, true);
                            rateLimitRetryTimer.restart();
                            return;
                        }

                        var hint = "";
                        if (xhr.status === 429 && perDayQuota)
                            hint = " This model's daily free quota is used up - it resets tomorrow. Pick another model, or use Claude Code, which is not on this quota.";
                        else if (xhr.status === 429)
                            hint = " Rate limit reached and still limited after " + root.maxRateLimitRetries + " retries - wait a minute and try again.";
                        else if (root.needsApiKey && (xhr.status === 401 || xhr.status === 403))
                            hint = " Check your API key.";
                        var errMsg = (xhr.status === 0) ? "Generation canceled" : (providerName + " request failed (status " + xhr.status + ")." + hint + apiDetail);
                        var currentText = chatHistory.get(chatHistory.count - 1).text;
                        if (currentText.trim() === "") {
                            chatHistory.setProperty(chatHistory.count - 1, "text", errMsg);
                        } else {
                            chatHistory.setProperty(chatHistory.count - 1, "text", currentText + "\n\n*[" + errMsg + "]*");
                        }
                        chatHistory.setProperty(chatHistory.count - 1, "isFinished", true);
                        isTyping = false;
                        isThinking = false;
                        inAgentLoop = false;
                        saveHistory();
                    }
                }
            }
        };

        var enableTools = GlobalConfig.ai.enableCelestialMode;
        var sysPrompt = "You are a helpful AI assistant integrated into the user's desktop OS shell (Caelestia, running on KDE Plasma/Wayland).";
        if (enableTools) {
            sysPrompt += "\n\nYou have access to the following tools. To call a tool, output a <tool_call> block containing ONLY valid JSON. Do not output any text inside the block other than the JSON object.\n\nFORMAT:\n<tool_call>\n{\"name\": \"TOOL_NAME\", \"args\": {ARGUMENTS}}\n</tool_call>\n\nAVAILABLE TOOLS:\n- take_screenshot: Captures the user's screen for visual analysis. Args: none.\n  Example: <tool_call>\n{\"name\": \"take_screenshot\", \"args\": {}}\n</tool_call>\n\n- web_search: Searches the web. Args: query (string, required), page (number, optional).\n  Example: <tool_call>\n{\"name\": \"web_search\", \"args\": {\"query\": \"latest news\"}}\n</tool_call>\n\n- read_webpage: Fetches and reads the text of a URL. Args: url (string, required).\n  Example: <tool_call>\n{\"name\": \"read_webpage\", \"args\": {\"url\": \"https://example.com\"}}\n</tool_call>\n\n- open_app: Launches an installed desktop application. Args: app_name (string, required).\n  Example: <tool_call>\n{\"name\": \"open_app\", \"args\": {\"app_name\": \"dolphin\"}}\n</tool_call>\n\n- set_timer: Sets a countdown timer that fires a desktop notification. Args: seconds (number, required), message (string, required).\n  Example: <tool_call>\n{\"name\": \"set_timer\", \"args\": {\"seconds\": 300, \"message\": \"Break time!\"}}\n</tool_call>\n\n- get_weather: Gets the current local weather from the system dashboard. Args: none.\n  Example: <tool_call>\n{\"name\": \"get_weather\", \"args\": {}}\n</tool_call>\n\n- caelestia_command: Runs a caelestia CLI command. Valid subcommands: shell, toggle, scheme, search, screenshot, record, clipboard, emoji, wallpaper, resizer, install, update. Args: subcommand (string, required), args (string, optional extra flags).\n  Example: <tool_call>\n{\"name\": \"caelestia_command\", \"args\": {\"subcommand\": \"wallpaper\", \"args\": \"--random\"}}\n</tool_call>\n\nCRITICAL RULES:\n1. ALWAYS use a <tool_call> block to call a tool. NEVER pretend to perform actions in plain text.\n2. You may output a brief acknowledgment before the <tool_call> block (e.g. 'Opening Dolphin for you!') but you MUST include the block.\n3. You can include multiple <tool_call> blocks in one response.\n4. After receiving tool results, respond naturally to the user based on what the tool returned.";
        }
        
        var requestBody;
        if (useAnthropic) {
            var claudeMessages = [];
            for (var i = 0; i < chatHistory.count; i++) {
                var msg = chatHistory.get(i);
                if (!msg.isUser && !msg.isFinished && (msg.text || "") === "")
                    continue;
                if ((msg.text || "") === "")
                    continue;
                claudeMessages.push({
                    "role": msg.isUser ? "user" : "assistant",
                    "content": msg.text
                });
            }

            if (isSystemToolResult) {
                var claudeContent;
                if (base64Image) {
                    claudeContent = [
                        { "type": "text", "text": promptText },
                        { "type": "image", "source": { "type": "base64", "media_type": "image/jpeg", "data": base64Image } }
                    ];
                } else {
                    claudeContent = promptText;
                }
                claudeMessages.push({ "role": "user", "content": claudeContent });
            }

            requestBody = {
                "model": model,
                "max_tokens": 4096,
                "system": sysPrompt,
                "messages": claudeMessages,
                "stream": true
            };
        } else {
            var messages = [];
            messages.push({
                "role": "system",
                "content": sysPrompt
            });

            for (var j = 0; j < chatHistory.count; j++) {
                var m = chatHistory.get(j);
                messages.push({
                    "role": m.isUser ? "user" : "assistant",
                    "content": m.text || ""
                });
            }

            if (isSystemToolResult) {
                var toolMsg = {
                    "role": "user",
                    "content": promptText
                };
                if (base64Image) {
                    if (root.isOpenaiCompat) {
                        toolMsg["content"] = [
                            { "type": "text", "text": promptText },
                            { "type": "image_url", "image_url": { "url": "data:image/jpeg;base64," + base64Image } }
                        ];
                    } else {
                        toolMsg["images"] = [base64Image];
                    }
                }
                messages.push(toolMsg);
            }

            requestBody = {
                "model": model,
                "messages": messages,
                "stream": true
            };
        }

        xhr.send(JSON.stringify(requestBody));
    }

    Item {
        id: mainWrapper

        anchors.fill: parent
        anchors.margins: Tokens.padding.medium

         RowLayout {
             id: modeSwitcherRow

             anchors.top: parent.top
             anchors.left: parent.left
             anchors.right: parent.right
             anchors.rightMargin: 0
             z: 10
             spacing: Tokens.spacing.small

             StyledRect {
                 id: modeSwitcherBg

                 implicitWidth: modeRow.width
                 implicitHeight: 32
                 radius: Tokens.rounding.full
                 color: Colours.tPalette.m3surfaceContainer

                 StyledClippingRect {
                     z: -1
                     anchors.fill: parent
                     radius: Tokens.rounding.full

                     ShaderEffectSource {
                         id: switcherBlurSource

                         sourceItem: contentStack
                         sourceRect: {
                             var p = parent.mapToItem(contentStack, 0, 0);
                             return Qt.rect(p.x, p.y, parent.width, parent.height);
                         }
                     }
                     MultiEffect {
                         anchors.fill: parent
                         source: switcherBlurSource
                         blurEnabled: true
                         blurMax: 32
                     }
                 }

                 StyledRect {
                     width: isHistoryTab ? historyTab.width : chatTab.width
                     height: parent.height
                     radius: Tokens.rounding.full
                     color: Colours.palette.m3primary
                     x: isHistoryTab ? historyTab.x : chatTab.x
                     
                     Behavior on x { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                     Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                 }

                 Row {
                     id: modeRow

                     height: parent.height

                     Item {
                         id: chatTab

                         height: parent.height
                         width: !isHistoryTab ? 40 : chatContent.implicitWidth + Tokens.padding.medium * 2
                         

                         Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

                         StateLayer {
                             radius: Tokens.rounding.full
                             onClicked: isHistoryTab = false
                         }

                         Row {
                             id: chatContent

                             anchors.centerIn: parent
                             spacing: Tokens.spacing.small

                             MaterialIcon {
                                 anchors.verticalCenter: parent.verticalCenter
                                 text: "chat"
                                 color: !isHistoryTab ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                                 font: Tokens.font.icon.small
                             }
                             Text {
                                 anchors.verticalCenter: parent.verticalCenter
                                 text: "Chat"
                                 color: !isHistoryTab ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                                 font: Tokens.font.body.small
                                 visible: isHistoryTab
                             }
                         }
                     }

                     Item {
                         id: historyTab

                         height: parent.height
                         width: isHistoryTab ? 40 : historyContent.implicitWidth + Tokens.padding.medium * 2
                         

                         Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

                         StateLayer {
                             radius: Tokens.rounding.full
                             onClicked: isHistoryTab = true
                         }

                         Row {
                             id: historyContent

                             anchors.centerIn: parent
                             spacing: Tokens.spacing.small

                             MaterialIcon {
                                 anchors.verticalCenter: parent.verticalCenter
                                 text: "history"
                                 color: isHistoryTab ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                                 font: Tokens.font.icon.small
                             }
                             Text {
                                 anchors.verticalCenter: parent.verticalCenter
                                 text: "History"
                                 color: isHistoryTab ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                                 font: Tokens.font.body.small
                                 visible: !isHistoryTab
                             }
                         }
                     }
                 }
             }

         }

         Flow {
             id: selectorRow

             anchors.top: modeSwitcherRow.bottom
             anchors.left: parent.left
             anchors.right: parent.right
             anchors.topMargin: Tokens.spacing.small
             z: 10
             spacing: Tokens.spacing.small

             SplitButton {
                 id: providerSelector

                 type: SplitButton.Tonal
                 verticalPadding: 4
                 visible: root.providerList.length > 1
                 Layout.preferredWidth: implicitWidth

                 active: menuItems.find(m => m.modelData === root.provider) ?? menuItems[0] ?? null
                 menu.onItemSelected: item => {
                     GlobalConfig.ai.defaultProvider = item.modelData;
                 }

                 menuItems: providerVariants.instances

                 fallbackIcon: "cloud"
                 fallbackText: qsTr("Provider")
                 stateLayer.disabled: true

                 Variants {
                     id: providerVariants

                     model: root.providerList

                     delegate: MenuItem {
                         required property string modelData

                         text: root.providerLabel(modelData)
                     }
                 }
             }

             SplitButton {
                 id: modelSelector

                 type: SplitButton.Tonal
                 verticalPadding: 4
                 Layout.preferredWidth: implicitWidth

                 active: menuItems.find(m => m.modelData === root.activeModel()) ?? menuItems[0] ?? null
                 menu.onItemSelected: item => {
                     if (root.isClaudeCode) {
                         GlobalConfig.ai.defaultClaudeCodeModel = item.modelData;
                         GlobalConfig.ai.claudeCodeEffort = "default";
                     } else if (root.isClaude)
                         GlobalConfig.ai.defaultClaudeModel = item.modelData;
                     else if (root.isOpenaiCompat)
                         GlobalConfig.ai[root.defaultModelField(root.provider)] = item.modelData;
                     else
                         GlobalConfig.ai.defaultOllamaModel = item.modelData;
                 }

                 menuItems: modelVariants.instances

                 fallbackIcon: "smart_toy"
                 fallbackText: qsTr("Select Model")
                 stateLayer.disabled: true

                 Variants {
                     id: modelVariants

                     model: {
                         if (root.isClaudeCode)
                             return root.claudeCodeModelsList;
                         if (root.isClaude)
                             return root.claudeModelsList;
                         if (root.isOpenaiCompat)
                             return root.openaiCompatModelList();
                         return root.ollamaModelsList;
                     }

                     delegate: MenuItem {
                         required property string modelData

                         text: modelData
                     }
                 }
             }

             SplitButton {
                 id: effortSelector

                 type: SplitButton.Tonal
                 verticalPadding: 4
                 visible: root.isClaudeCode && root.claudeCodeEffortOptions.length > 0

                 active: menuItems.find(m => m.modelData === (GlobalConfig.ai.claudeCodeEffort || "default")) ?? menuItems[0] ?? null
                 menu.onItemSelected: item => {
                     GlobalConfig.ai.claudeCodeEffort = item.modelData;
                 }

                 menuItems: effortVariants.instances

                 fallbackIcon: "neurology"
                 fallbackText: qsTr("Effort")
                 stateLayer.disabled: true

                 Variants {
                     id: effortVariants

                     model: root.claudeCodeEffortOptions

                     delegate: MenuItem {
                         required property string modelData

                         text: modelData
                     }
                 }
             }

             SplitButton {
                 id: accountSelector

                 type: SplitButton.Tonal
                 verticalPadding: 4
                 visible: root.isClaudeCode && root.claudeAccountIds.length > 1

                 active: menuItems.find(m => m.modelData === (GlobalConfig.ai.activeClaudeAccount || "")) ?? menuItems[0] ?? null
                 menu.onItemSelected: item => {
                     GlobalConfig.ai.activeClaudeAccount = item.modelData;
                 }

                 menuItems: accountVariants.instances

                 fallbackIcon: "person"
                 fallbackText: qsTr("Account")
                 stateLayer.disabled: true

                 Variants {
                     id: accountVariants

                     model: root.claudeAccountIds

                     delegate: MenuItem {
                         required property string modelData

                         text: root.accountLabel(modelData)
                     }
                 }
             }

             // Permission mode for this chat (Claude Code).
             SplitButton {
                 id: permissionSelector

                 type: SplitButton.Tonal
                 verticalPadding: 4
                 visible: root.isClaudeCode

                 active: menuItems.find(m => m.modelData === root.effectiveClaudeCodePermissionMode(root.claudeCodePermissionMode)) ?? menuItems[0] ?? null
                 menu.onItemSelected: item => root.setClaudeCodePermissionMode(item.modelData)

                 menuItems: permissionVariants.instances

                 fallbackIcon: "shield"
                 fallbackText: qsTr("Permissions")
                 stateLayer.disabled: true

                 Variants {
                     id: permissionVariants

                     model: root.claudeCodePermissionModes

                     delegate: MenuItem {
                         required property string modelData

                         text: root.permissionModeLabel(modelData)
                     }
                 }
             }

             // Working directory for this chat (Claude Code).
             StyledRect {
                 id: cwdButton

                 visible: root.isClaudeCode
                 implicitWidth: Math.min(cwdRow.implicitWidth + Tokens.padding.medium * 2, 220)
                 implicitHeight: permissionSelector.height
                 radius: Tokens.rounding.full
                 color: Colours.tPalette.m3secondaryContainer

                 StateLayer {
                     radius: Tokens.rounding.full
                     color: Colours.palette.m3onSecondaryContainer
                     onClicked: cwdDialog.open()
                 }

                 RowLayout {
                     id: cwdRow

                     anchors.fill: parent
                     anchors.leftMargin: Tokens.padding.medium
                     anchors.rightMargin: Tokens.padding.medium
                     spacing: Tokens.spacing.small

                     MaterialIcon {
                         text: "folder"
                         color: Colours.palette.m3onSecondaryContainer
                         font: Tokens.font.icon.small
                     }

                     StyledText {
                         Layout.fillWidth: true
                         text: root.shortPath(root.claudeCodeChatCwd)
                         color: Colours.palette.m3onSecondaryContainer
                         font: Tokens.font.label.medium
                         elide: Text.ElideMiddle
                     }
                 }

                 FileDialog {
                     id: cwdDialog

                     selectFolder: true
                     title: qsTr("Claude Code working directory")
                     onAccepted: path => root.setClaudeCodeCwd(path)
                 }
             }

             // Continue this chat's session in a terminal (claude --resume).
             StyledRect {
                 visible: root.isClaudeCode
                 implicitWidth: permissionSelector.height
                 implicitHeight: permissionSelector.height
                 radius: Tokens.rounding.full
                 color: Colours.tPalette.m3secondaryContainer

                 StateLayer {
                     radius: Tokens.rounding.full
                     color: Colours.palette.m3onSecondaryContainer
                     onClicked: root.openClaudeCodeInTerminal()
                 }

                 MaterialIcon {
                     anchors.centerIn: parent
                     text: "terminal"
                     color: Colours.palette.m3onSecondaryContainer
                     font: Tokens.font.icon.small
                 }
             }


         }
         
         Item {
             id: contentStack

             anchors.top: selectorRow.bottom
             anchors.bottom: parent.bottom
             anchors.left: parent.left
             anchors.right: parent.right
             anchors.topMargin: Tokens.spacing.medium

             Item {
                 anchors.fill: parent
                 opacity: !isHistoryTab ? 1 : 0
                 visible: opacity > 0

                 Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.InOutQuad } }

                 VerticalFadeListView {
                     id: listView

                     anchors.top: parent.top
                     anchors.bottom: attachmentStrip.visible ? attachmentStrip.top : inputBoxRow.top
                     anchors.left: parent.left
                     anchors.right: parent.right
                     anchors.bottomMargin: Tokens.spacing.medium
                     spacing: Tokens.spacing.medium
                     model: chatHistory
                     boundsBehavior: Flickable.StopAtBounds
                     // Keep off-screen messages alive. Recreating them while dragging the
                     // scrollbar re-measures them, so the content height (and with it the
                     // scroll position) kept jumping.
                     cacheBuffer: 100000
                     
                     ColumnLayout {
                         anchors.centerIn: parent
                         opacity: chatHistory.count === 0 && !isTyping && !isThinking ? 1.0 : 0.0
                         visible: opacity > 0

                         Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.InOutQuad } }

                         spacing: Tokens.spacing.large

                         Item {
                             Layout.alignment: Qt.AlignHCenter
                             implicitWidth: 72
                             implicitHeight: 72

                             Logo {
                                 id: emptyStateLogo

                                 anchors.fill: parent
                                 visible: false
                             }

                             MultiEffect {
                                 anchors.fill: parent
                                 source: emptyStateLogo
                                 colorization: 1.0
                                 colorizationColor: Colours.palette.m3primary
                             }
                         }

                         StyledText {
                             id: greetingText
                             Layout.alignment: Qt.AlignHCenter
                             Layout.maximumWidth: listView.width - (Tokens.padding.large * 2)

                             horizontalAlignment: Text.AlignHCenter
                             wrapMode: Text.Wrap
                             font: Tokens.font.title.medium
                             color: Colours.palette.m3onSurfaceVariant

                             property var phrases: [
                                 "Ask away, %1!",
                                 "How can I help you today, %1?",
                                 "What's on your mind, %1?",
                                 "Ready when you are, %1!",
                                 "Let's get started, %1.",
                                 "What shall we explore today, %1?",
                                 "I'm all ears, %1!"
                             ]

                             Component.onCompleted: {
                                 var user = Quickshell.env("USER") || "user";
                                 var userCapitalized = user.charAt(0).toUpperCase() + user.slice(1);
                                 var phrase = phrases[Math.floor(Math.random() * phrases.length)];
                                 text = phrase.replace("%1", userCapitalized);
                             }
                         }
                     }

                     ScrollBar.vertical: StyledScrollBar {
                         flickable: listView
                     }

                     footer: Item {
                         // Claude Code keeps its status line up for the whole reply,
                         // below the text as it streams.
                         id: statusFooter

                         readonly property bool shown: isThinking || (root.isClaudeCode && root.isTyping)
                         readonly property real maxBubbleWidth: listView.width * 0.85
                         readonly property real naturalWidth: footerCol.implicitWidth + Tokens.padding.medium * 2 + 8
                         // Widest the bubble has been during this reply. The verb, the
                         // counters and the thoughts all change width as they update;
                         // only growing keeps the bubble from wobbling.
                         property real stableWidth: 0

                         onNaturalWidthChanged: if (shown) stableWidth = Math.max(stableWidth, naturalWidth)
                         onShownChanged: stableWidth = shown ? naturalWidth : 0

                         width: listView.width
                         height: shown ? bubbleBg.height + Tokens.spacing.medium : 0
                         visible: opacity > 0
                         opacity: shown ? 1 : 0
                         
                         Behavior on height { Anim { type: Anim.DefaultSpatial } }
                         Behavior on opacity { Anim { type: Anim.DefaultSpatial } }

                         StyledRect {
                             id: bubbleBg

                             y: Tokens.spacing.medium / 2
                             width: Math.min(statusFooter.maxBubbleWidth, Math.max(statusFooter.stableWidth, statusFooter.naturalWidth))
                             height: footerCol.implicitHeight + Tokens.padding.medium * 2
                             radius: Tokens.rounding.large
                             color: Colours.tPalette.m3surfaceContainer

                             topLeftRadius: Tokens.rounding.large
                             topRightRadius: Tokens.rounding.large
                             bottomLeftRadius: 4
                             bottomRightRadius: Tokens.rounding.large

                             Column {
                                 id: footerCol

                                 anchors.fill: parent
                                 anchors.margins: Tokens.padding.medium
                                 spacing: Tokens.spacing.small
                                 
                                 Row {
                                     spacing: Tokens.spacing.small
                                     
                                     LoadingIndicator {
                                         visible: !root.isClaudeCode
                                         width: 20
                                         height: 20
                                         color: Colours.palette.m3primary
                                     }

                                     // Claude Code: the CLI's twinkling star.
                                     StyledText {
                                         id: starGlyph

                                         readonly property var frames: ["·", "✢", "✳", "✶", "✻", "✽", "✻", "✶", "✳", "✢"]
                                         property int frame: 0

                                         visible: root.isClaudeCode
                                         // The frames come from different fallback fonts with
                                         // different line heights; a fixed box keeps the row
                                         // (and the bubble) from bouncing with every frame.
                                         width: 20
                                         height: 20
                                         horizontalAlignment: Text.AlignHCenter
                                         verticalAlignment: Text.AlignVCenter
                                         anchors.verticalCenter: parent.verticalCenter
                                         text: frames[frame]
                                         color: root.claudeCodeToolRunning ? Colours.palette.m3tertiary : Colours.palette.m3primary
                                         font.pointSize: Tokens.font.body.small.pointSize * 1.2
                                         font.family: Tokens.font.body.small.family

                                         Behavior on color { CAnim {} }

                                         Timer {
                                             interval: 120
                                             repeat: true
                                             running: starGlyph.visible && root.isTyping
                                             onTriggered: starGlyph.frame = (starGlyph.frame + 1) % starGlyph.frames.length
                                         }
                                     }
                                     
                                     Item {
                                         width: mainText.implicitWidth
                                         height: mainText.implicitHeight

                                         Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                                         
                                         StyledText {
                                             id: mainText

                                             text: displayedText
                                             color: Colours.palette.m3onSurfaceVariant
                                             font: Tokens.font.body.small
                                             
                                             property string displayedText: root.currentActionText

                                             property string nextText: ""

                                             transform: Translate { id: textTrans; y: 0 }
                                             opacity: 1.0

                                             Connections {
                                                 target: root

                                                 function onCurrentActionTextChanged() {
                                                     if (root.currentActionText !== mainText.displayedText) {
                                                         mainText.nextText = root.currentActionText;
                                                         switchAnim.restart();
                                                     }
                                                 }
                                             }

                                             SequentialAnimation {
                                                 id: switchAnim

                                                 ParallelAnimation {
                                                     NumberAnimation { target: textTrans; property: "y"; to: -8; duration: 150; easing.type: Easing.InCubic }
                                                     NumberAnimation { target: mainText; property: "opacity"; to: 0.0; duration: 150; easing.type: Easing.InCubic }
                                                 }
                                                 PropertyAction { target: mainText; property: "displayedText"; value: mainText.nextText }
                                                 PropertyAction { target: textTrans; property: "y"; value: 8 }
                                                 ParallelAnimation {
                                                     NumberAnimation { target: textTrans; property: "y"; to: 0; duration: 400; easing.type: Easing.OutBack; easing.overshoot: 1.5 }
                                                     NumberAnimation { target: mainText; property: "opacity"; to: 1.0; duration: 250; easing.type: Easing.OutQuad }
                                                 }
                                             }

                                             SequentialAnimation {
                                                 running: isThinking && !switchAnim.running
                                                 loops: Animation.Infinite

                                                 NumberAnimation { target: mainText; property: "opacity"; from: 1.0; to: 0.4; duration: 800; easing.type: Easing.InOutSine }
                                                 NumberAnimation { target: mainText; property: "opacity"; from: 0.4; to: 1.0; duration: 800; easing.type: Easing.InOutSine }
                                             }
                                         }
                                     }
                                     
                                     Item {
                                         visible: root.currentThoughtText !== ""
                                         width: Tokens.spacing.medium
                                         height: 1
                                     }
                                     
                                     Item {
                                         visible: root.currentThoughtText !== ""
                                         width: thoughtRowFooter.implicitWidth
                                         height: thoughtRowFooter.implicitHeight

                                         Row {
                                             id: thoughtRowFooter

                                             spacing: Tokens.spacing.small

                                             MaterialIcon {
                                                 text: "expand_more"
                                                 color: Colours.palette.m3onSurfaceVariant
                                                 font: Tokens.font.icon.small
                                                 rotation: root.isThoughtExpanded ? 180 : 0

                                                 Behavior on rotation { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                                             }
                                         }
                                         MouseArea {
                                             anchors.fill: parent
                                             anchors.margins: -10
                                             cursorShape: Qt.PointingHandCursor
                                             onClicked: root.isThoughtExpanded = !root.isThoughtExpanded
                                         }
                                     }
                                 }
                                 // Claude Code: elapsed time and output tokens on their own line.
                                 StyledText {
                                     visible: root.isClaudeCode && root.isTyping
                                     width: Math.min(implicitWidth, statusFooter.maxBubbleWidth - Tokens.padding.medium * 2 - 8)
                                     leftPadding: 20 + Tokens.spacing.small
                                     text: root.formatElapsed(root.claudeCodeElapsed)
                                         + (root.claudeCodeOutTokens > 0 ? " · ↓ " + root.formatTokens(root.claudeCodeOutTokens) + " tokens" : "")
                                     color: Colours.palette.m3outline
                                     font.family: Tokens.font.mono.small.family
                                     font.pointSize: Tokens.font.label.small.pointSize
                                     elide: Text.ElideRight
                                 }

                                 Item {
                                     id: footerThoughtContentWrapper

                                     width: root.isThoughtExpanded ? footerThoughtContent.width : 0
                                     height: root.isThoughtExpanded ? footerThoughtContent.implicitHeight : 0
                                     clip: true
                                     
                                     Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }

                                     TextEdit {
                                         id: footerThoughtContent

                                         width: Math.min(implicitWidth, listView.width * 0.85 - Tokens.padding.medium * 2)
                                         textFormat: Text.MarkdownText
                                         text: root.currentThoughtText
                                         color: Colours.palette.m3onSurfaceVariant
                                         font: Tokens.font.body.small
                                         wrapMode: Text.Wrap
                                         readOnly: true
                                         selectByMouse: true
                                         selectionColor: Colours.palette.m3primary
                                         selectedTextColor: Colours.palette.m3onPrimary
                                         opacity: root.isThoughtExpanded ? 1.0 : 0.0
                                         
                                         Behavior on opacity {
                                             SequentialAnimation {
                                                 PauseAnimation { duration: root.isThoughtExpanded ? 100 : 0 }
                                                 NumberAnimation { duration: 150; easing.type: Easing.InOutQuad }
                                             }
                                         }
                                     }
                                 }
                             }
                         }
                     }

                     delegate: Item {
                         id: delegateItem

                         required property string text
                         required property bool isUser
                         required property bool isFinished
                         required property string thoughtText
                         required property string toolsJson
                         required property string usageText
                         required property string attachments

                         readonly property var tools: {
                             if (!toolsJson)
                                 return [];
                             try {
                                 return JSON.parse(toolsJson);
                             } catch (e) {
                                 return [];
                             }
                         }
                         readonly property var attachmentList: attachments ? attachments.split("\n") : []

                         width: listView.width - Tokens.padding.large
                         // While a reply is still thinking only its tool calls are worth showing.
                         visible: (!delegateItem.isFinished && isThinking && delegateItem.tools.length === 0) ? false : (delegateItem.text !== "" || delegateItem.thoughtText !== "" || delegateItem.tools.length > 0 || delegateItem.attachmentList.length > 0)
                         height: visible ? bubbleRect.height : 0
                         
                         scale: 0.0
                         opacity: 0.0
                         
                         required property int index

                         // Only a message that was just added pops in; one being created
                         // again as it scrolls into view appears as is.
                         Component.onCompleted: {
                             if (index === chatHistory.count - 1 && !root.loadingChat)
                                 popInAnim.start();
                             else {
                                 scale = 1;
                                 opacity = 1;
                             }
                         }
                         
                         ParallelAnimation {
                             id: popInAnim

                             NumberAnimation { target: delegateItem; property: "scale"; from: 0.8; to: 1.0; duration: 300; easing.type: Easing.OutBack }
                             NumberAnimation { target: delegateItem; property: "opacity"; from: 0.0; to: 1.0; duration: 200; easing.type: Easing.OutQuad }
                         }
                         
                         SequentialAnimation {
                             id: popDoneAnim

                             NumberAnimation { target: delegateItem; property: "scale"; from: 1.0; to: 1.02; duration: 100; easing.type: Easing.OutQuad }
                             NumberAnimation { target: delegateItem; property: "scale"; from: 1.02; to: 1.0; duration: 150; easing.type: Easing.OutSine }
                         }
                         
                         onIsFinishedChanged: {
                             if (isFinished) popDoneAnim.start();
                         }

                         StyledRect {
                             id: bubbleRect

                             readonly property real maxBubbleWidth: delegateItem.width * 0.85

                             anchors.right: delegateItem.isUser ? parent.right : undefined
                             anchors.left: delegateItem.isUser ? undefined : parent.left
                             
                             width: Math.min(maxBubbleWidth, bubbleLayout.implicitWidth + Tokens.padding.medium * 2 + 8)
                             height: bubbleLayout.implicitHeight + Tokens.padding.medium * 2
                             radius: Tokens.rounding.large
                             color: delegateItem.isUser ? Colours.palette.m3primary : Colours.tPalette.m3surfaceContainer

                             topLeftRadius: Tokens.rounding.large
                             topRightRadius: Tokens.rounding.large
                             bottomLeftRadius: delegateItem.isUser ? Tokens.rounding.large : 4
                             bottomRightRadius: delegateItem.isUser ? 4 : Tokens.rounding.large
                             
                             Column {
                                 id: bubbleLayout

                                 anchors.top: parent.top
                                 anchors.left: parent.left
                                 anchors.margins: Tokens.padding.medium
                                 spacing: Tokens.spacing.small

                                 property string delegateThought: delegateItem.thoughtText

                                 property bool isExpanded: false

                                 Item {
                                     visible: bubbleLayout.delegateThought !== ""
                                     implicitWidth: thoughtRow.implicitWidth
                                     implicitHeight: thoughtRow.implicitHeight
                                     height: visible ? implicitHeight : 0

                                     Row {
                                         id: thoughtRow

                                         spacing: Tokens.spacing.small

                                         Text {
                                             text: qsTr("Thought Process")
                                             color: Colours.palette.m3onSurfaceVariant
                                             font: Tokens.font.body.small
                                         }
                                         MaterialIcon {
                                             id: thoughtArrow

                                             text: "expand_more"
                                             color: Colours.palette.m3onSurfaceVariant
                                             font: Tokens.font.icon.small
                                             rotation: bubbleLayout.isExpanded ? 180 : 0

                                             Behavior on rotation { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                                         }
                                     }
                                     MouseArea {
                                         anchors.fill: parent
                                         cursorShape: Qt.PointingHandCursor
                                         onClicked: bubbleLayout.isExpanded = !bubbleLayout.isExpanded
                                     }
                                 }

                                 Item {
                                     id: thoughtContentWrapper

                                     width: thoughtContent.width
                                     height: bubbleLayout.isExpanded ? thoughtContent.implicitHeight : 0
                                     clip: true
                                     
                                     Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }

                                     TextEdit {
                                         id: thoughtContent

                                         width: Math.min(implicitWidth, bubbleRect.maxBubbleWidth - Tokens.padding.medium * 2)
                                         textFormat: Text.MarkdownText
                                         
                                         property string fullThought: bubbleLayout.delegateThought
                                         
                                         property bool cursorVisible: true

                                         Timer {
                                             running: !delegateItem.isFinished
                                             repeat: true
                                             interval: 400
                                             onTriggered: thoughtContent.cursorVisible = !thoughtContent.cursorVisible
                                         }
                                         
                                         text: delegateItem.isFinished ? fullThought : fullThought + (cursorVisible ? "▌" : "")
                                         
                                         color: Colours.palette.m3onSurfaceVariant

                                         font: Tokens.font.body.small

                                         wrapMode: Text.Wrap

                                         readOnly: true

                                         selectByMouse: true

                                         selectionColor: Colours.palette.m3primary

                                         selectedTextColor: Colours.palette.m3onPrimary

                                         opacity: bubbleLayout.isExpanded ? 1.0 : 0.0
                                         
                                         Behavior on opacity {
                                             SequentialAnimation {
                                                 PauseAnimation { duration: bubbleLayout.isExpanded ? 100 : 0 }
                                                 NumberAnimation { duration: 150; easing.type: Easing.InOutQuad }
                                             }
                                         }
                                     }
                                 }

                                 // Tool calls made while producing this reply (Claude Code).
                                 Repeater {
                                     model: delegateItem.tools

                                     StyledRect {
                                         id: toolCard

                                         required property var modelData
                                         property bool expanded: false
                                         readonly property bool isAgent: root.isAgentTool(modelData.name)
                                         readonly property var steps: modelData.steps || []
                                         // Collapsed running subagent: show just its latest steps.
                                         readonly property var visibleSteps: expanded ? steps : (!modelData.done ? steps.slice(-3) : [])

                                         width: bubbleRect.maxBubbleWidth - Tokens.padding.medium * 2
                                         implicitHeight: toolCardCol.implicitHeight + Tokens.padding.small * 2
                                         radius: Tokens.rounding.small
                                         color: Colours.layer(Colours.tPalette.m3surfaceContainerHigh, 2)

                                         // Subagent cards get an accent bar down the left edge.
                                         StyledRect {
                                             visible: toolCard.isAgent
                                             anchors.left: parent.left
                                             anchors.top: parent.top
                                             anchors.bottom: parent.bottom
                                             anchors.margins: 4
                                             width: 3
                                             radius: Tokens.rounding.full
                                             color: toolCard.modelData.isError ? Colours.palette.m3error : (toolCard.modelData.done ? Colours.palette.m3outlineVariant : Colours.palette.m3tertiary)

                                             Behavior on color { CAnim {} }
                                         }

                                         Column {
                                             id: toolCardCol

                                             anchors.left: parent.left
                                             anchors.right: parent.right
                                             anchors.top: parent.top
                                             anchors.margins: Tokens.padding.small
                                             anchors.leftMargin: toolCard.isAgent ? Tokens.padding.small + 8 : Tokens.padding.small
                                             spacing: Tokens.spacing.small

                                             Item {
                                                 width: parent.width
                                                 implicitHeight: toolHeader.implicitHeight

                                                 RowLayout {
                                                     id: toolHeader

                                                     anchors.left: parent.left
                                                     anchors.right: parent.right
                                                     spacing: Tokens.spacing.small

                                                     MaterialIcon {
                                                         text: toolCard.modelData.isError ? "error" : (toolCard.isAgent ? (toolCard.modelData.done ? "task_alt" : "smart_toy") : (toolCard.modelData.done ? "check_circle" : "pending"))
                                                         color: toolCard.modelData.isError ? Colours.palette.m3error : (toolCard.modelData.done ? Colours.palette.m3primary : (toolCard.isAgent ? Colours.palette.m3tertiary : Colours.palette.m3onSurfaceVariant))
                                                         font: Tokens.font.icon.small

                                                         // A running subagent breathes so it reads as busy.
                                                         SequentialAnimation on opacity {
                                                             running: toolCard.isAgent && !toolCard.modelData.done
                                                             loops: Animation.Infinite
                                                             onRunningChanged: if (!running) parent.opacity = 1

                                                             NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutSine }
                                                             NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
                                                         }
                                                     }

                                                     StyledText {
                                                         text: toolCard.isAgent ? (toolCard.modelData.agentType || "subagent") : toolCard.modelData.name
                                                         color: Colours.palette.m3onSurface
                                                         font: Tokens.font.label.medium
                                                     }

                                                     StyledText {
                                                         Layout.fillWidth: true
                                                         text: toolCard.modelData.summary || ""
                                                         color: Colours.palette.m3onSurfaceVariant
                                                         font: toolCard.isAgent ? Tokens.font.label.medium : Tokens.font.mono.small
                                                         elide: Text.ElideRight
                                                         maximumLineCount: 1
                                                     }

                                                     MaterialIcon {
                                                         visible: toolCard.isAgent || (toolCard.modelData.result || "") !== "" || (toolCard.modelData.summary || "").length > 40
                                                         text: "expand_more"
                                                         color: Colours.palette.m3onSurfaceVariant
                                                         font: Tokens.font.icon.small
                                                         rotation: toolCard.expanded ? 180 : 0

                                                         Behavior on rotation { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                                                     }
                                                 }

                                                 MouseArea {
                                                     anchors.fill: parent
                                                     cursorShape: Qt.PointingHandCursor
                                                     onClicked: toolCard.expanded = !toolCard.expanded
                                                 }
                                             }

                                             // Subagent: current step and running totals.
                                             StyledText {
                                                 visible: toolCard.isAgent && text !== ""
                                                 width: parent.width
                                                 text: {
                                                     const stats = root.agentStatsText(toolCard.modelData);
                                                     const step = !toolCard.modelData.done ? (toolCard.modelData.progress || "") : "";
                                                     return step !== "" && stats !== "" ? step + " · " + stats : (step || stats);
                                                 }
                                                 color: Colours.palette.m3outline
                                                 font: Tokens.font.label.small
                                                 elide: Text.ElideRight
                                             }

                                             // Subagent: its own tool calls.
                                             Repeater {
                                                 model: toolCard.visibleSteps

                                                 RowLayout {
                                                     required property var modelData

                                                     width: toolCardCol.width
                                                     spacing: Tokens.spacing.small

                                                     MaterialIcon {
                                                         text: parent.modelData.isError ? "close" : (parent.modelData.done ? "check" : "more_horiz")
                                                         color: parent.modelData.isError ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                                                         font: Tokens.font.icon.small
                                                     }

                                                     StyledText {
                                                         text: parent.modelData.name
                                                         color: Colours.palette.m3onSurfaceVariant
                                                         font: Tokens.font.label.small
                                                     }

                                                     StyledText {
                                                         Layout.fillWidth: true
                                                         text: parent.modelData.summary || ""
                                                         color: Colours.palette.m3outline
                                                         font: Tokens.font.mono.small
                                                         elide: Text.ElideRight
                                                         maximumLineCount: 1
                                                     }
                                                 }
                                             }

                                             StyledText {
                                                 visible: !toolCard.expanded && !toolCard.modelData.done && toolCard.steps.length > 3
                                                 text: qsTr("+%1 earlier steps").arg(toolCard.steps.length - 3)
                                                 color: Colours.palette.m3outline
                                                 font: Tokens.font.label.small
                                             }

                                             // Subagent report, rendered as Markdown.
                                             TextEdit {
                                                 visible: toolCard.isAgent && toolCard.expanded && (toolCard.modelData.result || "") !== ""
                                                 width: parent.width
                                                 text: toolCard.modelData.result || ""
                                                 textFormat: Text.MarkdownText
                                                 color: toolCard.modelData.isError ? Colours.palette.m3error : Colours.palette.m3onSurface
                                                 font: Tokens.font.body.small
                                                 wrapMode: Text.Wrap
                                                 readOnly: true
                                                 selectByMouse: true
                                                 selectionColor: Colours.palette.m3primary
                                                 selectedTextColor: Colours.palette.m3onPrimary
                                             }

                                             TextEdit {
                                                 visible: toolCard.expanded && !toolCard.isAgent
                                                 width: parent.width
                                                 text: (toolCard.modelData.summary || "") + ((toolCard.modelData.result || "") !== "" ? "\n\n" + toolCard.modelData.result : "")
                                                 textFormat: Text.PlainText
                                                 color: toolCard.modelData.isError ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                                                 font: Tokens.font.mono.small
                                                 wrapMode: Text.WrapAnywhere
                                                 readOnly: true
                                                 selectByMouse: true
                                                 selectionColor: Colours.palette.m3primary
                                                 selectedTextColor: Colours.palette.m3onPrimary
                                             }
                                         }
                                     }
                                 }

                                 TextEdit {
                                     id: messageText

                                     // Nothing to show yet (e.g. only tool calls so far): no
                                     // empty line with a lone blinking cursor.
                                     visible: fullText !== ""
                                     textFormat: Text.MarkdownText
                                     width: Math.min(implicitWidth, bubbleRect.maxBubbleWidth - Tokens.padding.medium * 2)
                                     
                                     property string fullText: delegateItem.text !== undefined ? delegateItem.text : ""
                                     
                                     property bool cursorVisible: true

                                     Timer {
                                         running: !delegateItem.isFinished
                                         repeat: true
                                         interval: 400
                                         onTriggered: messageText.cursorVisible = !messageText.cursorVisible
                                     }
                                     
                                     text: delegateItem.isFinished ? fullText : fullText + (cursorVisible ? "▌" : "")
                                     
                                     color: delegateItem.isUser ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface

                                     font: Tokens.font.body.small

                                     wrapMode: Text.Wrap

                                     readOnly: true

                                     selectByMouse: true

                                     selectionColor: Colours.palette.m3primary

                                     selectedTextColor: Colours.palette.m3onPrimary

                                     MouseArea {
                                         anchors.fill: parent
                                         hoverEnabled: true
                                         cursorShape: Qt.IBeamCursor
                                         propagateComposedEvents: true
                                         onPressed: mouse => mouse.accepted = false
                                     }
                                 }

                                 Repeater {
                                     model: delegateItem.attachmentList

                                     Row {
                                         required property string modelData

                                         spacing: Tokens.spacing.small

                                         MaterialIcon {
                                             text: root.isImagePath(parent.modelData) ? "image" : "attach_file"
                                             color: delegateItem.isUser ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                                             font: Tokens.font.icon.small
                                         }

                                         StyledText {
                                             width: Math.min(implicitWidth, bubbleRect.maxBubbleWidth - Tokens.padding.medium * 2 - 24)
                                             text: parent.modelData.replace(/^.*\//, "")
                                             color: delegateItem.isUser ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                                             font: Tokens.font.label.small
                                             elide: Text.ElideMiddle
                                         }
                                     }
                                 }

                                 StyledText {
                                     visible: !delegateItem.isUser && delegateItem.isFinished && delegateItem.usageText !== ""
                                     width: Math.min(implicitWidth, bubbleRect.maxBubbleWidth - Tokens.padding.medium * 2)
                                     text: delegateItem.usageText
                                     color: Colours.palette.m3outline
                                     font: Tokens.font.label.small
                                     wrapMode: Text.Wrap
                                 }
                             }
                         }
                     }
                 }

                 Item {
                     id: scrollBtnWrapper

                     anchors.bottom: inputBoxRow.top
                     anchors.bottomMargin: Tokens.spacing.large
                     anchors.right: parent.right
                     anchors.rightMargin: Tokens.padding.large
                     width: 36
                     height: 36
                     z: 20
                     opacity: (!listView.atYEnd && chatHistory.count > 0) ? 1.0 : 0.0
                     visible: opacity > 0

                     Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }

                     StyledRect {
                         id: scrollBtnBg

                         anchors.fill: parent
                         radius: 18
                         color: Colours.tPalette.m3surfaceContainerHigh
                     }

                     MultiEffect {
                         anchors.fill: scrollBtnBg
                         source: scrollBtnBg
                         shadowEnabled: true
                         shadowOpacity: 0.3
                         shadowBlur: 0.5
                         shadowVerticalOffset: 2
                     }

                     MaterialIcon {
                         anchors.centerIn: parent
                         text: "arrow_downward"
                         font: Tokens.font.icon.small
                         color: Colours.palette.m3onSurface
                     }

                     MouseArea {
                         anchors.fill: parent
                         cursorShape: Qt.PointingHandCursor
                         onClicked: listView.positionViewAtEnd()
                     }
                 }

                 ColumnLayout {
                     id: suggestionBox

                     anchors.bottom: attachmentStrip.visible ? attachmentStrip.top : inputBoxRow.top
                     anchors.bottomMargin: Tokens.spacing.small
                     anchors.left: parent.left
                     anchors.right: parent.right
                     z: 11
                     spacing: Tokens.spacing.small
                     visible: root.isClaudeCode && root.promptSuggestions.length > 0

                     RowLayout {
                         Layout.fillWidth: true
                         spacing: Tokens.spacing.small

                         StyledText {
                             Layout.fillWidth: true
                             text: qsTr("Suggestions")
                             color: Colours.palette.m3onSurfaceVariant
                             font: Tokens.font.label.small
                         }

                         Item {
                             Layout.preferredWidth: 24
                             Layout.preferredHeight: 24

                             MaterialIcon {
                                 anchors.centerIn: parent
                                 text: "close"
                                 color: closeSugMouse.containsMouse ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant
                                 font: Tokens.font.icon.small
                             }

                             MouseArea {
                                 id: closeSugMouse

                                 anchors.fill: parent
                                 hoverEnabled: true
                                 cursorShape: Qt.PointingHandCursor
                                 onClicked: root.promptSuggestions = []
                             }
                         }
                     }

                     Repeater {
                         model: root.promptSuggestions

                         StyledRect {
                             required property string modelData
                             Layout.fillWidth: true

                             implicitHeight: sugChipText.implicitHeight + Tokens.padding.medium * 2
                             radius: Tokens.rounding.large
                             color: Colours.tPalette.m3surfaceContainerHigh

                             StateLayer {
                                 radius: Tokens.rounding.large
                                 onClicked: {
                                     inputArea.text = modelData;
                                     root.promptSuggestions = [];
                                     inputArea.forceActiveFocus();
                                 }
                             }

                             StyledText {
                                 id: sugChipText

                                 anchors.left: parent.left
                                 anchors.right: parent.right
                                 anchors.top: parent.top
                                 anchors.leftMargin: Tokens.padding.medium
                                 anchors.rightMargin: Tokens.padding.medium
                                 anchors.topMargin: Tokens.padding.medium
                                 text: parent.modelData
                                 color: Colours.palette.m3onSurface
                                 font: Tokens.font.body.small
                                 wrapMode: Text.Wrap
                             }
                         }
                     }
                 }

                 // Files attached to the next message (Claude Code).
                 Flow {
                     id: attachmentStrip

                     anchors.bottom: inputBoxRow.top
                     anchors.bottomMargin: Tokens.spacing.small
                     anchors.left: parent.left
                     anchors.right: parent.right
                     z: 10
                     spacing: Tokens.spacing.small
                     visible: root.isClaudeCode && root.pendingAttachments.length > 0

                     Repeater {
                         model: root.pendingAttachments

                         StyledRect {
                             id: attachChip

                             required property var modelData

                             implicitWidth: Math.min(attachChipRow.implicitWidth + Tokens.padding.medium * 2, attachmentStrip.width)
                             implicitHeight: attachChipRow.implicitHeight + Tokens.padding.small * 2
                             radius: Tokens.rounding.full
                             color: Colours.tPalette.m3secondaryContainer

                             RowLayout {
                                 id: attachChipRow

                                 anchors.fill: parent
                                 anchors.leftMargin: Tokens.padding.medium
                                 anchors.rightMargin: Tokens.padding.small
                                 spacing: Tokens.spacing.small

                                 MaterialIcon {
                                     text: attachChip.modelData.isImage ? "image" : "attach_file"
                                     color: Colours.palette.m3onSecondaryContainer
                                     font: Tokens.font.icon.small
                                 }

                                 StyledText {
                                     Layout.fillWidth: true
                                     Layout.maximumWidth: 180
                                     text: attachChip.modelData.path.replace(/^.*\//, "")
                                     color: Colours.palette.m3onSecondaryContainer
                                     font: Tokens.font.label.medium
                                     elide: Text.ElideMiddle
                                 }

                                 Item {
                                     Layout.preferredWidth: 20
                                     Layout.preferredHeight: 20

                                     MaterialIcon {
                                         anchors.centerIn: parent
                                         text: "close"
                                         color: Colours.palette.m3onSecondaryContainer
                                         font: Tokens.font.icon.small
                                     }

                                     MouseArea {
                                         anchors.fill: parent
                                         cursorShape: Qt.PointingHandCursor
                                         onClicked: root.removeAttachment(attachChip.modelData.path)
                                     }
                                 }
                             }
                         }
                     }
                 }

                 FileDialog {
                     id: attachDialog

                     title: qsTr("Attach a file")
                     onAccepted: path => root.addAttachment(path)
                 }

                 StyledRect {
                     id: inputBoxRow

                     anchors.bottom: parent.bottom
                     anchors.left: parent.left
                     anchors.right: parent.right
                     z: 10
                     implicitHeight: Math.max(48, inputArea.implicitHeight + Tokens.padding.medium * 2)
                     color: Colours.tPalette.m3surfaceContainer
                     radius: 24

                     StyledClippingRect {
                         z: -1
                         anchors.fill: parent
                         radius: 24

                         ShaderEffectSource {
                             id: inputBlurSource

                             sourceItem: contentStack
                             sourceRect: {
                                 var p = parent.mapToItem(contentStack, 0, 0);
                                 return Qt.rect(p.x, p.y, parent.width, parent.height);
                             }
                         }
                         MultiEffect {
                             anchors.fill: parent
                             source: inputBlurSource
                             blurEnabled: true
                             blurMax: 32
                         }
                     }

                     StateLayer {
                         id: inputStateLayer

                         anchors.fill: parent
                         radius: 24
                         hoverEnabled: false
                         cursorShape: Qt.IBeamCursor
                         onClicked: inputArea.forceActiveFocus()
                     }

                     DropArea {
                         anchors.fill: parent
                         enabled: root.isClaudeCode
                         onDropped: drop => {
                             if (!drop.hasUrls)
                                 return;
                             for (var i = 0; i < drop.urls.length; i++)
                                 root.addAttachment(drop.urls[i].toString());
                             drop.acceptProposedAction();
                         }
                     }

                     RowLayout {
                         anchors.fill: parent
                         anchors.leftMargin: Tokens.padding.large
                         anchors.rightMargin: Tokens.padding.small
                         spacing: Tokens.spacing.small

                         ScrollView {
                             id: inputScroll
                             Layout.fillWidth: true
                             Layout.fillHeight: true
                             
                             TextArea {
                                 id: inputArea

                                 verticalAlignment: TextInput.AlignVCenter
                                 placeholderText: qsTr("Ask assistant...")
                                 color: Colours.palette.m3onSurface
                                 placeholderTextColor: Colours.palette.m3outline
                                 font: Tokens.font.body.small
                                 wrapMode: Text.Wrap
                                 selectByMouse: true
                                 background: null

                                 MouseArea {
                                     anchors.fill: parent
                                     hoverEnabled: true
                                     cursorShape: Qt.IBeamCursor
                                     propagateComposedEvents: true
                                     onPressed: mouse => {
                                          var mapped = mapToItem(inputStateLayer, mouse.x, mouse.y);
                                          inputStateLayer.press(mapped.x, mapped.y);
                                          mouse.accepted = false;
                                      }
                                 }

                                 Keys.onPressed: event => {
                                     if (event.key === Qt.Key_Return && !(event.modifiers & Qt.ShiftModifier)) {
                                         event.accepted = true;
                                         if (!root.isTyping) {
                                             root.sendPrompt(inputArea.text);
                                             inputArea.clear();
                                         }
                                     } else if (root.isClaudeCode && event.matches(StandardKey.Paste)) {
                                         // An image on the clipboard becomes an attachment;
                                         // anything else is pasted as text as usual.
                                         event.accepted = true;
                                         root.pasteClipboardImage();
                                     }
                                 }
                             }
                         }

                         // Attach a file (Claude Code).
                         Item {
                             visible: root.isClaudeCode
                             Layout.preferredWidth: visible ? 32 : 0
                             Layout.preferredHeight: 32

                             MaterialIcon {
                                 anchors.centerIn: parent
                                 text: "attach_file"
                                 color: attachMouse.containsMouse ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                                 font: Tokens.font.icon.small
                             }

                             MouseArea {
                                 id: attachMouse

                                 anchors.fill: parent
                                 hoverEnabled: true
                                 cursorShape: Qt.PointingHandCursor
                                 onClicked: attachDialog.open()
                             }
                         }

                         Item {
                             visible: root.isClaudeCode
                             Layout.preferredWidth: visible ? 32 : 0
                             Layout.preferredHeight: 32

                             MaterialIcon {
                                 anchors.centerIn: parent
                                 text: root.loadingSuggestions ? "hourglass_empty" : "lightbulb"
                                 color: sugMouse.containsMouse ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                                 font: Tokens.font.icon.small
                             }

                             MouseArea {
                                 id: sugMouse

                                 anchors.fill: parent
                                 hoverEnabled: true
                                 cursorShape: Qt.PointingHandCursor
                                 onClicked: root.fetchPromptSuggestions()
                             }
                         }

                         Item {
                             Layout.preferredWidth: 36
                             Layout.preferredHeight: 36

                             MaterialShape {
                                 anchors.fill: parent
                                 color: root.isTyping ? Colours.palette.m3error : (root.canSend ? Colours.palette.m3primary : Colours.layer(Colours.tPalette.m3surfaceContainerHigh, 2))
                                 shape: root.isTyping ? MaterialShape.Cookie4Sided : (root.canSend ? MaterialShape.Arrow : MaterialShape.Circle)
                                 scale: (!root.canSend && !root.isTyping) ? 1 : sendMouse.pressed ? 0.6 : sendMouse.containsMouse ? 0.8 : 0.7
                                 rotation: 0
                                 
                                 Behavior on scale { Anim { type: Anim.FastSpatial } }
                                 Behavior on color { CAnim {} }

                                 MouseArea {
                                     id: sendMouse

                                     anchors.fill: parent
                                     hoverEnabled: true
                                     cursorShape: (root.canSend || root.isTyping) ? Qt.PointingHandCursor : Qt.ArrowCursor
                                     onClicked: {
                                         if (root.isTyping) {
                                             root.cancelRateLimitRetry();
                                             if (root.currentRequest) {
                                                 root.currentRequest.abort();
                                             }
                                             root.stopClaudeCode();
                                             root.isTyping = false;
                                             root.isThinking = false;
                                             root.inAgentLoop = false;
                                             typingTimer.stop();
                                             chatHistory.setProperty(chatHistory.count - 1, "isFinished", true);
                                             saveHistory();
                                         } else if (inputArea.text.length > 0 || root.pendingAttachments.length > 0) {
                                             root.sendPrompt(inputArea.text);
                                             inputArea.clear();
                                         }
                                     }
                                 }
                             }

                             MaterialIcon {
                                 anchors.centerIn: parent
                                 text: "arrow_upward"
                                 color: Colours.palette.m3onSurfaceVariant
                                 font: Tokens.font.icon.small
                                 opacity: (root.canSend || root.isTyping) ? 0 : 1

                                 Behavior on opacity { Anim { type: Anim.DefaultEffects } }
                             }
                         }
                     }
                 }
             }

             Item {
                 anchors.fill: parent
                 opacity: isHistoryTab ? 1 : 0
                 visible: opacity > 0

                 Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.InOutQuad } }

                 GridView {
                     anchors.top: parent.top
                     anchors.left: parent.left
                     anchors.right: parent.right
                     anchors.bottom: newChatButton.top
                     anchors.bottomMargin: Tokens.spacing.medium
                     
                     cellWidth: width / 2
                     cellHeight: 90
                     model: historySessionsModel

                     delegate: Item {
                         required property var model
                         property string chatId: model && model.id ? String(model.id) : ""
                         property string chatTitle: model && model.title ? String(model.title) : ""

                         width: GridView.view.cellWidth
                         height: GridView.view.cellHeight

                         StyledRect {
                             anchors.fill: parent
                             anchors.margins: Tokens.spacing.small
                             radius: Tokens.rounding.medium
                             color: Colours.tPalette.m3surfaceContainerHigh

                             StateLayer {
                                 radius: Tokens.rounding.medium
                                 onClicked: loadChat(chatId)
                             }

                             RowLayout {
                                 anchors.fill: parent
                                 anchors.margins: Tokens.padding.small
                                 spacing: Tokens.spacing.medium

                                 StyledRect {
                                     Layout.preferredWidth: 32
                                     Layout.preferredHeight: 32
                                     radius: 16
                                     color: Colours.tPalette.m3surfaceContainerHighest

                                     MaterialIcon {
                                         anchors.centerIn: parent
                                         text: "chat"
                                         color: Colours.palette.m3onSurfaceVariant
                                         font: Tokens.font.icon.small
                                     }
                                 }

                                 ColumnLayout {
                                     Layout.fillWidth: true
                                     spacing: 0

                                     Text {
                                         Layout.fillWidth: true
                                         Layout.alignment: Qt.AlignVCenter
                                         text: chatTitle ? chatTitle : "New Chat"
                                         color: Colours.palette.m3onSurface
                                         font: Tokens.font.label.small
                                         elide: Text.ElideRight
                                          wrapMode: Text.Wrap
                                          maximumLineCount: 3
                                     }
                                 }

                                 Item {
                                     Layout.alignment: Qt.AlignTop | Qt.AlignRight
                                     Layout.preferredWidth: 24
                                     Layout.preferredHeight: 24
                                     
                                     StyledRect {
                                         anchors.fill: parent
                                         radius: 12
                                         color: Colours.palette.m3onSurfaceVariant
                                         opacity: deleteMouseArea.containsMouse ? 0.12 : 0.0

                                         Behavior on opacity { NumberAnimation { duration: 150 } }
                                     }

                                     MaterialIcon {
                                         anchors.centerIn: parent
                                         text: "close"
                                         font: Tokens.font.icon.small
                                         color: Colours.palette.m3onSurfaceVariant
                                     }

                                     MouseArea {
                                         id: deleteMouseArea

                                         anchors.fill: parent
                                         hoverEnabled: true
                                         cursorShape: Qt.PointingHandCursor
                                         onClicked: deleteChat(chatId)
                                     }
                                 }
                             }
                         }
                     }
                 }

                 StyledRect {
                     id: clearAllButton

                     anchors.bottom: parent.bottom
                     anchors.left: parent.left
                     width: clearAllLayout.implicitWidth + Tokens.padding.large * 2
                     height: 32
                     radius: 16
                     color: Colours.palette.m3errorContainer

                     StateLayer {
                         radius: 16
                         onClicked: clearAllHistory()
                     }

                     RowLayout {
                         id: clearAllLayout

                         anchors.centerIn: parent
                         spacing: Tokens.spacing.small

                         MaterialIcon {
                             text: "delete"
                             color: Colours.palette.m3onErrorContainer
                             font: Tokens.font.icon.small
                         }
                         Text {
                             text: qsTr("Clear All")
                             color: Colours.palette.m3onErrorContainer
                             font: Tokens.font.body.small
                         }
                     }
                 }

                 StyledRect {
                     id: newChatButton

                     anchors.bottom: parent.bottom
                     anchors.right: parent.right
                     width: newChatLayout.implicitWidth + Tokens.padding.large * 2
                     height: 32
                     radius: 16
                     color: Colours.palette.m3primaryContainer

                     StateLayer {
                         radius: 16
                         onClicked: createNewChat()
                     }

                     RowLayout {
                         id: newChatLayout

                         anchors.centerIn: parent
                         spacing: Tokens.spacing.small

                         MaterialIcon {
                             text: "add"
                             color: Colours.palette.m3onPrimaryContainer
                             font: Tokens.font.icon.small
                         }
                         Text {
                             text: qsTr("New Chat")
                             color: Colours.palette.m3onPrimaryContainer
                             font: Tokens.font.body.small
                         }
                     }
                 }
             }
         }
    }
}
