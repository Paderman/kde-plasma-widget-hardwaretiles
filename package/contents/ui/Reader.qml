// SPDX-FileCopyrightText: 2026 Paderman
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import org.kde.ksysguard.sensors as Sensors
import org.kde.plasma.plasma5support as P5Support
import "NvidiaKeys.js" as NK

// Reads ONE value from any supported source:
//   "sensor"  – ksystemstats sensor id
//   "command" – shell command printing a number
//   "nvidia"  – a field of the shared NvidiaProvider
//   "pcie"    – PCIe link of the graphics card from sysfs (key = PCI address, empty = auto)
//   "igpu"    – Intel graphics in the processor from sysfs (card = gpuAddr; key = "load" | "clock")
//               or from the per-program statistics in /proc (key = "render" | "video" | "copy" |
//               "enhance" | "memory")
Item {
    id: reader
    visible: false

    property bool enabled_: true
    property string source: "sensor"
    property string sensorId: ""
    property string command: ""
    property string key: ""
    property string unit: ""
    property int interval: 1500
    property var nvidia: null
    property int gpuIndex: 0          // nvidia-smi index of the card (-1 = card not found)
    property string gpuAddr: ""       // PCI address of the card (source "igpu")

    readonly property bool isSensor: source !== "command" && source !== "nvidia" && source !== "pcie" && source !== "igpu"
    readonly property bool isIgpu: source === "igpu"
    readonly property bool igpuClock: isIgpu && key === "clock"
    readonly property bool igpuMemory: isIgpu && key === "memory"
    // values from the per-program statistics (engine loads, memory)
    readonly property bool igpuFromClients: isIgpu && key !== "load" && key !== "clock"
    // tooltip: which programs use the graphics right now (igpu tiles only)
    readonly property string clientsText: {
        if (!isIgpu) return "";
        const l = [];
        if (igc.active.length) l.push(i18n("In use by: %1", igc.active.join(", ")));
        if (igc.idle.length) l.push(i18n("Opened, but idle: %1", igc.idle.join(", ")));
        return l.join("\n");
    }
    readonly property bool isPcie: source === "pcie"
    readonly property bool isCommand: source === "command"
    readonly property bool isNvidia: source === "nvidia"
    readonly property var nvMeta: NK.meta(key)

    // ---------------------------------------------------------------- output
    property real cmdValue: NaN
    property bool cmdOk: false

    readonly property var nvDecoded: !isNvidia || !nvidia || gpuIndex < 0 ? ({ value: NaN, text: "" })
        : nvMeta.nvml ? ({ value: nvidia.fanRpm(gpuIndex, fanNo), text: "" })
        : nvidia.hasGpu(gpuIndex) ? nvidia.decoded(key, gpuIndex) : ({ value: NaN, text: "" })

    // ---- fans of an NVIDIA card (fan.speed, fan.rpm, fan.rpm.N)
    readonly property int fanNo: isNvidia ? NK.fanNo(key) : -1
    readonly property var fanList: fanNo >= 0 && nvidia && gpuIndex >= 0 ? nvidia.fanList(gpuIndex) : []
    // fans that should turn but stand still – nvidia-smi cannot see that
    readonly property var stuckFans: fanNo >= 0 && nvidia && gpuIndex >= 0 ? nvidia.stuckFans(gpuIndex, fanNo) : []
    readonly property string stuckText: !stuckFans.length ? ""
        // xgettext:no-javascript-format
        : fanList.length === 1 ? i18n("The fan is not turning, although the card wants %1 %.", stuckFans[0].target)
        // xgettext:no-javascript-format
        : stuckFans.length === 1 ? i18n("Fan %1 is not turning, although the card wants %2 %.", stuckFans[0].no, stuckFans[0].target)
        : i18n("Fans %1 are not turning, although the card wants them to.", stuckFans.map(f => f.no).join(", "))
    // fans that turn, but clearly slower than another fan of the card at the same target
    readonly property var slowFans: fanNo >= 0 && nvidia && gpuIndex >= 0 && !stuckFans.length ? nvidia.slowFans(gpuIndex, fanNo) : []
    function rpmText(v) { return Math.round(v).toLocaleString(Qt.locale(), "f", 0) + " " + i18n("RPM"); }
    readonly property string slowText: !slowFans.length ? ""
        : i18n("Fan %1 runs much slower than fan %2 (%3 instead of %4).", slowFans[0].fan.no, slowFans[0].ref.no,
               rpmText(slowFans[0].fan.rpm), rpmText(slowFans[0].ref.rpm))
    // what is wrong with the fans (shown under the value, used for notifications)
    readonly property string fanText: stuckText || slowText
    // tooltip: every fan with its measured speed
    readonly property string fansText: {
        const l = fanList.filter(f => f.rpm >= 0 && (fanNo <= 0 || f.no === fanNo));
        if (!l.length || (fanNo > 0 && !nvMeta.nvml)) return "";
        return l.map(f => i18n("Fan %1: %2", f.no, rpmText(f.rpm) + (f.pct >= 0 ? " (" + f.pct + " %)" : ""))).join("\n");
    }

    readonly property real value: !enabled_ ? NaN
        : isPcie ? (pcie.ok ? pcie.curWidth : NaN)
        : isIgpu ? (igpuFromClients ? igc.value : igpu.value)
        : isCommand ? (cmdOk ? cmdValue : NaN)
        : isNvidia ? nvDecoded.value
        : (sensor.status === Sensors.Sensor.Ready && !noGpuTemp ? Number(sensor.value) : NaN)
    readonly property bool valid: !isNaN(value)
    // ksystemstats reports 0 °C for graphics chips without a temperature sensor
    // (e.g. Intel graphics built into the processor) – show "–" instead of 0 °C
    readonly property bool noGpuTemp: /^gpu\/[^\/]+\/temperature$/.test(sensorId) && Number(sensor.value) === 0

    readonly property string name: isPcie ? (pcie.ok ? (pcie.gpuName ? pcie.gpuName + (pcie.gpuInfo ? " (" + pcie.gpuInfo + ")" : "") + "\n" : "")
                                                      + i18n("PCIe device %1 on slot port %2", pcie.device, pcie.port)
                                                    : i18n("PCIe link"))
        : isIgpu ? (igpuClock ? i18n("Current clock of the graphics built into the processor (from the kernel driver)")
                  : igpuMemory ? i18n("Main memory used by programs on the graphics built into the processor")
                  : key === "render" ? i18n("3D and compute unit of the graphics built into the processor")
                  : key === "video" ? i18n("Video unit (encoding/decoding) of the graphics built into the processor")
                  : igpuFromClients ? i18n("Unit “%1” of the graphics built into the processor", key)
                  : i18n("Load of the graphics built into the processor (from the kernel driver)"))
        : isCommand ? commandName
        : isNvidia ? i18n(nvMeta.label)
        : (sensor.name || sensorId)
    // readable description of a shell command source (tooltip, notifications)
    readonly property string commandName: {
        const m = command.match(/\/run\/gddr6\/vram(?:-([0-9a-fA-F:.]+))?/);
        if (m) return i18n("Memory temperature (VRAM), measured by the gddr6 service")
                      + (m[1] ? "\n" + i18n("Graphics card PCI %1", m[1].replace(/^0000:/, "")) : "");
        const p = command.match(/\/run\/sensordeck-power\/([a-z0-9-]+)/);
        if (p) return (p[1] === "igpu" ? i18n("Power draw of the graphics built into the processor")
                     : p[1] === "cpu-cores" ? i18n("Power draw of the processor cores")
                     : p[1] === "ram" ? i18n("Power draw of the memory")
                     : i18n("Power draw of the whole processor"))
                      + "\n" + i18n("measured by the processor, published by the Sensor Deck power service");
        return i18n("Shell command: %1", command.length > 60 ? command.slice(0, 57) + "…" : command);
    }
    readonly property string shortName: isPcie ? i18n("PCIe") : isIgpu ? (igpuClock ? i18n("GPU clock") : igpuMemory ? i18n("Graphics memory") : key === "render" ? i18n("3D load") : key === "video" ? i18n("Video load") : i18n("GPU load")) : isCommand ? "" : isNvidia ? i18n(nvMeta.label) : (sensor.shortName || sensor.name || "")

    // maximum reported by the source itself (0 = unknown)
    readonly property real sourceMax: isPcie ? pcie.possibleWidth
        : isIgpu ? (igpuClock ? igpu.max : igpuMemory ? 0 : 100)
        : isSensor && sensor.maximum > 0 ? sensor.maximum
        : isNvidia && nvMeta.max ? nvMeta.max : 0
    // key of an nvidia field that is the natural maximum (e.g. memory.total)
    readonly property string nvMaxKey: isNvidia && nvMeta.maxKey ? nvMeta.maxKey : ""

    readonly property string effUnit: isCommand ? unit : isNvidia ? (nvMeta.nvml ? i18n(nvMeta.unit) : (nvMeta.unit || "")) : isIgpu ? (igpuClock ? "MHz" : igpuMemory ? "MiB" : "%") : ""

    // unit text of a ksystemstats value, taken from its formatted string ("52 °C" -> "°C")
    readonly property string sensorUnit: {
        const m = (sensor.formattedValue || "").match(/^\s*[-+]?[\d.,\u00a0\u202f ]*\d\s*(.*)$/);
        return m ? m[1] : "";
    }

    // format any number in this reader's unit (value, maximum, thresholds)
    function format(v) {
        if (isNaN(v)) return "–";
        let u = isSensor ? sensorUnit : effUnit;
        // fan speeds: "1,553.0 U/min" -> "1,553 U/min"
        if (isSensor && /^(U\/min|RPM|rpm)$/.test(u)) return Math.round(v).toLocaleString(Qt.locale(), "f", 0) + " " + u;
        if (isSensor && v === value && sensor.formattedValue) return sensor.formattedValue;
        if ((isNvidia && nvMeta.mib || igpuMemory) && Math.abs(v) >= 1024) { v = v / 1024; u = "GiB"; }
        const dec = (Number.isInteger(v) || Math.abs(v) >= 100) ? 0 : 1;
        return v.toLocaleString(Qt.locale(), "f", dec) + (u ? " " + u : "");
    }

    readonly property string formatted: {
        if (!valid) return "–";
        if (isPcie) return pcie.text;
        if (isNvidia && nvDecoded.text) return nvDecoded.text;
        return format(value);
    }
    // texts like "P2" or "Power-Limit" are shown as-is
    readonly property bool isText: isPcie || (isNvidia && nvDecoded.text !== "")
    // extra line under the value (e.g. PCIe: what card and slot can do)
    readonly property string detail: isPcie ? pcie.detail : fanText
    readonly property bool integrated: isPcie && pcie.integrated
    // device name shown above the value (PCIe: graphics card)
    readonly property string subtitle: isPcie ? pcie.gpuName : ""
    readonly property string subtitleInfo: isPcie ? pcie.gpuInfo : ""
    // -1 = none; otherwise forces at least this level (PCIe: missing lanes -> 1)
    readonly property int forcedLevel: isPcie && pcie.ok && pcie.curWidth > 0 && pcie.curWidth < pcie.possibleWidth ? 1
                                     : stuckFans.length ? 2 : slowFans.length ? 1 : -1

    // ---------------------------------------------------------- ksystemstats
    Sensors.Sensor {
        id: sensor
        sensorId: reader.enabled_ && reader.isSensor ? reader.sensorId : ""
        updateRateLimit: reader.interval
    }
    // ------------------------------------------------------------ PCIe sysfs
    QtObject {
        id: pcie
        property bool ok: false
        property string device: ""
        property string port: ""
        property real curSpeed: 0
        property int curWidth: 0
        property real cardSpeed: 0
        property int cardWidth: 0
        property real slotSpeed: 0
        property int slotWidth: 0
        property string gpuName: ""     // "NVIDIA GeForce RTX 3080"
        property string gpuInfo: ""     // "ZOTAC · GA102"

        // "Advanced Micro Devices, Inc. [AMD/ATI]" -> "AMD", "NVIDIA Corporation" -> "NVIDIA"
        function shortVendor(v) {
            const b = v.match(/\[([^\]]+)\]/);
            if (b) return b[1].split("/")[0];
            return v.replace(/,? (Corporation|Corp\.?|Inc\.?|Ltd\.?|Co\.?|Technology|International|Group).*$/i, "")
                    .split(" ")[0];
        }
        function setNames(vendor, device, svendor) {
            const sv = vendor ? shortVendor(vendor) : "";
            const m = device.match(/^(.*?)\s*\[(.+)\]\s*$/);
            const model = m ? m[2] : device;
            const chip = m ? m[1] : "";
            gpuName = model ? ((sv && model.indexOf(sv) !== 0 ? sv + " " : "") + model) : "";
            const partner = svendor ? shortVendor(svendor) : "";
            const info = [];
            if (partner && partner !== sv) info.push(partner);
            if (chip) info.push(chip);
            gpuInfo = info.join(" · ");
        }

        function gen(gts) {
            return gts >= 64 ? 6 : gts >= 32 ? 5 : gts >= 16 ? 4 : gts >= 8 ? 3 : gts >= 5 ? 2 : gts > 0 ? 1 : 0;
        }
        function linkText(g, w) { return i18n("Gen %1 ×%2", g, w); }

        readonly property int curGen: gen(curSpeed)
        readonly property int cardGen: gen(cardSpeed)
        readonly property int slotGen: gen(slotSpeed)
        // what this card can reach in this slot
        readonly property int possibleGen: slotGen > 0 ? Math.min(cardGen, slotGen) : cardGen
        readonly property int possibleWidth: slotWidth > 0 ? Math.min(cardWidth, slotWidth) : cardWidth

        // power saving: "Gen 1 · max 3 ×8" – shows at a glance that the card only idles down
        // graphics built into the processor: sits directly on the root complex,
        // has no PCIe slot and therefore no link to report
        readonly property bool integrated: ok && port !== "" && port === device
        readonly property string text: !ok ? "–" : integrated ? i18n("Built into CPU") : curWidth === 0 ? i18n("No link")
            : (curGen > 0 && curGen < possibleGen) ? i18n("Gen %1 · max %2 ×%3", curGen, possibleGen, curWidth)
            : linkText(curGen, curWidth)
        readonly property string detail: {
            if (ok && integrated) return i18n("Graphics built into the processor – uses the main memory, no PCIe slot");
            if (!ok || curWidth === 0) return "";
            const parts = [];
            if (curWidth < possibleWidth)
                parts.push(i18n("Only ×%1 of ×%2 possible lanes – check contact/slot", curWidth, possibleWidth));
            else if (curGen < possibleGen)
                parts.push(i18n("Max. %1 · currently power saving", linkText(possibleGen, possibleWidth)));
            else
                parts.push(i18n("Maximum for this slot"));
            parts.push(i18n("Card %1 · slot %2", linkText(cardGen, cardWidth), linkText(slotGen, slotWidth)));
            return parts.join("\n");
        }
    }
    P5Support.DataSource {
        id: pcieExec
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            const lines = String(data["stdout"] || "").trim().split("\n");
            const f = (lines[0] || "").trim().split(/\s+/);
            const names = {};
            lines.slice(1).forEach(l => {
                const m = l.match(/^(\w+):\s*(.*)$/);
                if (m) names[m[1]] = m[2].trim();
            });
            pcie.setNames(names.Vendor || "", names.Device || "", names.SVendor || "");
            if (data["exit code"] === 0 && f.length >= 8) {
                pcie.device = f[0].replace(/^0000:/, "");
                pcie.curSpeed = parseFloat(f[1]) || 0;
                pcie.curWidth = parseInt(f[2]) || 0;
                pcie.cardSpeed = parseFloat(f[3]) || 0;
                pcie.cardWidth = parseInt(f[4]) || 0;
                pcie.port = f[5].replace(/^0000:/, "");
                pcie.slotSpeed = parseFloat(f[6]) || 0;
                pcie.slotWidth = parseInt(f[7]) || 0;
                pcie.ok = true;
            } else {
                pcie.ok = false;
            }
            disconnectSource(source);
        }
    }
    Timer {
        running: reader.enabled_ && reader.isPcie
        // link width never changes at runtime, the generation does (power saving)
        interval: Math.max(reader.interval, 3000)
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            const script = Qt.resolvedUrl("../code/pcie-info.sh").toString().replace(/^file:\/\//, "");
            // only a real PCI address (e.g. "02:00.0" or "0000:02:00.0"), otherwise auto-detect
            const k = (reader.key || "").trim();
            const addr = /^([0-9a-fA-F]{4}:)?[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-7]$/.test(k) ? k : "";
            pcieExec.connectSource("sh '" + script + "' " + addr);
        }
    }

    // ------------------------------------------------- Intel graphics (sysfs)
    // ksystemstats reports load and clock of Intel graphics in the processor as a
    // constant 0, the kernel driver knows them: the clock directly, the load from
    // how much of the time the graphics was not in its power-saving sleep
    QtObject {
        id: igpu
        property real value: NaN
        property real max: 0
        property real prevIdle: -1
        property real prevTime: 0
    }
    P5Support.DataSource {
        id: igpuExec
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source);
            const f = String(data["stdout"] || "").trim().split(/\s+/).map(Number);
            const now = Date.now();
            if (f.length < 3 || f.some(isNaN)) { igpu.value = NaN; return; }
            const idle = f[0], act = f[1], max = f[2];
            if (max > 0) igpu.max = max;
            if (reader.igpuClock) {
                igpu.value = act >= 0 ? act : NaN;
            } else if (idle >= 0) {
                const dt = now - igpu.prevTime;
                if (igpu.prevIdle >= 0 && dt > 200 && idle >= igpu.prevIdle)
                    igpu.value = Math.round(Math.max(0, Math.min(100, 100 - 100 * (idle - igpu.prevIdle) / dt)));
                igpu.prevIdle = idle;
                igpu.prevTime = now;
            } else {
                igpu.value = NaN;
            }
        }
    }
    Timer {
        running: reader.enabled_ && reader.isIgpu && !reader.igpuFromClients && reader.gpuAddr !== ""
        interval: reader.interval
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            const script = Qt.resolvedUrl("../code/igpu-info.sh").toString().replace(/^file:\/\//, "");
            const a = reader.gpuAddr.trim();
            if (!/^([0-9a-fA-F]{4}:)?[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-7]$/.test(a)) return;
            igpuExec.connectSource("sh '" + script + "' " + a);
        }
    }

    // per-program statistics (/proc/<pid>/fdinfo): busy time per engine and
    // memory of every program that has the graphics open – programs of this
    // user only. The busy time is a counter, the load is its growth per second.
    QtObject {
        id: igc
        property real value: NaN
        property var prev: ({})          // client id -> { engine: ns | [cycles, total] }
        property real prevTime: 0
        property var active: []
        property var idle: []
        // xe names its engines by class
        readonly property var xeNames: ({ rcs: "render", bcs: "copy", vcs: "video", vecs: "video-enhance", ccs: "compute" })
    }
    P5Support.DataSource {
        id: igcExec
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source);
            if (data["exit code"] !== 0) { igc.value = NaN; return; }
            const now = Date.now(), dt = now - igc.prevTime;
            const cur = {}, mem = {}, prog = {};
            String(data["stdout"] || "").split("\n").forEach(line => {
                const f = line.trim().split(/\s+/);
                const id = f[1];
                if (f[0] === "N" && f.length >= 4) (cur[id] = cur[id] || {})[f[2]] = Number(f[3]);
                else if (f[0] === "X" && f.length >= 5) (cur[id] = cur[id] || {})[igc.xeNames[f[2]] || f[2]] = [Number(f[3]), Number(f[4])];
                else if (f[0] === "M" && f.length >= 3) mem[id] = Number(f[2]);
                else if (f[0] === "P" && f.length >= 4) prog[id] = f.slice(3).join(" ");
            });
            // load per engine, summed over all programs; which programs were busy
            const want = reader.key === "enhance" ? "video-enhance" : reader.key;
            const busyProg = {};
            let load = 0, have = igc.prevTime > 0 && dt > 200;
            for (const id in cur) {
                const p = igc.prev[id];
                if (!p) continue;
                for (const e in cur[id]) {
                    const c = cur[id][e], o = p[e];
                    if (o === undefined) continue;
                    let part = 0;
                    if (Array.isArray(c)) { const dtot = c[1] - o[1]; part = dtot > 0 ? 100 * Math.max(0, c[0] - o[0]) / dtot : 0; }
                    else part = 100 * Math.max(0, c - o) / (dt * 1e6);
                    if (part > 0.5) busyProg[id] = true;
                    if (e === want) load += part;
                }
            }
            let total = 0;
            for (const id in mem) total += mem[id];
            if (reader.igpuMemory) igc.value = total / 1048576;
            else if (reader.igpuFromClients) igc.value = have ? Math.round(Math.min(100, load)) : NaN;
            // program names for the tooltip: busy or holding memory = in use
            const act = {}, idl = {};
            for (const id in prog) {
                if (busyProg[id] || mem[id] > 0) act[prog[id]] = true;
                else idl[prog[id]] = true;
            }
            igc.active = Object.keys(act).sort();
            igc.idle = Object.keys(idl).filter(n => !act[n]).sort();
            igc.prev = cur;
            igc.prevTime = now;
        }
    }
    Timer {
        running: reader.enabled_ && reader.isIgpu && !reader.igpuClock && reader.gpuAddr !== ""
        // walking through all programs costs more than one file – every 3 s is enough
        interval: Math.max(reader.interval, 3000)
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            const script = Qt.resolvedUrl("../code/igpu-clients.sh").toString().replace(/^file:\/\//, "");
            const a = reader.gpuAddr.trim();
            if (!/^([0-9a-fA-F]{4}:)?[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-7]$/.test(a)) return;
            igcExec.connectSource("sh '" + script + "' " + a);
        }
    }

    // --------------------------------------------------------- shell command
    P5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            const out = String(data["stdout"] || "").trim();
            const m = out.match(/[-+]?\d+(?:[.,]\d+)?/);
            if (data["exit code"] === 0 && m) {
                reader.cmdValue = parseFloat(m[0].replace(",", "."));
                reader.cmdOk = true;
            } else {
                reader.cmdOk = false;
            }
            disconnectSource(source);
        }
    }
    Timer {
        running: reader.enabled_ && reader.isCommand && reader.command !== ""
        interval: reader.interval
        repeat: true
        triggeredOnStart: true
        onTriggered: exec.connectSource(reader.command)
    }
}
