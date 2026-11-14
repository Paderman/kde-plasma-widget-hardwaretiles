.pragma library

// SPDX-FileCopyrightText: 2026 Paderman
// SPDX-License-Identifier: GPL-2.0-or-later

// Schema of one tile
// id:          stable identifier (keeps history when tiles are reordered)
// source:      "sensor" (ksystemstats) | "command" (shell command) | "nvidia" (nvidia-smi field)
//              | "pcie" (PCIe link of the graphics card from sysfs; key = PCI address, "" = auto)
//              | "igpu" (Intel graphics in the processor; key = "load" | "clock" | "render" | "video" | "memory")
// sensorId:    ksystemstats id, e.g. "gpu/gpu5/temperature"
// command:     shell command, e.g. "cat /run/gddr6/vram"
// key:         nvidia-smi field, e.g. "fan.speed"
// unit:        unit text for command sources
// refSensorId: optional ksystemstats sensor used as maximum + "/ total" (e.g. totalVram)
// relThresholds: warn/crit are percent of the total (refSensorId / natural maximum)
// style:       "ring" | "bar" | "graph" | "value" | "curve"
// min / max:   value range (max 0 = auto)
// warn / crit: thresholds (0 = off)
// wide:        span two columns
// showInPanel: show in the compact (panel) view
// color:       accent color ("" = automatic palette)
// notify:      send desktop notifications when thresholds are crossed
// gpu:         PCI address of the graphics card this tile belongs to ("" = the widget's main card)
// compare:     show the value of ALL graphics cards in this tile (GPU tokens resolved per card)
// curve tiles: x = main source (temperature), y = ySource/ySensorId/yCommand/yKey/yUnit, yMax
//              refCurve: optional reference curve "30:30 50:40 70:70 85:100"

// warning / critical colours: bright on dark backgrounds, darker on light ones so
// texts like "Power limit" keep enough contrast (about 5:1 on Breeze Light)
function warnColor(light) { return light ? "#a35a00" : "#ffb020"; }
function critColor(light) { return light ? "#c0123f" : "#ff4d6d"; }

var palette = ["#8b7bff", "#22c3ff", "#2fe0a0", "#ff7eb6", "#ffb547", "#5ad8e6", "#c48bff", "#9be15d"];

// the palette above glows on dark backgrounds but is pale on light ones; there
// each colour is replaced by a deeper shade of the same hue (at least 4:1 on white)
var lightShades = {
    "#8b7bff": "#6247e0", "#22c3ff": "#0279b8", "#2fe0a0": "#038a5e", "#ff7eb6": "#d0236e",
    "#ffb547": "#b85c00", "#5ad8e6": "#0a849e", "#c48bff": "#8a35d9", "#9be15d": "#4a8a12"
};

function luminance(c) {
    function ch(v) { return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); }
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

// accent colour fitted to the theme: unchanged on dark backgrounds; on light ones
// a known palette colour gets its deeper shade, any other (user-picked) colour is
// darkened step by step until it has enough contrast
function themed(c, light) {
    if (!light || !c) return c;
    var key = String(c).toLowerCase();
    if (lightShades[key]) return lightShades[key];
    var q = Qt.color(key);
    if (q.a === 0) return c;
    var h = Math.max(0, q.hslHue), s = q.hslSaturation, l = q.hslLightness;
    for (var i = 0; i < 20 && luminance(q) > 0.2; ++i) {
        l *= 0.9;
        q = Qt.hsla(h, s, l, q.a);
    }
    return q;
}

function blank() {
    return {
        id: "", label: "", source: "sensor", sensorId: "", command: "", key: "", unit: "",
        refSensorId: "",
        style: "ring", min: 0, max: 0, warn: 0, crit: 0,
        wide: false, showInPanel: false, color: "", notify: true,
        ySource: "nvidia", ySensorId: "", yCommand: "", yKey: "fan.speed", yUnit: "", yMax: 0,
        refCurve: "", gpu: "", compare: false, relThresholds: false
    };
}

function newId() {
    return "t" + Date.now().toString(36) + Math.floor(Math.random() * 1e6).toString(36);
}

