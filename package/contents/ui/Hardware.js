.pragma library
.import "Defaults.js" as Defaults

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

// ---------------------------------------------------------------- naming

// "Advanced Micro Devices, Inc. [AMD/ATI]" -> "AMD", "NVIDIA Corporation" -> "NVIDIA"
function shortVendor(v) {
    v = v || "";
    var b = v.match(/\[([^\]]+)\]/);
    if (b) return b[1].split("/")[0];
    return v.replace(/,? (Corporation|Corp\.?|Inc\.?|Ltd\.?|Co\.?|Technology|International|Group|Limited).*$/i, "")
            .split(" ")[0];
}

// -> {name: "NVIDIA GeForce RTX 3080", info: "ZOTAC · GA102"}
function gpuNames(vendor, device, svendor) {
    var sv = vendor ? shortVendor(vendor) : "";
    var m = (device || "").match(/^(.*?)\s*\[(.+)\]\s*$/);
    var model = m ? m[2] : (device || "");
    var chip = m ? m[1] : "";
    var name = model ? ((sv && model.indexOf(sv) !== 0 ? sv + " " : "") + model) : "";
    var partner = svendor ? shortVendor(svendor) : "";
    var info = [];
    if (partner && partner !== sv) info.push(partner);
    if (chip) info.push(chip);
    return { name: name, info: info.join(" · ") };
}

// lm-sensors chip suffix for a PCI address: "0000:03:00.0" -> "0300"
function lmPci(addr) {
    var m = (addr || "").match(/([0-9a-f]{2}):([0-9a-f]{2})\.([0-7])$/i);
    if (!m) return "";
    var bus = parseInt(m[1], 16), dev = parseInt(m[2], 16), fn = parseInt(m[3], 10);
    var hex = function (n) { return ("0" + n.toString(16)).slice(-2); };
    return hex(bus) + hex((dev << 3) | fn);
}

var vendorColors = { nvidia: "#76b900", amd: "#ed1c24", intel: "#0071c5", other: "#8b7bff" };

// ---------------------------------------------------------------- discovery

var supportedDrivers = ["nvidia", "amdgpu", "radeon", "i915", "xe", "nouveau"];

function parse(out) {
    var hw = { gpus: [], nvmes: [], cpuCores: [], gddr6: false, power: false, lmTool: true, pm: "", pmPackage: "", distro: "", chips: {} };
    var parts = String(out || "").split(/\nSENSORS\n?/);
    var nvFans = {}, gpuCaps = {};
    parts[0].split("\n").forEach(function (line) {
        var f = line.split("\t");
        if (f[0] === "GPU" && f.length >= 9) {
            var vid = f[2].toLowerCase();
            var vendor = vid === "0x10de" ? "nvidia" : (vid === "0x1002" ? "amd" : (vid === "0x8086" ? "intel" : "other"));
            var n = gpuNames(f[6], f[7], f[8]);
            var drv = f[3];
            hw.gpus.push({
                addr: f[1], vendorId: vid, vendor: vendor, driver: drv,
                card: f[4] === "-" ? "" : f[4],
                ksys: f[4] === "-" ? "" : "gpu" + f[4],
                nvIndex: parseInt(f[5]),
                hwmon: (drv === "amdgpu" || drv === "radeon" || drv === "nouveau") ? drv + "-pci-" + lmPci(f[1]) : "",
                // Intel graphics in the processor (on the root bus): no temperature
                // sensor and no own video memory
                integrated: vid === "0x8086" && /^(0000:)?00:/.test(f[1]),
                name: n.name || (f[7] || f[1]), info: n.info,
                supported: supportedDrivers.indexOf(drv) >= 0
            });
        } else if (f[0] === "NVME" && f.length >= 3) {
            hw.nvmes.push({ addr: f[1], model: f[2], chip: "nvme-pci-" + lmPci(f[1]) });
        } else if (f[0] === "GDDR6") {
            hw.gddr6 = f[1] === "1";
        } else if (f[0] === "POWER") {
            hw.power = f[1] === "1";
        } else if (f[0] === "CPUCORE" && f.length >= 4) {
            hw.cpuCores.push({ cpu: parseInt(f[1]), pkg: parseInt(f[2]) || 0, core: parseInt(f[3]) });
        } else if (f[0] === "GPUCAP" && f.length >= 2) {
            var c = {};
            String(f[2] || "").split(",").forEach(function (x) { if (x) c[x] = true; });
            gpuCaps[f[1]] = c;
        } else if (f[0] === "NVFANS" && f.length >= 3) {
            nvFans[parseInt(f[1])] = parseInt(f[2]) || 0;
        } else if (f[0] === "DISTRO") {
            hw.pm = f[1] || ""; hw.pmPackage = f[2] || ""; hw.distro = f[3] || "";
        } else if (f[0] === "LMTOOL") {
            hw.lmTool = f[1] === "1";
        }
    });
    // fans of NVIDIA cards whose measured speed the driver reports
    hw.gpus.forEach(function (g) { g.nvFans = g.nvIndex >= 0 ? (nvFans[g.nvIndex] || 0) : 0; });
    // what the driver reports (null: unknown, older discovery – then nothing is left out)
    hw.gpus.forEach(function (g) { g.caps = gpuCaps[g.addr] || null; });
    if (parts.length > 1) {
        try { hw.chips = JSON.parse(parts[1]) || {}; } catch (e) { hw.chips = {}; }
    }
    // kept for resolve(): tiles made before the CPU mapping existed
    lastChips = hw.chips;
    lastCpuCores = hw.cpuCores;
    return hw;
}

