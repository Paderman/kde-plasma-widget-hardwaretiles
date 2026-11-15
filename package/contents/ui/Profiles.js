.pragma library

// SPDX-FileCopyrightText: 2026 Paderman
// SPDX-License-Identifier: GPL-2.0-or-later

// Profiles: named snapshots of the view – tiles, order, appearance and
// notification settings. Stored as JSON in the setting "profiles":
//   [{ name, saved: ISO time, hw: [{ addr, vendor, name }], data: { key: value } }]
// Not part of a profile: learned fan curves, update check, setup state –
// they belong to the computer, not to the view.

var FORMAT = "sensordeck-profiles";

// setting -> type ("s" string, "b" bool, "i" int)
var KEYS = {
    items: "s", gpuAddress: "s", layoutPreset: "s", layoutHash: "s", baseOrder: "s",
    gpuSectionMode: "s", fitToSize: "b", columns: "i", updateInterval: "i", historyLength: "i",
    tileStyle: "s", tileScale: "i", backgroundOpacity: "i", tileOpacity: "i", tooltipsEnabled: "b", tooltipDelay: "i", tooltipDuration: "i", panelShowLabels: "b", panelShowRings: "b",
    alertsEnabled: "b", alertOnWarn: "b", alertRecovery: "b", alertDelay: "i",
    alertCooldown: "i", alertHysteresis: "i", fanWatch: "b", fanSlowPercent: "i"
};

function list(json) {
    try {
        var a = JSON.parse(json || "[]");
        if (Array.isArray(a)) return a.filter(function (p) { return p && typeof p.name === "string" && p.data; });
    } catch (e) {}
    return [];
}

function find(profiles, name) {
    for (var i = 0; i < profiles.length; ++i) if (profiles[i].name === name) return profiles[i];
    return null;
}

// "Gaming" -> "Gaming (2)" if taken
function uniqueName(profiles, name) {
    name = String(name || "").trim() || "Profile";
    if (!find(profiles, name)) return name;
    for (var n = 2; ; ++n) if (!find(profiles, name + " (" + n + ")")) return name + " (" + n + ")";
}

// only known settings, with the right type – everything else is dropped
function sanitize(data) {
    var out = {};
    if (!data || typeof data !== "object") return out;
    for (var k in KEYS) {
        if (!(k in data)) continue;
        var v = data[k];
        if (KEYS[k] === "s") out[k] = typeof v === "string" ? v : String(v);
        else if (KEYS[k] === "b") out[k] = v === true || v === "true";
        else { var n = parseInt(v); if (!isNaN(n)) out[k] = Math.max(0, Math.min(1000000, n)); }
    }
    // the tiles must be a JSON array
    if ("items" in out) {
        try { if (!Array.isArray(JSON.parse(out.items))) delete out.items; } catch (e) { delete out.items; }
    }
    return out;
}

function hwSummary(gpus) {
    return (gpus || []).map(function (g) { return { addr: g.addr, vendor: g.vendor, name: g.name || "" }; });
}

function snapshot(cfg) {
    var d = {};
    for (var k in KEYS) d[k] = cfg[k];
    return d;
}

// is the current view the same as the profile?
function sameAs(cfg, profile) {
    if (!profile) return false;
    var d = sanitize(profile.data), c = sanitize(snapshot(cfg));
    for (var k in d) if (String(c[k]) !== String(d[k])) return false;
    return true;
}

// Graphics cards of the profile that this computer does not have are mapped
// to a free card of the same maker, in order (other makers' values differ).
// Returns { data, missing: tiles still bound to an absent card, moved: cards remapped }
function remap(data, savedHw, gpus) {
    data = sanitize(data);
    gpus = gpus || [];
    var present = {}, map = {}, used = {}, moved = 0;
    gpus.forEach(function (g) { present[g.addr] = true; });
    var vendorOf = {};
    (savedHw || []).forEach(function (g) { vendorOf[g.addr] = g.vendor; });

    var tiles = [];
    try { tiles = JSON.parse(data.items || "[]"); } catch (e) { tiles = []; }
    var addrs = [];
    function want(a) { if (a && addrs.indexOf(a) < 0) addrs.push(a); }
    want(data.gpuAddress);
    tiles.forEach(function (t) { want(t.gpu); if (t.source === "pcie") want(t.key); });
    addrs.forEach(function (a) { if (present[a]) used[a] = true; });

    addrs.forEach(function (a) {
        if (present[a]) return;
        var free = gpus.filter(function (g) { return !used[g.addr]; });
        var same = free.filter(function (g) { return vendorOf[a] && g.vendor === vendorOf[a]; });
        var pick = same[0] || null;
        if (pick) { map[a] = pick.addr; used[pick.addr] = true; moved++; }
    });

    var missing = 0;
    tiles.forEach(function (t) {
        if (t.gpu && map[t.gpu]) t.gpu = map[t.gpu];
        if (t.source === "pcie" && t.key && map[t.key]) t.key = map[t.key];
        if (t.gpu && !present[t.gpu]) missing++;
    });
    if (data.gpuAddress && !present[data.gpuAddress])
        data.gpuAddress = map[data.gpuAddress] || "";   // "" = first card found
    if ("items" in data) data.items = JSON.stringify(tiles);
    return { data: data, missing: missing, moved: moved };
}

