.pragma library

// SPDX-FileCopyrightText: 2026 Paderman
// SPDX-License-Identifier: GPL-2.0-or-later

// Simulated hardware for the README screenshots (tools/screenshots/make-screenshots.sh).
// Replaces ksystemstats, nvidia-smi, the gddr6 service, PCIe sysfs and the
// hardware probe in a throw-away copy of the widget – the real widget never loads this.

var t0 = Date.now();
var SPEED = 6;                   // simulated seconds per real second (graphs fill quickly)
var multi = false;               // two graphics cards (set by the patched main.qml)

function now() { return (Date.now() - t0) / 1000 * SPEED; }
// smooth wave 0…1 with period p (simulated seconds) and phase ph
function w(p, ph) { return (Math.sin(2 * Math.PI * now() / p + (ph || 0)) + 1) / 2; }
// small deterministic jitter
function j(seed, amp) { return Math.sin(now() * 1.7 + seed * 12.9898) * amp; }

// ---------------------------------------------------------------- hardware probe
function hwDiscover() {
    var T = "\t", out = [];
    out.push(["GPU", "0000:01:00.0", "0x10de", "nvidia", "1", "0", "NVIDIA Corporation", "AD104 [GeForce RTX 4070 SUPER]", ""].join(T));
    if (multi)
        out.push(["GPU", "0000:05:00.0", "0x10de", "nvidia", "2", "1", "NVIDIA Corporation", "GA104 [GeForce RTX 3060 Ti]", ""].join(T));
    out.push(["NVME", "0000:03:00.0", "Samsung SSD 990 PRO 2TB"].join(T));
    out.push("GDDR6" + T + "1");
    out.push(["NVFANS", "0", "2"].join(T));
    if (multi) out.push(["NVFANS", "1", "2"].join(T));
    out.push(["DISTRO", "apt", "lm-sensors", "Demo"].join(T));
    out.push("LMTOOL" + T + "1");
    out.push("SENSORS");
    out.push(JSON.stringify({
        "nct6798-isa-0290": {
            "Adapter": "ISA adapter",
            "fan1": { "fan1_input": 1100 }, "fan2": { "fan2_input": 850 }, "fan3": { "fan3_input": 820 },
            "SYSTIN": { "temp1_input": 33 }, "CPUTIN": { "temp2_input": 45 }
        },
        "nvme-pci-0300": { "Composite": { "temp1_input": 41 } }
    }));
    return out.join("\n") + "\n";
}

// fan speed (%) of card 0 at a temperature – also used for the prefilled learned curve
function fanCurve(x) {
    return x < 45 ? 30 : Math.min(100, 30 + (x - 45) * 1.9 + (x > 70 ? (x - 70) * 1.2 : 0));
}

// ---------------------------------------------------------------- nvidia-smi
function gpu(i) {
    // card 0: game running; card 1: lighter compute load
    if (i === 0) {
        var load = 86 + 12 * w(40) + j(1, 2);
        var temp = 58 + 14 * w(160, 1) + j(2, 0.6);
        return {
            "temperature.gpu": temp, "fan.speed": fanCurve(temp) + j(3, 0.8),
            "utilization.gpu": Math.min(100, load), "utilization.memory": 38 + 25 * w(40), "utilization.encoder": 0,
            "utilization.decoder": 4, "power.draw": 128 + 0.8 * load + 8 * w(17), "enforced.power.limit": 220,
            "power.max_limit": 240, "clocks.gr": 2310 + 160 * w(23), "clocks.max.gr": 3105, "clocks.mem": 10501,
            "clocks.max.mem": 10501, "clocks.video": 1950, "memory.total": 12282, "memory.used": 7400 + 900 * w(90),
            "memory.free": 12282 - 7400 - 900 * w(90), "pstate": "P2", "clocks_event_reasons.active": "0x0000000000000004"
        };
    }
    var l = 45 + 35 * w(60, 2);
    var t2 = 49 + 9 * w(130, 2);
    return {
        "temperature.gpu": t2, "fan.speed": 36 + (t2 - 48) * 2, "utilization.gpu": l, "utilization.memory": 20 + 15 * w(60, 2),
        "utilization.encoder": 0, "utilization.decoder": 0, "power.draw": 60 + 1.4 * l, "enforced.power.limit": 200,
        "power.max_limit": 220, "clocks.gr": 1500 + 300 * w(31), "clocks.max.gr": 2100, "clocks.mem": 7000,
        "clocks.max.mem": 7001, "clocks.video": 1500, "memory.total": 8192, "memory.used": 3100 + 600 * w(70),
        "memory.free": 8192 - 3100 - 600 * w(70), "pstate": "P2", "clocks_event_reasons.active": "0x0000000000000000"
    };
}