// ---- processor temperatures ----------------------------------------------
// ksystemstats does not list the CPU temperature chips under lmsensors/: their
// values appear as cpu/cpuX/temperature instead (coretemp "Core N" on the threads
// of core N). So "lmsensors/coretemp-isa-0000/temp6" never shows anything.
var cpuTempChip = /^(coretemp|k10temp|zenpower)-/i;
var lastChips = {};
var lastCpuCores = [];
// ksystemstats sensor for one value of a CPU temperature chip, "" = it has none
function cpuTempSensor(chip, label, cores) {
    var m = /^coretemp-isa-([0-9a-f]+)$/i.exec(chip || "");
    var c = /^Core (\d+)$/.exec(label || "");
    if (!m || !c) return "";
    var pkg = parseInt(m[1], 16), core = parseInt(c[1]);
    var threads = (cores || []).filter(function (t) { return t.pkg === pkg && t.core === core; })
                               .map(function (t) { return t.cpu; });
    // older detection output without the topology: thread N is core N on the first package
    if (!threads.length && !(cores || []).length && pkg === 0) threads = [core];
    return threads.length ? "cpu/cpu" + Math.min.apply(null, threads) + "/temperature" : "";
}
// an old tile id like "lmsensors/coretemp-isa-0000/temp6" -> "cpu/cpu4/temperature"
function cpuTempFromLm(id) {
    var m = /^lmsensors\/((?:coretemp|k10temp|zenpower)-[^\/]+)\/(temp\d+)$/i.exec(id || "");
    if (!m) return id;
    var chip = lastChips[m[1]];
    if (!chip) return id;          // detection not done yet: leave it
    var label = Object.keys(chip).filter(function (l) {
        return chip[l] && typeof chip[l] === "object" && (m[2] + "_input") in chip[l];
    })[0];
    // k10temp/zenpower (Tctl, Tccd …) and "Package id": ksystemstats has no own sensor
    return cpuTempSensor(m[1], label, lastCpuCores) || "cpu/all/maximumTemperature";
}

function supportedGpus(hw) {
    return (hw && hw.gpus ? hw.gpus : []).filter(function (g) { return g.supported; });
}

// selected GPU: by address, else the first discrete one
function pickGpu(hw, addr) {
    var list = supportedGpus(hw);
    if (!list.length) return null;
    for (var i = 0; i < list.length; ++i) if (list[i].addr === addr) return list[i];
    for (var j = 0; j < list.length; ++j) if (list[j].driver === "nvidia" || list[j].driver === "amdgpu") return list[j];
    return list[0];
}

// exact match only (for tiles bound to a specific card – no fallback to another GPU)
function gpuByAddr(hw, addr) {
    var list = supportedGpus(hw);
    for (var i = 0; i < list.length; ++i) if (list[i].addr === addr) return list[i];
    return null;
}

// short name for badges / section headers: "NVIDIA GeForce RTX 3080" -> "RTX 3080"
function gpuTag(gpu) {
    if (!gpu) return "";
    var t = (gpu.name || "").replace(/\b(NVIDIA|GeForce|AMD|ATI|Radeon|Intel\(R\)|Intel|Corporation|Graphics Card)\b/gi, "")
                            .replace(/\s+/g, " ").trim();
    return t || gpu.name || gpu.addr;
}

// colour per GPU slot (two cards of the same vendor must still be distinguishable)
var gpuColors = ["#22c3ff", "#ff7eb6", "#ffb547", "#2fe0a0", "#c48bff", "#9be15d"];
var gpuColorsLight = ["#0279b8", "#d0236e", "#b85c00", "#038a5e", "#8a35d9", "#4a8a12"];   // same hues, deeper (light themes)
function gpuColor(slot, light) { return slot >= 0 ? (light ? gpuColorsLight : gpuColors)[slot % gpuColors.length] : "transparent"; }

// does a tile depend on a graphics card (and therefore belongs to one)?
function usesGpu(it) {
    if (!it) return false;
    if (it.gpu) return true;
    if (it.source === "nvidia" || it.source === "pcie" || it.source === "igpu") return true;
    if (it.style === "curve" && it.ySource === "nvidia") return true;
    var keys = ["sensorId", "refSensorId", "ySensorId", "command", "yCommand"];
    for (var i = 0; i < keys.length; ++i) {
        var v = it[keys[i]];
        if (typeof v === "string" && /\{gpu(addr|hwmon)?\}/.test(v)) return true;
    }
    return false;
}