function hash(str) {
    var h = 0;
    for (var i = 0; i < str.length; ++i) h = (h * 31 + str.charCodeAt(i)) | 0;
    return Math.abs(h);
}

// stable automatic colour per tile id ("d3" -> palette[2] for the defaults)
function colorFor(id) {
    id = id || "";
    var m = id.match(/^[dgs](\d+)$/);
    var n = m ? parseInt(m[1]) - 1 : hash(id);
    return palette[n % palette.length];
}

function normalize(it, index) {
    var b = blank();
    for (var k in b) {
        if (it && it[k] !== undefined && it[k] !== null) b[k] = it[k];
    }
    // migrate: fixed GPU numbers ("gpu/gpu5/…") -> the GPU chosen for this widget
    ["sensorId", "refSensorId", "ySensorId"].forEach(function (k) {
        if (typeof b[k] === "string") b[k] = b[k].replace(/^gpu\/gpu\d+\//, "gpu/{gpu}/");
    });
    if (b.command === "cat /run/gddr6/vram") b.command = "cat /run/gddr6/vram-{gpuaddr} 2>/dev/null || cat /run/gddr6/vram";
    // migrate: the old nvidia-smi PCIe field -> sysfs source (knows the slot limit)
    if (b.source === "nvidia" && b.key === "pcie.link.gen.current") { b.source = "pcie"; b.key = ""; }
    if (!b.id) b.id = "a" + (index || 0) + "-" + hash(b.source + b.sensorId + b.command + b.key + b.label).toString(36);
    // migrate: the old default label "VRAM" of the memory temperature tile (after the id, so it stays stable)
    if ((b.label === "VRAM" || b.label === "VRAM-Temp") && (/\/run\/gddr6\/vram/.test(b.command) || /^lmsensors\/.*\/temp3$/.test(b.sensorId)))
        b.label = "VRAM-Temperatur";
    // migrate: old label of the NVIDIA throttle-reason tile
    if (b.label === "Drosselung" && b.key === "clocks_event_reasons.active") b.label = "Taktbremse";
    // migrate: old default labels -> clearer names (only exact old defaults, own names stay)
    b.label = renamed(b);
    // migrate: memory in percent -> "12.3 / 64 GiB" like VRAM, thresholds in % of the
    // total. Only tiles with the old template values – own settings stay.
    if (b.source === "sensor" && b.sensorId === "memory/physical/usedPercent" && !b.refSensorId
            && (Number(b.max) === 100 || Number(b.max) === 0) && !b.unit
            && ((b.warn == 85 && b.crit == 95) || (b.warn == 80 && b.crit == 92) || (!b.warn && !b.crit))) {
        b.sensorId = "memory/physical/used";
        b.refSensorId = "memory/physical/total";
        b.max = 0;
        b.relThresholds = true;
        if (!b.warn && !b.crit) { b.warn = 85; b.crit = 95; }
    }
    return b;
}

// "Gehäuselüfter vorne (fan1)" -> "Gehäuselüfter vorne" (sensor number stays in the tooltip)
function stripSensorNo(label) {
    var s = String(label || "").replace(/\s*\((fan|temp|pwm|in)\d+\)\s*$/i, "");
    return s || label;
}

// "PLEXTOR PX-512M8PeG" -> "Plextor-SSD · Temperature" (translated)
function nvmeLabel(model, translate) {
    var tr = function (s) {
        var a = Array.prototype.slice.call(arguments, 1);
        if (translate) return translate.apply(null, [s].concat(a));
        for (var i = 0; i < a.length; ++i) s = s.split("%" + (i + 1)).join(String(a[i]));
        return s;
    };
    var brand = String(model || "").trim().split(/\s+/)[0] || "NVMe";
    if (/^[A-Z]{4,}$/.test(brand))
        brand = brand.charAt(0) + brand.slice(1).toLowerCase();
    return brand === "NVMe" ? tr("NVMe · Temperature") : tr("%1-SSD · Temperature", brand);
}

function renamed(b) {
    var l = b.label, k = b.key, s = b.sensorId || "";
    var nv = b.source === "nvidia";
    if ((l === "GPU" || l === "GPU-Temp") && ((nv && k === "temperature.gpu") || /^gpu\/.*\/temperature$/.test(s))) return "GPU-Temperatur";
    if ((l === "CPU" || l === "CPU-Temp") && /^cpu\/.*Temperature$/.test(s)) return "CPU-Temperatur";
    if (l === "GPU-Leistung" && ((nv && k === "power.draw") || /^gpu\/.*\/power$/.test(s))) return "GPU-Verbrauch";
    if (l === "NVENC" && nv && k === "utilization.encoder") return "Video-Kodierung";
    if (l === "NVDEC" && nv && k === "utilization.decoder") return "Video-Dekodierung";
    if (l === "P-State" && nv && k === "pstate") return "Leistungsstufe";
    if ((l === "Gehäuse" || l === "Gehäuse-Temp") && /^lmsensors\/.*\/temp\d+$/.test(s)) return "Gehäuse-Temperatur";
    if (l === "Hotspot" && /^lmsensors\/.*\/temp2$/.test(s)) return "GPU-Hotspot";
    if (l === "Lüfterkurve" && b.style === "curve") return "GPU-Lüfterkurve";
    if (l === "RAM" && s === "memory/physical/usedPercent") return "Arbeitsspeicher";
    if (/^lmsensors\/.*\/fan\d+$/.test(s) && /\((fan)\d+\)\s*$/.test(l)) return stripSensorNo(l);
    if (/^lmsensors\/nvme[^/]*\/temp1$/.test(s) && / · Temp$/.test(l)) return l.replace(/ · Temp$/, " · Temperatur");
    // NVMe temperature tiles were named after the model ("PLEXTOR PX-512M8PeG")
    // (model names contain a digit – own names like "System-SSD" stay)
    if (/^lmsensors\/nvme[^/]*\/temp1$/.test(s) && !/temp|°/i.test(l) && /\d/.test(l) && l.split(/\s+/).length <= 2) return nvmeLabel(l);
    return l;
}

// Standard values of the settings pages ("Standardwerte wiederherstellen").
// Keep in sync with config/main.xml (gpuSectionMode: "" there means "auto",
// read from the old gpuSections switch).
var settings = {
    appearance: {
        columns: 0, fitToSize: true, tileStyle: "glass", tileScale: 100,
        gpuSectionMode: "auto", gpuSections: true,
        updateInterval: 1500, historyLength: 60,
        panelShowRings: true, panelShowLabels: false
    },
    alerts: {
        alertsEnabled: true, alertOnWarn: false, alertRecovery: true,
        alertDelay: 5, alertHysteresis: 3, alertCooldown: 10,
        fanWatch: true, fanSlowPercent: 50
    }
};

function make(o) { return normalize(o, 0); }

// A new widget starts empty -> the setup wizard builds tiles for the detected hardware.
function items() { return []; }

function parse(json) {
    try {
        var a = JSON.parse(json || "");
        if (Array.isArray(a)) return a.map(function (it, i) { return normalize(it, i); });
    } catch (e) {}
    return items();
}

// fingerprint of a tile list (JSON) without the ids – equal as long as no tile
// was added, removed, edited or moved
function signature(json) {
    return String(hash(JSON.stringify(parse(json).map(function (it) {
        var o = {};
        for (var k in it) if (k !== "id") o[k] = it[k];
        return o;
    }))));
}

// "30:30 50:40 70:70" -> [{x:30,y:30}, …] sorted by x
function parseCurve(str) {
    var pts = [];
    (str || "").split(/[\s;]+/).forEach(function (p) {
        var m = p.match(/^(-?\d+(?:[.,]\d+)?)[:=\/](-?\d+(?:[.,]\d+)?)$/);
        if (m) pts.push({ x: parseFloat(m[1].replace(",", ".")), y: parseFloat(m[2].replace(",", ".")) });
    });
    pts.sort(function (a, b) { return a.x - b.x; });
    return pts;
}