function apply(cfg, data) {
    data = sanitize(data);
    for (var k in data) cfg[k] = data[k];
}

// Loads a profile into cfg (Plasmoid.configuration); the current view is kept
// as backup for "Undo profile change". gpus: graphics cards of this computer.
// Returns how many tiles belong to a graphics card this computer does not have (-1 = not found).
function load(cfg, name, gpus) {
    var p = find(list(cfg.profiles), name);
    if (!p) return -1;
    cfg.profileBackup = JSON.stringify({ name: cfg.activeProfile, data: snapshot(cfg) });
    var r = remap(p.data, p.hw, gpus);
    apply(cfg, r.data);
    cfg.activeProfile = name;
    cfg.setupDone = true;
    return r.missing;
}

function backup(cfg) {
    try { var b = JSON.parse(cfg.profileBackup || "null"); return b && b.data ? b : null; }
    catch (e) { return null; }
}

function undo(cfg) {
    var b = backup(cfg);
    if (!b) return false;
    apply(cfg, b.data);
    cfg.activeProfile = b.name || "";
    cfg.profileBackup = "";
    return true;
}

// saves the current view as profile name (replaces one of the same name)
function save(cfg, name, gpus) {
    var l = list(cfg.profiles).filter(function (p) { return p.name !== name; });
    l.push({ name: name, saved: new Date().toISOString(), hw: hwSummary(gpus), data: sanitize(snapshot(cfg)) });
    l.sort(function (a, b) { return a.name.localeCompare(b.name); });
    cfg.profiles = JSON.stringify(l);
    cfg.activeProfile = name;
}

// shell commands of the tiles that Sensor Deck did not create itself
// (gddr6 and power service files are known and harmless)
var SAFE_CMD = /^cat \/run\/(gddr6|sensordeck-power)\/[A-Za-z0-9_.:{}-]+( 2>\/dev\/null \|\| cat \/run\/gddr6\/vram)?$/;
function commands(data) {
    var out = [];
    var tiles = [];
    try { tiles = JSON.parse((data && data.items) || "[]"); } catch (e) { return out; }
    if (!Array.isArray(tiles)) return out;
    tiles.forEach(function (t) {
        [t.source === "command" ? t.command : "", t.ySource === "command" ? t.yCommand : ""].forEach(function (c) {
            c = String(c || "").trim();
            if (c && !SAFE_CMD.test(c) && out.indexOf(c) < 0) out.push(c);
        });
    });
    return out;
}

// ---- files --------------------------------------------------------------------
function exportText(profiles, version) {
    return JSON.stringify({ format: FORMAT, version: 1, app: version || "", profiles: profiles }, null, 2) + "\n";
}

// -> { profiles: [...], error: "" | "format" | "empty" }
function parseImport(text) {
    var o;
    try { o = JSON.parse(text); } catch (e) { return { profiles: [], error: "format" }; }
    var raw = o && o.format === FORMAT && Array.isArray(o.profiles) ? o.profiles
            : (o && typeof o.name === "string" && o.data ? [o] : null);   // a single profile
    if (!raw) return { profiles: [], error: "format" };
    var out = [];
    raw.forEach(function (p) {
        if (!p || typeof p.name !== "string" || !p.data) return;
        var d = sanitize(p.data);
        if (!("items" in d)) return;
        out.push({ name: p.name.slice(0, 80), saved: String(p.saved || ""),
                   hw: Array.isArray(p.hw) ? p.hw.filter(function (g) { return g && typeof g.addr === "string"; })
                                                 .map(function (g) { return { addr: g.addr, vendor: String(g.vendor || ""), name: String(g.name || "") }; })
                                           : [],
                   data: d });
    });
    return { profiles: out, error: out.length ? "" : "empty" };
}

// UTF-8 text <-> base64, to pass file contents through a shell command safely
var B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
function toBase64(str) {
    var bytes = [];
    for (var i = 0; i < str.length; ++i) {
        var c = str.charCodeAt(i);
        if (c >= 0xd800 && c < 0xdc00 && i + 1 < str.length) {
            c = 0x10000 + ((c - 0xd800) << 10) + (str.charCodeAt(++i) - 0xdc00);
        }
        if (c < 0x80) bytes.push(c);
        else if (c < 0x800) bytes.push(0xc0 | c >> 6, 0x80 | c & 63);
        else if (c < 0x10000) bytes.push(0xe0 | c >> 12, 0x80 | c >> 6 & 63, 0x80 | c & 63);
        else bytes.push(0xf0 | c >> 18, 0x80 | c >> 12 & 63, 0x80 | c >> 6 & 63, 0x80 | c & 63);
    }
    var out = "";
    for (var j = 0; j < bytes.length; j += 3) {
        var n = bytes[j] << 16 | (bytes[j + 1] || 0) << 8 | (bytes[j + 2] || 0);
        out += B64[n >> 18 & 63] + B64[n >> 12 & 63]
             + (j + 1 < bytes.length ? B64[n >> 6 & 63] : "=")
             + (j + 2 < bytes.length ? B64[n & 63] : "=");
    }
    return out;
}

// path of a file:// URL, quoted for the shell
function shellPath(url) {
    var p = decodeURIComponent(String(url).replace(/^file:\/\//, ""));
    return "'" + p.replace(/'/g, "'\\''") + "'";
}