// mainboard sensors from `sensors -j` (or the sysfs fallback of hw-discover.sh):
// named or spinning fans + the most likely case/board temperature.
// Chips that never carry mainboard values are skipped completely; CPU chips only
// for temperatures (their fans – e.g. thinkpad, dell_smm – are wanted).
var skipChip = /^(nvme|amdgpu|radeon|nouveau|nvidia|iwlwifi|mt79|ath1|spd5118|jc42|ee1004|drivetemp|bat|ucsi|hidpp|corsairpsu)/i;
var skipTempChip = /^(coretemp|k10temp|zenpower|acpitz|thinkpad|pch_)/i;
// labels that are clearly not the case/board temperature
var notBoard = /CPU|Core|Package|Tctl|Tdie|Tccd|PECI|VRM|GPU|DIMM|Virtual|Calibration|AUXTIN|PCH|Chipset|SB ?Temp|TSI|SMBUS|Edge|Junction|Mem|Water|Coolant/i;
var boardLabel = /SYSTIN|Motherboard|Mainboard|\bMB\b|MB ?Temp|System|SYS ?Temp|Ambient|Case/i;
// Super-I/O and board drivers: their unlabelled temp1 is usually the board sensor
var superIo = /^(nct|it8|it87|f71|f8000|w83|sch5|gigabyte_wmi|asus|dell_smm)/i;
// older SMSC Super-I/O chips (e.g. smsc47b397 in HP business PCs): temp1 follows
// the processor and temp2 the hot chipset – the coolest unlabelled one is the case
var smscIo = /^smsc47/i;
// voltage of the mainboard battery (coin cell, keeps BIOS settings and clock):
// "Vbat", "VBAT", "3VBAT", "CMOS Battery" … – not "3VSB" (standby supply)
var batteryLabel = /(^|[^a-z])(vbat|vbatt|cmos)|batter/i;
// thresholds for a 3 V coin cell (CR2032): new about 3.0–3.3 V
var BATTERY_WARN = 2.9, BATTERY_CRIT = 2.7;

function boardSensors(hw) {
    var fans = [], temps = [], battery = [];
    var chips = hw && hw.chips ? hw.chips : {};
    Object.keys(chips).forEach(function (chip) {
        if (skipChip.test(chip)) return;
        var c = chips[chip];
        Object.keys(c).forEach(function (label) {
            var feat = c[label];
            if (typeof feat !== "object" || feat === null) return;
            Object.keys(feat).forEach(function (k) {
                var m = k.match(/^(fan|temp|in)(\d+)_input$/);
                if (!m) return;
                var v = feat[k];
                var id = "lmsensors/" + chip + "/" + m[1] + m[2];
                // a missing or empty cell reads near 0 V – still shown, then it warns
                if (m[1] === "in") {
                    if (batteryLabel.test(label) && v < 4.5 && !battery.length) battery.push({ id: id, label: label });
                    return;
                }
                // a fan with its own name (sensors.conf label) is always taken – it may just
                // be standing still at the moment (fan stop); unnamed ones only if they spin.
                // A pump never stops: one at 0 rpm is not connected, so pumps only if they spin.
                var named = !/^fan\d+$/.test(label);
                var pump = /pump/i.test(label);
                if (m[1] === "fan" && (v > 0 || (named && !pump)))
                    fans.push({ id: id, label: named ? Defaults.stripSensorNo(label) : tr("Fan %1", m[2]) });
                if (m[1] === "temp" && !skipTempChip.test(chip) && v > 10 && v < 80 && !notBoard.test(label)) {
                    var score = boardLabel.test(label) ? 3
                              : (superIo.test(chip) && /^temp1$/.test(label)) ? 1
                              : (smscIo.test(chip) && /^temp\d+$/.test(label)) ? 0.5 : 0;
                    if (score > 0) temps.push({ id: id, label: label, score: score, value: v });
                }
            });
        });
    });
    // best match first; equal scores keep the sensor order – only among the
    // SMSC guesses the coolest wins
    temps.sort(function (x, y) { return y.score - x.score || (x.score === 0.5 ? x.value - y.value : 0); });
    return { fans: fans.slice(0, 4), temps: temps.slice(0, 1), battery: battery };
}

// What the setup wizard offers when no mainboard fans were found:
//   "ok"      fans found – nothing to do
//   "install" lm-sensors missing, Hardware Tiles can install it (apt/dnf/zypper/pacman)
//   "detect"  lm-sensors installed, Hardware Tiles can run sensors-detect
//   "manual"  image-based or unknown system – only instructions
function sensorSetupState(hw) {
    if (!hw) return "ok";
    if (boardSensors(hw).fans.length) return "ok";
    var pmKnown = ["apt", "dnf", "zypper", "pacman"].indexOf(hw.pm) >= 0;
    if (!hw.lmTool) return pmKnown ? "install" : "manual";
    return hw.pm === "immutable" ? "manual" : "detect";
}

