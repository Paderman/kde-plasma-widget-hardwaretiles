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

// Plain-language explanations for the tile tooltips:
//   about(cfg)            – what the tile measures (one or two sentences)
//   now(cfg, text, value) – what the current value means (only where it helps)

function is(cfg, nvKey, sensorRe) {
    if (cfg.source === "nvidia" && nvKey && (Array.isArray(nvKey) ? nvKey.indexOf(cfg.key) >= 0 : cfg.key === nvKey)) return true;
    return !!(sensorRe && typeof cfg.sensorId === "string" && sensorRe.test(cfg.sensorId));
}

function about(cfg, translate) {
    _tr = translate || null;
    if (!cfg) return "";
    var cmd = cfg.command || "";

    if (cfg.style === "curve")
        return tr("Shows how fast the graphics card fans spin at which temperature. The widget learns the line from the measurements; the dot is the current state.");
    if (/\/run\/sensordeck-power\/igpu/.test(cmd))
        return tr("Current power draw of the graphics built into the processor. Near 0 W when idle, a few to about 15 W under load.");
    if (/\/run\/sensordeck-power\//.test(cmd))
        return tr("Current power draw of the processor, averaged over one second. Low when idle, much higher under full load – the maximum depends on the processor.");
    if (cfg.source === "igpu" && cfg.key === "render")
        return tr("How busy the 3D and compute unit of the graphics built into the processor is – games, desktop effects, browsers. Only programs of your user are counted.");
    if (cfg.source === "igpu" && cfg.key === "video")
        return tr("How busy the video unit of the graphics built into the processor is – playing, recording or converting videos. Only programs of your user are counted.");
    if (cfg.source === "igpu" && cfg.key === "memory")
        return tr("Graphics built into the processor have no memory of their own – they use part of the main memory. This shows how much the programs using them occupy right now.");
    if (cfg.source === "igpu" && cfg.key === "clock")
        return tr("Current clock of the graphics built into the processor. 0 MHz means it is asleep – normal when it has nothing to do.");
    if (cfg.source === "igpu")
        return tr("How busy the graphics built into the processor is. Measured as the share of time it is not asleep to save power – a good estimate, not an exact value.");
    if (cfg.source === "pcie")
        return tr("Link between graphics card and mainboard: generation (Gen) and number of data lanes (×). When idle the card often drops to a lower generation to save power – that is normal.");

    // ---- graphics card
    if (/\/run\/gddr6\/vram/.test(cmd) || is(cfg, null, /^lmsensors\/.*amdgpu.*\/temp3$/) || is(cfg, null, /^lmsensors\/\{gpuhwmon\}\/temp3$/))
        return tr("Temperature of the graphics memory (VRAM). It usually runs hotter than the graphics chip – 80–95 °C under load is common.");
    if (is(cfg, null, /^lmsensors\/.*\/temp2$/) && /hotspot/i.test(cfg.label || ""))
        return tr("Hottest spot on the graphics chip. Usually 10–20 °C above the GPU temperature.");
    if (is(cfg, "temperature.gpu", /^gpu\/[^/]+\/temperature$/))
        return tr("Temperature of the graphics chip. 60–80 °C under load is normal.");
    if (is(cfg, "fan.speed", /^lmsensors\/(\{gpuhwmon\}|amdgpu[^/]*)\/fan\d+$/))
        return tr("Speed of the graphics card fans. 0 when idle is normal – many cards switch the fans off completely then.");
    if (is(cfg, "utilization.gpu", /^gpu\/[^/]+\/usage$/))
        return tr("How busy the graphics chip is right now. 95–100 % while gaming is normal and desired.");
    if (is(cfg, "power.draw", /^gpu\/[^/]+\/power$/))
        return tr("Current power draw of the graphics card. The second value is its power limit – when it reaches it, it lowers its clock (see Throttling).");
    if (is(cfg, "enforced.power.limit"))
        return tr("Maximum allowed power draw of the graphics card. Above it, the card lowers its clock.");
    if (is(cfg, ["memory.used", "memory.free", "memory.total"], /^gpu\/[^/]+\/(used|free|total)Vram$/))
        return tr("Graphics memory (VRAM) for textures, images and compute data. When it is full, games have to fall back to slower system memory – that can cause stutter.");
    if (is(cfg, "utilization.memory"))
        return tr("Share of time in which the graphics memory is being read or written.");
    if (is(cfg, "clocks.gr", /^gpu\/[^/]+\/coreFrequency$/))
        return tr("Current clock of the graphics chip. It changes constantly: high under load, low when idle. The second value is the maximum clock.");
    if (is(cfg, "clocks.mem", /^gpu\/[^/]+\/memoryFrequency$/))
        return tr("Clock of the graphics memory. When idle the card lowers it a lot to save power.");
    if (is(cfg, "clocks.video"))
        return tr("Clock of the video units that encode and decode videos.");
    if (is(cfg, "utilization.encoder"))
        return tr("Load of the video encoder (NVENC). Active when recording the screen, streaming or exporting video, e.g. with OBS.");
    if (is(cfg, "utilization.decoder"))
        return tr("Load of the video decoder (NVDEC). Active when playing videos, e.g. on YouTube or in a video player.");
    if (is(cfg, "pstate"))
        return tr("Power state of the graphics card: P0 is full performance, P8 and above is idle power saving.");
    if (is(cfg, "clocks_event_reasons.active"))
        return tr("Shows whether and why the graphics card is currently running below its possible clock.");

    // ---- system
    if (is(cfg, null, /^cpu\/.*[Tt]emperature$/))
        return tr("Temperature of the hottest processor core. 60–85 °C under load is normal.");
    if (is(cfg, null, /^cpu\/[^/]+\/usage$/))
        return tr("Combined usage of all processor cores.");
    if (is(cfg, null, /^memory\/physical\//))
        return tr("Used system memory (RAM). When it runs low, the system swaps to disk and becomes noticeably slower.");
    if (is(cfg, null, /^disk\/[^/]+\/used/))
        return tr("Used disk space. Above 90 % it is time to clean up – very full SSDs get slower.");
    if (is(cfg, null, /^lmsensors\/nvme[^/]*\/temp\d+$/))
        return tr("Temperature of the SSD. Up to about 70 °C is fine; above that it slows down to protect itself.");
    if (is(cfg, null, /^lmsensors\/[^/]+\/fan\d+$/))
        return tr("Speed of this fan in revolutions per minute. 0 means it is standing still – intended for some fans when idle.");
    if (is(cfg, null, /^lmsensors\/[^/]+\/temp\d+$/))
        return tr("Temperature on the mainboard – a good indicator of the heat inside the case. 30–45 °C is common.");
    if (is(cfg, null, /^network\/[^/]+\/download$/))
        return tr("Amount of data currently being received over all network connections.");
    if (is(cfg, null, /^network\/[^/]+\/upload$/))
        return tr("Amount of data currently being sent over all network connections.");
    return "";
}

// texts of NvidiaKeys.throttleBits + idle/none, keyed by the English name
function throttleNow() {
    return [
        ["Power limit", tr("The card has reached its power limit – normal under load.")],
        ["Temperature target", tr("The card holds its target temperature and clocks a little lower to do so. More airflow in the case helps.")],
        ["Overheating!", tr("The card is too hot and slows down heavily. Check the cooling: dust, fans, case ventilation.")],
        ["Hardware slowdown", tr("The hardware is slowing down – usually due to overheating or a power supply problem.")],
        ["Power supply slowdown", tr("The power supply reports a problem – check the PSU and power cables.")],
        ["Clock locked", tr("The clock has been limited by a program or a setting.")],
        ["Synced to other GPU", tr("The clock is synced to other graphics cards (only common in data centres).")],
        ["Display clock", tr("Limited by the display output clock.")],
        ["Idle", tr("Nothing to do – the card clocks down to save power.")],
        ["None", tr("The card runs freely, without throttling.")]
    ];
}

// text: the (already translated) value text, e.g. "Power limit, Temperature target"
function now(cfg, text, value, translate) {
    _tr = translate || null;
    if (!cfg) return "";
    if (is(cfg, "clocks_event_reasons.active") && text) {
        var map = {};
        throttleNow().forEach(function (e) { map[tr(e[0])] = e[1]; });
        return text.split(", ").map(function (n) { return map[n] || ""; })
                   .filter(function (s) { return s; }).join("\n");
    }
    if (is(cfg, "pstate") && !isNaN(value)) {
        if (value <= 0) return tr("Full performance.");
        if (value <= 2) return tr("High performance – typical under load or for compute tasks.");
        if (value <= 7) return tr("Medium level.");
        return tr("Power saving – the card has little to do right now.");
    }
    return "";
}