// stdout of `nvidia-smi --query-gpu=index,<keys> --format=csv,noheader,nounits`
function nvidiaStdout(keys) {
    var lines = [];
    for (var i = 0; i < (multi ? 2 : 1); ++i) {
        var g = gpu(i), row = [i];
        keys.forEach(function (k) {
            var v = g[k];
            if (k === "pci.bus_id") v = i === 0 ? "00000000:01:00.0" : "00000000:05:00.0";
            else if (k === "name") v = i === 0 ? "NVIDIA GeForce RTX 4070 SUPER" : "NVIDIA GeForce RTX 3060 Ti";
            row.push(v === undefined ? "[N/A]" : (typeof v === "number" ? v.toFixed(1) : v));
        });
        lines.push(row.join(", "));
    }
    return lines.join("\n");
}

// output of code/nvml-fans.py: measured fan speeds, two fans per card
function nvmlFans() {
    var T = "\t", out = [];
    for (var i = 0; i < (multi ? 2 : 1); ++i) {
        var pct = Math.round(gpu(i)["fan.speed"]);
        var rpm = Math.round(pct * (i === 0 ? 31 : 28));
        out.push(["FAN", i, 1, rpm + Math.round(j(8 + i, 12)), pct, pct].join(T));
        out.push(["FAN", i, 2, rpm - 15 + Math.round(j(9 + i, 12)), pct, pct].join(T));
    }
    return out.join("\n") + "\n";
}

// output of code/pcie-info.sh for a card
function pcieInfo(addr) {
    var second = multi && /05:00/.test(addr || "");
    return (second ? "0000:05:00.0 16.0 4 16.0 16 0000:00:1c.4 8.0 4"
                   : "0000:01:00.0 16.0 16 16.0 16 0000:00:01.0 16.0 16")
        + "\nVendor:\tNVIDIA Corporation\nDevice:\t" + (second ? "GA104 [GeForce RTX 3060 Ti]" : "AD104 [GeForce RTX 4070 SUPER]") + "\n";
}

// ---------------------------------------------------------------- ksystemstats / commands
// returns { value, unit, max } for a sensor id or shell command
function sensor(id, german) {
    var rpm = german ? "U/min" : "RPM";
    if (/gddr6\/vram/.test(id)) {
        var second = /05:00/.test(id);
        return { value: second ? 64 + 6 * w(130, 2) : 74 + 10 * w(160, 1.3), unit: "°C" };
    }
    switch (id) {
    case "cpu/all/maximumTemperature": return { value: 61 + 9 * w(70, 0.5) + j(4, 1), unit: "°C", max: 100 };
    case "cpu/all/usage":              return { value: 32 + 22 * w(20, 1) + j(5, 6), unit: "%", max: 100 };
    case "memory/physical/usedPercent": return { value: 47 + 2 * w(200), unit: "%", max: 100 };
    case "memory/physical/used":        return { value: 14.6 + 0.6 * w(200), unit: "GiB" };
    case "memory/physical/total":       return { value: 31.3, unit: "GiB" };
    case "memory/swap/used":            return { value: 0.3, unit: "GiB" };
    case "memory/swap/total":           return { value: 8, unit: "GiB" };
    case "disk/all/usedPercent":        return { value: 63.4, unit: "%", max: 100 };
    case "network/all/download":        return { value: Math.max(0.1, 2.2 + 2.5 * w(15, 2) + j(6, 0.8)), unit: "MiB/s", max: 8 };
    case "network/all/upload":          return { value: Math.max(0.05, 0.35 + 0.25 * w(25) + j(7, 0.08)), unit: "MiB/s", max: 2 };
    case "lmsensors/nvme-pci-0300/temp1": return { value: 42 + 4 * w(120), unit: "°C" };
    case "lmsensors/nct6798-isa-0290/temp1": return { value: 33 + 1.5 * w(200), unit: "°C" };
    case "lmsensors/nct6798-isa-0290/fan1": return { value: 1050 + 180 * w(70, 0.5), unit: rpm };
    case "lmsensors/nct6798-isa-0290/fan2": return { value: 840 + 90 * w(160), unit: rpm };
    case "lmsensors/nct6798-isa-0290/fan3": return { value: 810 + 90 * w(160, 0.4), unit: rpm };
    }
    return { value: NaN, unit: "" };
}