function sensorSetupText(hw, translate) {
    if (translate) _tr = translate;
    switch (sensorSetupState(hw)) {
    case "install":
        return tr("No fan sensors were found. Hardware Tiles can set up the sensor support for you: it installs the package “%1” and detects the sensor chip of your mainboard. You will be asked for your password.", hw.pmPackage);
    case "detect":
        return tr("No fan sensors were found. Hardware Tiles can detect the sensor chip of your mainboard and load its driver. You will be asked for your password.");
    case "manual":
        return hw.pm === "immutable"
            ? tr("No fan sensors were found. On this system, programs are installed differently (image-based system): add “lm-sensors”, run “sudo sensors-detect” once and restart – more in the README under “Mainboard sensors”.")
            : tr("No fan sensors were found. Install “lm-sensors” with your software center, run “sudo sensors-detect” once and restart – more in the README under “Mainboard sensors”.");
    }
    return "";
}

// ---------------------------------------------------------------- tile sets

// what the setup wizard offers
var categories = [
    { key: "gpuDetails", label: tr("Graphics card – details"), hint: tr("Fans & fan curve, clocks, throttling, video encoding …"), icon: "preferences-system-performance", def: true },
    { key: "cpu",        label: tr("Processor"),            hint: tr("Temperature and usage"), icon: "cpu", def: true },
    { key: "ram",        label: tr("Memory"),      hint: tr("Used and total, swap space"), icon: "memory", def: true },
    { key: "storage",    label: tr("SSDs & drives"),   hint: tr("NVMe temperatures, disk space"), icon: "drive-harddisk", def: true },
    { key: "board",      label: tr("Mainboard & fans"),   hint: tr("Case temperature, fan speeds, mainboard battery"), icon: "preferences-system-power-management", def: false },
    { key: "network",    label: tr("Network"),             hint: tr("Download and upload"), icon: "applications-internet", def: false },
    // only offered with several graphics cards
    { key: "compare",    label: tr("GPU comparison"),        hint: tr("Temperature, load, power and VRAM of all cards in shared tiles"), icon: "view-split-left-right", def: true, multiOnly: true }
];

function defaultOptions() {
    var o = {};
    categories.forEach(function (c) { o[c.key] = c.def; });
    return o;
}

var VRAM_CMD = "cat /run/gddr6/vram-{gpuaddr} 2>/dev/null || cat /run/gddr6/vram";
// power service (power-service/): processor and built-in graphics, in W
var CPU_POWER_CMD = "cat /run/hardwaretiles-power/cpu";
var IGPU_POWER_CMD = "cat /run/hardwaretiles-power/igpu";
// further cards: no fallback, /run/gddr6/vram is always the first GPU
var VRAM_CMD_STRICT = "cat /run/gddr6/vram-{gpuaddr}";

// Tiles that show one value for every graphics card. All NVIDIA -> nvidia-smi
// fields (exact, one query), mixed vendors -> ksystemstats (works for all).
function compareTiles(gpus) {
    var nv = gpus.every(function (g) { return g.vendor === "nvidia" && g.nvIndex >= 0; });
    var t = nv ? [
        { label: tr("GPU temperature"), source: "nvidia", key: "temperature.gpu", style: "ring", max: 100, warn: 75, crit: 85 },
        { label: tr("GPU load"), source: "nvidia", key: "utilization.gpu", style: "graph", max: 100, wide: true },
        { label: tr("GPU power"), source: "nvidia", key: "power.draw", style: "bar" },
        { label: tr("VRAM used"), source: "nvidia", key: "memory.used", style: "bar" }
    ] : [
        { label: tr("GPU temperature"), sensorId: "gpu/{gpu}/temperature", style: "ring", max: 100, warn: 80, crit: 95 },
        { label: tr("GPU load"), sensorId: "gpu/{gpu}/usage", style: "graph", max: 100, wide: true },
        { label: tr("GPU power"), sensorId: "gpu/{gpu}/power", style: "bar" },
        { label: tr("VRAM used"), sensorId: "gpu/{gpu}/usedVram", refSensorId: "gpu/{gpu}/totalVram", style: "bar" }
    ];
    // the per-card tiles already notify – no duplicates
    return t.map(function (o) { o.compare = true; o.notify = false; return Defaults.normalize(o, 0); });
}

// voltage of the mainboard battery: warns when it drops
function batteryTile(sensorId) {
    return { label: tr("Mainboard battery"), sensorId: sensorId, style: "value",
             lowWarn: BATTERY_WARN, lowCrit: BATTERY_CRIT };
}

// supply voltages of the power supply: nominal value from the label ("+12V", "3VSB" …)
function nominalVoltage(label) {
    var l = String(label || "").replace(/\s+/g, "");
    if (/^-/.test(l)) return 0;                       // -12 V, -5 V: rare, negative
    if (/(^|\+)12(\.0)?V|^V12|^12VSB/i.test(l)) return 12;
    if (/(^|\+)3\.3V|^3\.?3?VSB|^VSB3|^V3\.?3|^3VCC|^AVCC3|^VCC3V/i.test(l)) return 3.3;
    if (/(^|\+)5(\.0)?V|^5VSB|^VSB5|^V5|^5VCC/i.test(l)) return 5;
    return 0;
}
function round2(v) { return Math.round(v * 100) / 100; }

