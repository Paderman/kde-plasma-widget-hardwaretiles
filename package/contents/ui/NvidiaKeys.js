.pragma library

// SPDX-FileCopyrightText: 2026 Paderman
// SPDX-License-Identifier: GPL-2.0-or-later

// ---- translation: user-visible texts are tr("English"); the QML side passes
// its i18n() as `translate` (KDE gettext). Without it the English text is used.
var _tr = null;
function tr(s) {
    var a = Array.prototype.slice.call(arguments, 1);
    if (_tr) return _tr.apply(null, [s].concat(a));
    for (var i = 0; i < a.length; ++i) s = s.split("%" + (i + 1)).join(String(a[i]));
    return s;
}

// Values queried from `nvidia-smi --query-gpu=…` (one call per interval for all tiles).
// unit:   display unit; max: default maximum; maxKey: key whose value is the maximum
// kind:   "num" (default) | "pstate" | "throttle" | "pcie"
// mib:    value is MiB -> shown as GiB when large

var keys = [
    { key: "temperature.gpu",          label: tr("GPU temperature"),        unit: "°C",  max: 100 },
    { key: "fan.speed",                label: tr("Fan"),                unit: "%",   max: 100 },
    // measured speed from the driver library (code/nvml-fans.py), not from nvidia-smi
    { key: "fan.rpm",                  label: tr("Fan speed (all fans)"), unit: "RPM", nvml: true },
    { key: "fan.rpm.1",                label: tr("Fan 1 speed"),          unit: "RPM", nvml: true },
    { key: "fan.rpm.2",                label: tr("Fan 2 speed"),          unit: "RPM", nvml: true },
    { key: "fan.rpm.3",                label: tr("Fan 3 speed"),          unit: "RPM", nvml: true },
    { key: "utilization.gpu",          label: tr("GPU load"),              unit: "%",   max: 100 },
    { key: "utilization.memory",       label: tr("VRAM activity"),        unit: "%",   max: 100 },
    { key: "utilization.encoder",      label: tr("Video encoding (NVENC)"),  unit: "%",   max: 100 },
    { key: "utilization.decoder",      label: tr("Video decoding (NVDEC)"),  unit: "%",   max: 100 },
    { key: "power.draw",               label: tr("Power draw"),             unit: "W",   maxKey: "enforced.power.limit" },
    { key: "enforced.power.limit",     label: tr("Power limit"),           unit: "W",   maxKey: "power.max_limit" },
    { key: "clocks.gr",                label: tr("GPU clock"),              unit: "MHz", maxKey: "clocks.max.gr" },
    { key: "clocks.mem",               label: tr("Memory clock"),          unit: "MHz", maxKey: "clocks.max.mem" },
    { key: "clocks.video",             label: tr("Video clock"),             unit: "MHz", maxKey: "clocks.max.gr" },
    { key: "memory.used",              label: tr("VRAM used"),           unit: "MiB", maxKey: "memory.total", mib: true },
    { key: "memory.free",              label: tr("VRAM free"),             unit: "MiB", maxKey: "memory.total", mib: true },
    { key: "memory.total",             label: tr("VRAM total"),           unit: "MiB", mib: true },
    { key: "pstate",                   label: tr("Performance level (P-state)"), kind: "pstate", max: 12 },
    { key: "clocks_event_reasons.active", label: tr("Throttling"),         kind: "throttle", max: 1 }
    // PCIe link: see source "pcie" (sysfs) – it also knows the slot's limit
];

// extra fields that are only needed as maxima / for derived texts
var helperKeys = ["clocks.max.gr", "clocks.max.mem", "power.max_limit", "name"];

function allQueryKeys() {
    var out = [];
    keys.forEach(function (k) { if (!k.nvml && out.indexOf(k.key) < 0) out.push(k.key); });
    helperKeys.forEach(function (k) { if (out.indexOf(k) < 0) out.push(k); });
    return out;
}

function meta(key) {
    for (var i = 0; i < keys.length; ++i) if (keys[i].key === key) return keys[i];
    return { key: key, label: key, unit: "" };
}

function indexOf(key) {
    for (var i = 0; i < keys.length; ++i) if (keys[i].key === key) return i;
    return -1;
}

// bit -> text (nvmlClocksEventReasons); English, translated in decode().
// For the translation template only:
function _units() { return [tr("RPM")]; }
function _throttleNames() { return [tr("Power limit"), tr("Hardware slowdown"), tr("Temperature target"), tr("Overheating!"),
                                   tr("Power supply slowdown"), tr("Clock locked"), tr("Synced to other GPU"), tr("Display clock")]; }
var throttleBits = [
    [0x4,   "Power limit"],
    [0x8,   "Hardware slowdown"],
    [0x20,  "Temperature target"],
    [0x40,  "Overheating!"],
    [0x80,  "Power supply slowdown"],
    [0x2,   "Clock locked"],
    [0x10,  "Synced to other GPU"],
    [0x100, "Display clock"]
];

// P0 = full performance … P8 and above = idle / power saving
function pstateText(n) {
    if (n <= 0) return tr("Maximum");
    if (n <= 2) return tr("High");
    if (n <= 7) return tr("Medium");
    return tr("Power saving");
}

// Interprets one raw csv field. Returns {value: number|NaN, text: string|""}
// translate: QML i18n for the texts (P-state, throttle reasons)
function decode(key, raw, all, translate) {
    _tr = translate || null;
    var m = meta(key);
    raw = (raw || "").trim();
    if (raw === "" || raw.indexOf("N/A") >= 0 || raw.indexOf("Not Supported") >= 0)
        return { value: NaN, text: "" };

    if (m.kind === "pstate") {
        var n = parseInt(raw.replace(/[^0-9]/g, ""));
        // the word first – it is what most people understand; the number for those who know it
        return { value: n, text: isNaN(n) ? raw : pstateText(n) + " (P" + n + ")" };
    }
    if (m.kind === "throttle") {
        var bits = parseInt(raw, 16) || 0;
        var names = [];
        throttleBits.forEach(function (b) { if (bits & b[0]) names.push(tr(b[1])); });
        // 0x1 = GPU idle: not a real throttle
        var active = names.length > 0 && (bits & 0xEC) !== 0;
        return { value: active ? 1 : 0, text: names.length ? names.join(", ") : (bits & 0x1 ? tr("Idle") : tr("None")) };
    }
    if (m.kind === "pcie") {
        var gen = parseInt(raw);
        var w = all ? parseInt(all["pcie.link.width.current"]) : NaN;
        var wm = all ? parseInt(all["pcie.link.width.max"]) : NaN;
        var t = "Gen " + gen + (isNaN(w) ? "" : " ×" + w);
        if (!isNaN(wm) && wm !== w) t += " (max ×" + wm + ")";
        return { value: gen, text: t };
    }
    var v = parseFloat(raw);
    return { value: v, text: "" };
}

// "fan.rpm.2" -> 2, "fan.rpm" / "fan.speed" -> 0 (all fans), others -> -1
function fanNo(key) {
    var m = /^fan\.(?:rpm|speed)(?:\.(\d+))?$/.exec(key || "");
    return m ? (m[1] ? parseInt(m[1]) : 0) : -1;
}
