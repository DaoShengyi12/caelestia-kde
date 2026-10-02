.pragma library

// Plain data operations on the AI assistant's chat sessions. Kept free of QML
// types so they can be tested on their own; ChatStore.qml owns the state.
//
// A session: { id, title, messages, claudeCodeCwd, claudeCodePermissionMode,
// claudeCodeSessionId, claudeCodeSessionAccount }. A message has a stable id,
// which is how running requests find the message they write to.

var nextMessageSerial = 0;

// Fields kept per message, with their defaults. Every message carries all of
// them so the ListModel rows built from them always have the same roles.
var messageDefaults = {
    "msgId": "",
    "isUser": false,
    "text": "",
    "isFinished": true,
    "thoughtText": "",
    "toolsJson": "",
    "usageText": "",
    "attachments": "",
    // View state, not stored: the message was just added (pops in once), and
    // which parts of it are expanded (survives the delegate being recreated).
    "isNew": false,
    "thoughtExpanded": false,
    "expandedTools": ""
};

var viewOnlyFields = ["isNew", "thoughtExpanded", "expandedTools"];

function newMessageId() {
    nextMessageSerial++;
    return "m_" + Date.now().toString(36) + "_" + nextMessageSerial;
}

function newMessage(fields) {
    var m = {};
    for (var k in messageDefaults)
        m[k] = messageDefaults[k];
    for (var f in fields || {})
        if (f in messageDefaults && fields[f] !== undefined && fields[f] !== null)
            m[f] = fields[f];
    if (!m.msgId)
        m.msgId = newMessageId();
    return m;
}

function isDefaultTitle(title) {
    return !title || title === "Legacy Chat" || String(title).indexOf("New Chat") === 0;
}

function find(sessions, id) {
    for (var i = 0; i < sessions.length; i++)
        if (sessions[i].id === id)
            return sessions[i];
    return null;
}

function findMessage(session, msgId) {
    if (!session)
        return null;
    var msgs = session.messages;
    // Messages being written to are almost always the last ones.
    for (var i = msgs.length - 1; i >= 0; i--)
        if (msgs[i].msgId === msgId)
            return msgs[i];
    return null;
}

// Sessions as saved in the config. Nothing can still be running after a
// restart, so every stored reply counts as finished, and empty placeholders
// left by an interrupted reply are dropped.
function parseStored(json) {
    var parsed;
    try {
        parsed = JSON.parse(json || "[]");
    } catch (e) {
        return [];
    }
    if (!Array.isArray(parsed))
        return [];
    var out = [];
    for (var i = 0; i < parsed.length; i++) {
        var s = parsed[i];
        if (!s || !s.id)
            continue;
        var msgs = [];
        var stored = Array.isArray(s.messages) ? s.messages : [];
        for (var j = 0; j < stored.length; j++) {
            var m = stored[j];
            if (!m || (!m.isUser && !m.text && !m.toolsJson))
                continue;
            msgs.push(newMessage({
                "msgId": m.msgId,
                "isUser": m.isUser === true,
                "text": m.text || "",
                "isFinished": true,
                "thoughtText": m.thoughtText || "",
                "toolsJson": m.toolsJson || "",
                "usageText": m.usageText || "",
                "attachments": m.attachments || ""
            }));
        }
        var session = {};
        for (var key in s)
            session[key] = s[key];
        session.messages = msgs;
        out.push(session);
    }
    return out;
}

// What gets written to the config: chats with at least one message, without
// view state, and without a reply placeholder that has nothing in it yet.
function serialize(sessions) {
    var out = [];
    for (var i = 0; i < sessions.length; i++) {
        var s = sessions[i];
        var msgs = [];
        for (var j = 0; j < s.messages.length; j++) {
            var m = s.messages[j];
            if (!m.isUser && !m.isFinished && !m.text && !m.toolsJson)
                continue;
            var copy = {};
            for (var k in m)
                if (viewOnlyFields.indexOf(k) === -1)
                    copy[k] = m[k];
            msgs.push(copy);
        }
        if (msgs.length === 0)
            continue;
        var session = {};
        for (var key in s)
            session[key] = s[key];
        session.messages = msgs;
        out.push(session);
    }
    return JSON.stringify(out);
}

// The stored JSON with the given chats removed, or null if none of them is in it.
function withoutChats(json, ids) {
    var stored;
    try {
        stored = JSON.parse(json || "[]");
    } catch (e) {
        return null;
    }
    if (!Array.isArray(stored))
        return null;
    var kept = stored.filter(s => !s || ids.indexOf(s.id) === -1);
    return kept.length === stored.length ? null : JSON.stringify(kept);
}

function firstUserText(session) {
    var msgs = session ? session.messages : [];
    for (var i = 0; i < msgs.length; i++)
        if (msgs[i].isUser)
            return msgs[i].text || "";
    return "";
}