// friendly name of a sensor chip for the menus
function chipName(chip) {
    var c = String(chip || "");
    if (/^(nct|it8|it87|f71|f8000|w83|sch5|smsc47|gigabyte_wmi|asus|asus_ec|asus_wmi|dell_smm|thinkpad)/i.test(c)) return tr("Mainboard");
    if (/^(coretemp|k10temp|zenpower)/i.test(c)) return tr("Processor");
    if (/^nvme/i.test(c)) return tr("SSD");
    if (/^(acpitz|pch_)/i.test(c)) return tr("Chipset / ACPI");
    if (/^(spd5118|jc42|ee1004)/i.test(c)) return tr("Memory module");
    if (/^drivetemp/i.test(c)) return tr("Hard disk");
    if (/^(iwlwifi|mt79|ath1)/i.test(c)) return tr("Wi-Fi");
    if (/^corsairpsu/i.test(c)) return tr("Power supply");
    return c.replace(/-(isa|pci|acpi|virtual|i2c)-.*$/, "");
}

// Every sensor of `sensors -j` that can be added as a tile (template menu),
// grouped: voltages, temperatures, fans. Graphics card chips are left out –
// their values come with the graphics card tiles.
//   -> [{ title, items: [{ text, tile }] }]
function extraSensors(hw, translate) {
    if (translate) _tr = translate;
    var chips = hw && hw.chips ? hw.chips : {};
    var volts = [], temps = [], fans = [];
    var names = Object.keys(chips).filter(function (c) { return !/^(amdgpu|radeon|nouveau|nvidia|i915|xe)/i.test(c); });
    // "(Mainboard)" only helps when sensors come from several chips
    var several = names.length > 1;
    var fmt = function (v, d, u) { return Number(v).toLocaleString(Qt.locale(), "f", d) + " " + u; };
    names.forEach(function (chip) {
        var c = chips[chip], where = chipName(chip);
        // SSDs by their make ("Plextor SSD"), so two drives can be told apart
        var nv = (hw.nvmes || []).filter(function (n) { return n.chip === chip; })[0];
        if (nv) where = Defaults.nvmeLabel(nv.model, _tr).split(" · ")[0];
        Object.keys(c).forEach(function (label) {
            var feat = c[label];
            if (typeof feat !== "object" || feat === null) return;
            Object.keys(feat).forEach(function (k) {
                var m = k.match(/^(fan|temp|in)(\d+)_input$/);
                if (!m) return;
                var v = Number(feat[k]);
                var id = "lmsensors/" + chip + "/" + m[1] + m[2];
                var unnamed = new RegExp("^" + m[1] + "\\d+$").test(label);
                var name = Defaults.stripSensorNo(label);
                var suffix = several && name !== where ? " (" + where + ")" : "";
                if (m[1] === "in") {
                    if (unnamed) return;          // "in5": nobody knows what it is
                    var tile;
                    if (batteryLabel.test(label)) tile = batteryTile(id);
                    else {
                        tile = { label: tr("Voltage %1", name), sensorId: id, style: "value", notify: false };
                        var n = nominalVoltage(label);
                        // ATX: ±5 % allowed. Only when the reading is plausible – some
                        // boards report a line wrongly (e.g. 12 V as 1.0 V)
                        if (n && Math.abs(v - n) <= n * 0.1) {
                            tile.lowWarn = round2(n * 0.95); tile.warn = round2(n * 1.05);
                            tile.lowCrit = round2(n * 0.9);  tile.crit = round2(n * 1.1);
                            tile.notify = true;
                        }
                    }
                    volts.push({ text: name + suffix + " – " + fmt(v, 2, "V"), tile: tile });
                } else if (m[1] === "temp") {
                    if (!(v > -40 && v < 150) || /Calibration/i.test(label)) return;
                    // processor chips: only what ksystemstats really has (the cores)
                    if (cpuTempChip.test(chip)) {
                        id = cpuTempSensor(chip, label, hw.cpuCores);
                        if (!id) return;
                    }
                    temps.push({ text: name + suffix + " – " + fmt(v, 0, "°C"),
                                 tile: { label: several && name !== where ? where + " · " + name : name, sensorId: id, style: "value", notify: false } });
                } else {
                    fans.push({ text: (unnamed ? tr("Fan %1", m[2]) : name) + suffix + " – " + fmt(Math.round(v), 0, tr("RPM")),
                                tile: { label: unnamed ? tr("Fan %1", m[2]) : name, sensorId: id, style: "value" } });
                }
            });
        });
    });
    var groups = [];
    if (volts.length) groups.push({ title: tr("Voltages"), items: volts });
    if (temps.length) groups.push({ title: tr("Temperatures"), items: temps });
    if (fans.length) groups.push({ title: tr("Fans"), items: fans });
    return groups;
}

// copy of a compare tile for one card (first = main card keeps the gddr6 fallback)
function forGpu(it, addr, first) {
    var r = {};
    for (var k in it) r[k] = it[k];
    r.gpu = addr;
    r.id = it.id + "@" + addr;
    if (!first && r.command === VRAM_CMD) r.command = VRAM_CMD_STRICT;
    if (!first && r.yCommand === VRAM_CMD) r.yCommand = VRAM_CMD_STRICT;
    return r;
}

// gpu: one GPU object, or an array of GPUs (multi-GPU layout: one block of
// tiles per card, each bound to its card via "gpu", then the system tiles).
// translate: QML i18n (tile names are created in the user's language)
function build(gpu, opts, hw, translate) {
    _tr = translate || null;
    if (!Array.isArray(gpu)) return buildOne(gpu, opts, hw);
    var gpus = gpu.filter(function (g) { return !!g; });
    if (gpus.length <= 1) return buildOne(gpus[0] || null, opts, hw);
    opts = opts || defaultOptions();
    var all = [];
    gpus.forEach(function (g, i) {
        buildOne(g, { gpuDetails: !!opts.gpuDetails, fansEach: !!opts.fansEach }, hw).forEach(function (t) {
            t.gpu = g.addr;
            if (i > 0 && t.command === VRAM_CMD) t.command = VRAM_CMD_STRICT;
            all.push(t);
        });
    });
    if (opts.compare) all = all.concat(compareTiles(gpus));
    var sysOpts = {};
    for (var k in opts) sysOpts[k] = opts[k];
    sysOpts.gpuDetails = false;
    all = all.concat(buildOne(null, sysOpts, hw));
    return all.map(function (o, i) { o.id = "s" + (i + 1); return Defaults.normalize(o, i); });
}

// Builds the tile list for a GPU (+ optional categories). Sensor ids use the
// tokens {gpu}, {gpuaddr}, {gpuhwmon} – resolved at runtime for the chosen GPU.
function buildOne(gpu, opts, hw) {
    opts = opts || defaultOptions();
    var rings = [], graphs = [], bars = [], values = [], wide = [];
    var nv = gpu && gpu.vendor === "nvidia" && gpu.nvIndex >= 0;
    var amd = gpu && gpu.driver === "amdgpu";

    // ---- graphics card (always)
    if (gpu) {
        if (nv) {
            rings.push({ label: tr("GPU temperature"), source: "nvidia", key: "temperature.gpu", style: "ring", max: 100, warn: 75, crit: 85, showInPanel: true });
            if (hw && hw.gddr6)
                rings.push({ label: tr("VRAM temperature"), source: "command", command: VRAM_CMD, unit: "°C", style: "ring", max: 110, warn: 90, crit: 100, showInPanel: true });
            graphs.push({ label: tr("GPU load"), source: "nvidia", key: "utilization.gpu", style: "graph", max: 100 });
            bars.push({ label: tr("GPU power"), source: "nvidia", key: "power.draw", style: "bar" });
            bars.push({ label: tr("VRAM used"), source: "nvidia", key: "memory.used", style: "bar", notify: false });
        } else if (amd) {
            rings.push({ label: tr("GPU temperature"), sensorId: "gpu/{gpu}/temperature", style: "ring", max: 100, warn: 80, crit: 95, showInPanel: true });
            rings.push({ label: tr("GPU hotspot"), sensorId: "lmsensors/{gpuhwmon}/temp2", style: "ring", max: 110, warn: 95, crit: 105 });
            rings.push({ label: tr("VRAM temperature"), sensorId: "lmsensors/{gpuhwmon}/temp3", style: "ring", max: 110, warn: 90, crit: 100, showInPanel: true });
            graphs.push({ label: tr("GPU load"), sensorId: "gpu/{gpu}/usage", style: "graph", max: 100 });
            bars.push({ label: tr("GPU power"), sensorId: "gpu/{gpu}/power", style: "bar" });
            bars.push({ label: tr("VRAM used"), sensorId: "gpu/{gpu}/usedVram", refSensorId: "gpu/{gpu}/totalVram", style: "bar", notify: false });
        } else if (gpu.integrated) {
            // Intel graphics in the processor: no temperature, no own memory;
            // load and clock come from the kernel driver (source "igpu")
            graphs.push({ label: tr("GPU load"), source: "igpu", key: "load", style: "graph", max: 100 });
            if (hw && hw.power)
                values.push({ label: tr("GPU power"), source: "command", command: IGPU_POWER_CMD, unit: "W", style: "value", notify: false });
        } else {
            // radeon / nouveau: ksystemstats has no temperature for them – their
            // hwmon chip (if the card has a sensor at all) does
            var tempId = gpu.hwmon ? "lmsensors/{gpuhwmon}/temp1" : "gpu/{gpu}/temperature";
            rings.push({ label: tr("GPU temperature"), sensorId: tempId, style: "ring", max: 100, warn: 80, crit: 95, showInPanel: true });
            graphs.push({ label: tr("GPU load"), sensorId: "gpu/{gpu}/usage", style: "graph", max: 100 });
            bars.push({ label: tr("VRAM used"), sensorId: "gpu/{gpu}/usedVram", refSensorId: "gpu/{gpu}/totalVram", style: "bar", notify: false });
        }

        if (opts.gpuDetails) {
            if (nv) {
                rings.push({ label: tr("GPU fan"), source: "nvidia", key: "fan.speed", style: "ring", max: 100, warn: 85 });
                // measured speed; with several fans also one tile per fan (only offered as
                // suggestions in edit mode – opts.fansEach is not a wizard category)
                if (gpu.nvFans > 0)
                    values.push({ label: tr("GPU fan speed"), source: "nvidia", key: "fan.rpm", style: "value" });
                if (opts.fansEach && gpu.nvFans > 1)
                    for (var fn = 1; fn <= Math.min(3, gpu.nvFans); ++fn)
                        values.push({ label: tr("GPU fan %1", fn), source: "nvidia", key: "fan.rpm." + fn, style: "value" });
                wide.push({ label: tr("GPU fan curve"), source: "nvidia", key: "temperature.gpu", style: "curve", min: 30, max: 90,
                            ySource: "nvidia", yKey: "fan.speed", yMax: 100, wide: true });
                bars.push({ label: tr("GPU clock"), source: "nvidia", key: "clocks.gr", style: "bar" });
                bars.push({ label: tr("Memory clock"), source: "nvidia", key: "clocks.mem", style: "bar" });
                bars.push({ label: tr("Video encoding"), source: "nvidia", key: "utilization.encoder", style: "bar", max: 100 });
                bars.push({ label: tr("Video decoding"), source: "nvidia", key: "utilization.decoder", style: "bar", max: 100 });
                values.push({ label: tr("Throttling"), source: "nvidia", key: "clocks_event_reasons.active", style: "value", warn: 1, notify: false });
                values.push({ label: tr("Performance level"), source: "nvidia", key: "pstate", style: "value" });
            } else if (amd) {
                values.push({ label: tr("GPU fan"), sensorId: "lmsensors/{gpuhwmon}/fan1", style: "value" });
                wide.push({ label: tr("GPU fan curve"), sensorId: "gpu/{gpu}/temperature", style: "curve", min: 30, max: 100,
                            ySource: "sensor", ySensorId: "lmsensors/{gpuhwmon}/fan1", yMax: 3500, wide: true });
                bars.push({ label: tr("GPU clock"), sensorId: "gpu/{gpu}/coreFrequency", style: "bar" });
                bars.push({ label: tr("Memory clock"), sensorId: "gpu/{gpu}/memoryFrequency", style: "bar" });
            } else if (gpu.integrated) {
                bars.push({ label: tr("GPU clock"), source: "igpu", key: "clock", style: "bar" });
                bars.push({ label: tr("3D load"), source: "igpu", key: "render", style: "bar", max: 100 });
                bars.push({ label: tr("Video load"), source: "igpu", key: "video", style: "bar", max: 100 });
                values.push({ label: tr("Graphics memory"), source: "igpu", key: "memory", style: "value", notify: false });
            } else {
                // radeon / nouveau: fan from the card's hwmon chip, if it has one. These
                // older cards keep their fan running all the time (no idle fan stop like
                // newer cards) – a stopped fan is critical
                if (gpu.hwmon)
                    values.push({ label: tr("GPU fan"), sensorId: "lmsensors/{gpuhwmon}/fan1", style: "value", lowCrit: 200 });
                bars.push({ label: tr("GPU clock"), sensorId: "gpu/{gpu}/coreFrequency", style: "bar" });
            }
        }
        wide.push({ label: tr("Graphics card · PCIe"), source: "pcie", style: "value", wide: true, notify: false });
    }

    // ---- processor
    if (opts.cpu) {
        rings.push({ label: tr("CPU temperature"), sensorId: "cpu/all/maximumTemperature", style: "ring", max: 100, warn: 80, crit: 90, showInPanel: true });
        if (hw && hw.power)
            values.push({ label: tr("CPU power"), source: "command", command: CPU_POWER_CMD, unit: "W", style: "value", notify: false });
        graphs.push({ label: tr("CPU load"), sensorId: "cpu/all/usage", style: "graph", max: 100, wide: true });
    }
    // ---- memory
    if (opts.ram)
        bars.push({ label: tr("Memory"), sensorId: "memory/physical/used", refSensorId: "memory/physical/total", style: "bar", warn: 85, crit: 95, relThresholds: true, notify: false });
    // ---- storage
    if (opts.storage) {
        (hw && hw.nvmes ? hw.nvmes : []).slice(0, 4).forEach(function (n) {
            bars.push({ label: Defaults.nvmeLabel(n.model, _tr), sensorId: "lmsensors/" + n.chip + "/temp1", style: "bar", max: 90, warn: 60, crit: 70 });
        });
        bars.push({ label: tr("Disk used"), sensorId: "disk/all/usedPercent", style: "bar", max: 100, warn: 90, crit: 97, notify: false });
    }
    // ---- mainboard
    if (opts.board) {
        var b = boardSensors(hw);
        b.temps.forEach(function (t) { values.push({ label: tr("Case temperature"), sensorId: t.id, style: "value", warn: 45, crit: 55 }); });
        b.fans.forEach(function (f) { values.push({ label: f.label, sensorId: f.id, style: "value" }); });
        b.battery.forEach(function (t) { values.push(batteryTile(t.id)); });
    }
    // ---- network
    var net = [];
    if (opts.network) {
        net.push({ label: tr("Download"), sensorId: "network/all/download", style: "graph" });
        net.push({ label: tr("Upload"), sensorId: "network/all/upload", style: "graph" });
    }

    var all = rings.concat(graphs, bars, values, wide, net);
    // leave out graphics card tiles whose value the driver does not report
    // (e.g. Radeon HD 4200 with "radeon": no sensor, no own memory, no load)
    if (gpu && gpu.caps)
        all = all.filter(function (o) { return gpuCapOk(o.sensorId, gpu.caps) && gpuCapOk(o.ySensorId, gpu.caps)
                                               && gpuCapOk(o.refSensorId, gpu.caps); });
    return all.map(function (o, i) { o.id = "s" + (i + 1); return Defaults.normalize(o, i); });
}

// does the card report what this sensor id needs? (caps from GPUCAP)
var gpuCapNeeds = {
    "gpu/{gpu}/temperature": "temp1", "lmsensors/{gpuhwmon}/temp1": "temp1",
    "lmsensors/{gpuhwmon}/temp2": "temp2", "lmsensors/{gpuhwmon}/temp3": "temp3",
    "lmsensors/{gpuhwmon}/fan1": "fan1", "gpu/{gpu}/power": "power",
    "gpu/{gpu}/usage": "busy", "gpu/{gpu}/usedVram": "vram", "gpu/{gpu}/totalVram": "vram",
    "gpu/{gpu}/coreFrequency": "sclk", "gpu/{gpu}/memoryFrequency": "mclk"
};
function gpuCapOk(sensorId, caps) {
    var need = sensorId ? gpuCapNeeds[sensorId] : "";
    return !need || !!caps[need];
}

// ---------------------------------------------------------------- tokens

function resolveString(s, gpu) {
    if (!s || s.indexOf("{") < 0) return s;
    return s.replace(/\{gpu\}/g, gpu && gpu.ksys ? gpu.ksys : "gpu-none")
            .replace(/\{gpuaddr\}/g, gpu ? gpu.addr : "")
            .replace(/\{gpuhwmon\}/g, gpu && gpu.hwmon ? gpu.hwmon : "gpu-none");
}

// concrete copy of a tile for its GPU (keeps id). Adds runtime-only fields:
// gpuAddr, nvIndex (nvidia-smi index, -1 = none), gpuSlot (-1 = no GPU tile), gpuTag
function resolve(it, gpu, slot, tag) {
    var r = {};
    for (var k in it) r[k] = it[k];
    ["sensorId", "refSensorId", "ySensorId", "command", "yCommand"].forEach(function (k) {
        r[k] = resolveString(r[k], gpu);
    });
    ["sensorId", "refSensorId", "ySensorId"].forEach(function (k) { r[k] = cpuTempFromLm(r[k]); });
    if (r.source === "pcie" && !r.key && gpu) r.key = gpu.addr;
    // Intel graphics in the processor: ksystemstats only reports a constant 0 for
    // it – load and clock are read from the kernel driver instead, values it
    // does not have at all (temperature, power, VRAM) show "–"
    if (gpu && gpu.integrated && (!r.source || r.source === "sensor") && gpu.ksys) {
        var m = String(r.sensorId || "").match(/^gpu\/([^\/]+)\/(\w+)$/);
        if (m && m[1] === gpu.ksys) {
            if (m[2] === "usage") { r.source = "igpu"; r.key = "load"; r.sensorId = ""; }
            else if (m[2] === "coreFrequency" || m[2] === "frequency") { r.source = "igpu"; r.key = "clock"; r.sensorId = ""; }
            // power: from the power service, if installed (else "–")
            else if (m[2] === "power") { r.source = "command"; r.command = IGPU_POWER_CMD; r.unit = "W"; r.sensorId = ""; }
            else if (m[2] !== "name" && m[2] !== "totalVram") { r.sensorId = ""; r.refSensorId = ""; }
        }
    }
    // NVIDIA: ksystemstats builds "usage" from the per-process list of nvidia-smi
    // and adds up compute, video encoding and decoding – well above 100 % while
    // encoding. The card's own load comes from nvidia-smi directly.
    if (gpu && !gpu.integrated && gpu.nvIndex >= 0 && (!r.source || r.source === "sensor") && gpu.ksys
            && r.sensorId === "gpu/" + gpu.ksys + "/usage") {
        r.source = "nvidia"; r.key = "utilization.gpu"; r.sensorId = "";
    }
    r.gpuAddr = gpu ? gpu.addr : (it.gpu || "");
    // unknown card: unbound tiles fall back to nvidia-smi index 0 (old behaviour),
    // tiles bound to a card that is missing show no value instead of another card's
    r.nvIndex = gpu ? (gpu.nvIndex >= 0 ? gpu.nvIndex : -1) : (it.gpu ? -1 : 0);
    r.gpuSlot = slot === undefined ? -1 : slot;
    r.gpuTag = tag || "";
    return r;
}

// runtime fields that are never stored in the config
var runtimeKeys = ["gpuAddr", "nvIndex", "gpuSlot", "gpuTag"];
