// SPDX-FileCopyrightText: 2026 Paderman
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import org.kde.quickcharts as Charts
import org.kde.notification
import "Defaults.js" as Defaults
import "NvidiaKeys.js" as NK

// One data source per tile. Lives centrally in main.qml (keyed by the tile id),
// so panel + popup share values and graph history / fan curve survive reordering.
Item {
    id: src
    visible: false

    property var cfg: ({})
    property int interval: 1500
    property int historyLength: 60
    property var nvidia: null

    readonly property bool isCurve: cfg.style === "curve"

    // ---- readers --------------------------------------------------------
    Reader {
        id: main
        source: src.cfg.source || "sensor"
        sensorId: src.cfg.sensorId || ""
        command: src.cfg.command || ""
        key: src.cfg.key || ""
        unit: src.cfg.unit || ""
        interval: src.interval
        nvidia: src.nvidia
        gpuIndex: src.cfg.nvIndex === undefined ? 0 : src.cfg.nvIndex
        gpuAddr: src.cfg.gpuAddr || ""
    }
    // reference / maximum: explicit sensor, else the natural nvidia maximum (memory.total …)
    Reader {
        id: ref
        enabled_: source === "nvidia" ? key !== "" : sensorId !== ""
        source: src.cfg.refSensorId ? "sensor" : (main.nvMaxKey ? "nvidia" : "sensor")
        sensorId: src.cfg.refSensorId || ""
        key: src.cfg.refSensorId ? "" : main.nvMaxKey
        interval: Math.max(src.interval, 5000)
        nvidia: src.nvidia
        gpuIndex: src.cfg.nvIndex === undefined ? 0 : src.cfg.nvIndex
    }
    // memory tiles: swap usage for the tooltip
    readonly property bool isMemory: (cfg.source || "sensor") === "sensor" && /^memory\/physical\//.test(cfg.sensorId || "")
    Reader {
        id: swapUsed
        enabled_: sensorId !== ""
        source: "sensor"
        sensorId: src.isMemory ? "memory/swap/used" : ""
        interval: Math.max(src.interval, 5000)
    }
    Reader {
        id: swapTotal
        enabled_: sensorId !== ""
        source: "sensor"
        sensorId: src.isMemory ? "memory/swap/total" : ""
        interval: Math.max(src.interval, 5000)
    }
    readonly property string swapText: !isMemory || !swapTotal.valid ? ""
        : swapTotal.value > 0 ? i18n("Swap space: %1 / %2", swapUsed.valid ? swapUsed.formatted : "–", swapTotal.formatted)
        : i18n("Swap space: none set up")
    // y axis of the fan curve
    Reader {
        id: yr
        enabled_: src.isCurve
        source: src.cfg.ySource || "nvidia"
        sensorId: src.cfg.ySensorId || ""
        command: src.cfg.yCommand || ""
        key: src.cfg.yKey || ""
        unit: src.cfg.yUnit || ""
        interval: src.interval
        nvidia: src.nvidia
        gpuIndex: src.cfg.nvIndex === undefined ? 0 : src.cfg.nvIndex
    }
    readonly property alias reader: main
    readonly property alias yReader: yr
    readonly property alias refReader: ref

    // ---- value ----------------------------------------------------------
    readonly property real value: main.value
    readonly property bool valid: main.valid
    // a source that has not delivered a single value 15 s after start has no
    // data at all (e.g. temperature of graphics built into the processor) –
    // compare tiles leave such a card out
    property bool everValid: false
    property bool settled: false
    onValidChanged: if (valid) everValid = true
    Component.onCompleted: if (valid) everValid = true
    Timer { interval: 15000; running: true; onTriggered: src.settled = true }
    readonly property bool noData: settled && !everValid
    readonly property bool hasRef: ref.enabled_ && ref.valid && ref.value > 0

    // ---- meta -----------------------------------------------------------
    readonly property string label: cfg.label || main.shortName || (main.isCommand ? i18n("Command") : (cfg.sensorId || "—"))
    // with several graphics cards: "RTX 3080 · GPU" (notifications, tooltip)
    readonly property string gpuTag: cfg.gpuTag || ""
    readonly property string longLabel: gpuTag ? gpuTag + " · " + label : label
    readonly property string fullName: main.name
    readonly property real minimum: Number(cfg.min) || 0
    readonly property real maximum: {
        const m = Number(cfg.max) || 0;
        if (m > minimum) return m;
        if (hasRef) return ref.value;
        if (main.sourceMax > minimum) return main.sourceMax;
        return 100;
    }
    // relThresholds: warn/crit are percent of the total – off until the total is known
    readonly property bool relThresholds: !!cfg.relThresholds
    function fromPercent(p) { return relThresholds ? (hasRef && p > 0 ? minimum + (maximum - minimum) * p / 100 : 0) : p; }
    function percentOf(v) { return Math.round((v - minimum) / Math.max(1e-9, maximum - minimum) * 100); }
    readonly property real warn: fromPercent(Number(cfg.warn) || 0)
    readonly property real crit: fromPercent(Number(cfg.crit) || 0)
    // lower thresholds: the value falls below them (battery, supply voltages)
    readonly property real lowWarn: fromPercent(Number(cfg.lowWarn) || 0)
    readonly property real lowCrit: fromPercent(Number(cfg.lowCrit) || 0)
    readonly property bool hasLow: lowWarn > 0 || lowCrit > 0
    readonly property int highLevel: (crit > 0 && value >= crit) ? 2 : (warn > 0 && value >= warn) ? 1 : 0
    readonly property int lowLevel: (lowCrit > 0 && value <= lowCrit) ? 2 : (lowWarn > 0 && value <= lowWarn) ? 1 : 0
    // the value is too low (not too high) right now
    readonly property bool low: lowLevel > highLevel

    // never NaN: an animation that starts from NaN stays NaN (empty bar until restart),
    // and while the readers update, maximum can be NaN for a moment
    readonly property real fraction: {
        if (!valid) return 0;
        const f = (value - minimum) / Math.max(1e-9, maximum - minimum);
        return isFinite(f) ? Math.max(0, Math.min(1, f)) : 0;
    }
    // 0 = ok, 1 = warn, 2 = critical
    readonly property int thresholdLevel: Math.max(highLevel, lowLevel)
    // a forced level (stuck or slow fan, missing PCIe lanes) counts even without a value
    readonly property int level: Math.max(main.forcedLevel, valid ? thresholdLevel : 0)
    // a fan from a sensor chip (mainboard, radeon/nouveau card) below its critical
    // lower threshold: it has stopped – said in words, like for NVIDIA cards
    readonly property bool isFanSensor: main.isSensor && /^lmsensors\/[^\/]+\/fan\d+$/.test(main.sensorId)
    readonly property bool fanDown: isFanSensor && valid && lowCrit > 0 && lowLevel === 2
    readonly property string detailText: main.detail || (fanDown ? i18n("Fan not turning") : "")
    readonly property string subtitleText: main.subtitle
    readonly property string subtitleInfo: main.subtitleInfo

    readonly property color accent: Defaults.themed(cfg.color ? cfg.color : Defaults.colorFor(cfg.id), lightTheme)
    property bool lightTheme: false   // set by main.qml from the Plasma colours
    readonly property color color: level === 2 ? Defaults.critColor(lightTheme) : level === 1 ? Defaults.warnColor(lightTheme) : accent

    // ---- formatted output ----------------------------------------------
    readonly property string formatted: main.formatted
    readonly property bool isText: main.isText
    // split "52,3 °C" -> "52,3" + "°C" (texts like "P2" stay whole)
    readonly property var parts: {
        if (isText) return [formatted, ""];
        const m = formatted.match(/^\s*([-+]?[\d.,   ]*\d)\s*(.*)$/);
        return m ? [m[1], m[2]] : [formatted, ""];
    }
    readonly property string numberText: parts[0]
    readonly property string unitText: parts[1]
    // "/ 10 GiB" when a reference maximum exists
    readonly property string totalText: hasRef && !isText ? ref.formatted : ""

    readonly property alias history: hist

    // ---- fan curve data ---------------------------------------------------
    // trail: recent (x, y) samples; bins: learned average y per 1 unit of x
    property var trail: []
    property var bins: ({})
    property int curveRevision: 0
    readonly property real yValue: yr.value
    readonly property real yMax: (Number(cfg.yMax) > 0) ? Number(cfg.yMax)
                               : (yr.sourceMax > 0 ? yr.sourceMax : 100)

    Timer {
        running: src.isCurve
        interval: src.interval
        repeat: true
        onTriggered: {
            if (!main.valid || !yr.valid) return;
            const x = main.value, y = yr.value;
            const t = src.trail.slice(-(Math.max(10, Math.round(src.historyLength * 1000 / src.interval)) - 1));
            t.push({ x: x, y: y });
            src.trail = t;
            const k = Math.round(x);
            const b = src.bins[k];
            // running mean that slowly adapts (weight capped at 30 samples)
            if (b) { b.n = Math.min(30, b.n + 1); b.y += (y - b.y) / b.n; }
            else src.bins[k] = { y: y, n: 1 };
            src.curveRevision++;
        }
    }
    function resetCurve() { trail = []; bins = ({}); curveRevision++; }
    // which pair of sensors the learned data belongs to (stored with it, so a
    // changed tile does not get the curve of other sensors)
    readonly property string curvePair: [cfg.source, cfg.sensorId, cfg.key, cfg.command,
                                         cfg.ySource, cfg.ySensorId, cfg.yKey, cfg.yCommand].join("|")
    function exportCurve() {
        const out = {};
        for (const k in bins) out[k] = [Math.round(bins[k].y * 10) / 10, bins[k].n];
        return { pair: curvePair, bins: out };
    }
    function importCurve(d) {
        if (!d || d.pair !== curvePair || !d.bins) return;
        const b = {};
        for (const k in d.bins) b[k] = { y: Number(d.bins[k][0]), n: Number(d.bins[k][1]) };
        bins = b;
        curveRevision++;
    }

    // ---- notifications ---------------------------------------------------
    property bool alertsEnabled: true
    property bool alertOnWarn: false
    property bool alertRecovery: true
    property int alertDelay: 5000        // value must stay above threshold this long
    property int alertCooldown: 600000   // no repeat of the same level within this time
    property real hysteresis: 3          // must drop this far below threshold to re-arm
    // in the tile's unit; with relative thresholds the setting counts as percent of the total
    readonly property real hyst: relThresholds && hasRef ? (maximum - minimum) * hysteresis / 100 : hysteresis
    // small values (volts): at most 2 % of the threshold – 3 °C steps would never be reached again
    function hystFor(lim) { return lim > 0 && lim < 20 && !(relThresholds && hasRef) ? Math.min(hyst, lim * 0.02) : hyst; }

    readonly property bool notifyAllowed: alertsEnabled && cfg.notify !== false
    // level we would like to alert for right now
    readonly property int alertTarget: !notifyAllowed || (!valid && main.forcedLevel < 1) ? 0
                                     : level === 2 ? 2
                                     // a slow fan is a warning that always notifies
                                     : (level === 1 && (alertOnWarn || (main.forcedLevel === 1 && main.slowText))) ? 1 : 0
    property int alertLevel: 0           // level currently "armed/alerted"
    property bool alertShown: false      // a notification is on screen for this sensor
    property double lastAlertAt: 0
    property int lastAlertLevel: 0
    property bool alertForced: false     // the alert came from the source, not from a threshold

    property bool alertLow: false        // the alert is for a value that is too low
    function thresholdFor(l, lowSide) { return lowSide ? (l === 2 ? lowCrit : lowWarn) : (l === 2 ? crit : warn); }

    function evaluateAlert() {
        if (!notifyAllowed) {
            confirmTimer.stop();
            if (alertLevel !== 0) { alertLevel = 0; closeActive(); }
            return;
        }
        if (!valid && main.forcedLevel < 1) return;
        if (alertTarget > alertLevel) {
            if (!confirmTimer.running) confirmTimer.restart();
            return;
        }
        confirmTimer.stop();
        // de-escalate only once the value is clearly back on the normal side
        const lim = thresholdFor(alertLevel, alertLow);
        const h = hystFor(lim);
        const clear = v => alertLow ? v > lim + h : v < lim - h;
        const below = alertForced ? main.forcedLevel < alertLevel && (lim <= 0 || !valid || clear(value))
                                  : clear(value);
        if (alertLevel > 0 && below) {
            let next = 0;
            const w = thresholdFor(1, alertLow), hw = hystFor(w);
            if (alertLevel === 2 && alertOnWarn && w > 0 && (alertLow ? value <= w + hw : value >= w - hw)) next = 1;
            const wasFan = (alertForced && !!lastFanText) || (alertLow && isFanSensor);
            alertLevel = next;
            alertForced = false;
            if (next === 0 && alertShown) {
                if (alertRecovery) sendNote(0, wasFan);
                else closeActive();
                alertShown = false;
            }
        }
    }

    function fireAlert(l) {
        const now = Date.now();
        const escalation = alertLevel > 0;           // e.g. warn -> crit: always tell
        const suppressed = !escalation && l <= lastAlertLevel && (now - lastAlertAt) < alertCooldown;
        alertLevel = l;
        alertForced = main.forcedLevel >= l && thresholdLevel < l;
        alertLow = !alertForced && low;
        // a fan problem is shown on every tile of that fan – one notification is enough
        if (alertForced && main.fanText && src.nvidia && !src.nvidia.claimFanNote(main.gpuIndex)) return;
        if (suppressed) return;
        lastAlertAt = now;
        lastAlertLevel = l;
        sendNote(l);
        alertShown = true;
    }

    property var activeNote: null

    function closeActive() {
        const n = activeNote;
        activeNote = null;
        alertShown = false;
        if (n) n.close();
    }

    // One Notification object per event: KNotification sends asynchronously,
    // so re-using a single object could send stale/overwritten texts.
    property string lastFanText: ""
    function sendNote(l, wasFan) {
        const low = alertLow;
        const lim = thresholdFor(l, low);
        const limTxt = relThresholds ? main.format(lim) + " (" + percentOf(lim) + " %)"
                     : main.isSensor ? lim.toLocaleString(Qt.locale(), "f", Number.isInteger(lim) ? 0 : Math.abs(lim) < 20 ? 2 : 1) + (unitText ? " " + unitText : "")
                     : main.format(lim);
        const p = {};
        lastFanText = l > 0 && alertForced ? main.fanText : "";
        if (l === 1 && alertForced && main.slowText) {
            p.title = i18n("%1: fan running slowly", longLabel);
            p.text = main.slowText + "\n" + i18n("Its bearing may be stiff, or dust slows it down.");
            p.iconName = "dialog-warning";
            p.urgency = Notification.HighUrgency;
            p.flags = Notification.CloseOnTimeout;
        } else if (l === 2 && alertForced && main.stuckText) {
            p.title = i18n("%1: fan not turning", longLabel);
            p.text = main.stuckText + "\n" + i18n("Check whether something blocks it or a cable came loose.");
            p.iconName = "dialog-warning";
            p.urgency = Notification.CriticalUrgency;
            p.flags = Notification.Persistent;
        } else if (l === 2 && low && isFanSensor) {
            p.title = i18n("%1: fan not turning", longLabel);
            p.text = i18n("Only %1 – below the critical threshold of %2. The fan has stopped or is about to.", formatted, limTxt)
                   + "\n" + i18n("Check whether something blocks it or a cable came loose.");
            p.iconName = "dialog-warning";
            p.urgency = Notification.CriticalUrgency;
            p.flags = Notification.Persistent;
        } else if (l === 2) {
            p.title = i18n("%1 critical: %2", longLabel, formatted);
            p.text = low ? i18n("Below the critical threshold of %1.", limTxt) : i18n("Critical threshold of %1 exceeded.", limTxt);
            p.iconName = low ? "dialog-warning" : "temperature-high";
            p.urgency = Notification.CriticalUrgency;
            p.flags = Notification.Persistent;
        } else if (l === 1) {
            p.title = low ? i18n("%1 low: %2", longLabel, formatted) : i18n("%1 high: %2", longLabel, formatted);
            p.text = low ? i18n("Below the warning threshold of %1.", limTxt) : i18n("Warning threshold of %1 exceeded.", limTxt);
            p.iconName = "dialog-warning";
            p.urgency = Notification.HighUrgency;
            p.flags = Notification.CloseOnTimeout;
        } else {
            p.title = i18n("%1 back to normal: %2", longLabel, formatted);
            p.text = wasFan ? i18n("The fans are running normally again.")
                   : low ? i18n("The value is above the threshold again.") : i18n("The value is below the threshold again.");
            p.iconName = "temperature-normal";
            p.urgency = Notification.LowUrgency;
            p.flags = Notification.CloseOnTimeout;
        }
        // the sensor's own name – not a bare channel name like "Fan 1" (radeon/nouveau
        // fan, unnamed chip inputs): next to "GPU fan" it reads like a different fan
        if (fullName && fullName !== label && !(main.isSensor && /^[^\s\d]+\s?\d+$/.test(fullName.trim())))
            p.text += "\n" + fullName;

        closeActive();                     // replace the previous alert of this sensor
        const n = noteComponent.createObject(src, p);
        if (!n) return;
        if (l > 0) activeNote = n;         // recovery notes are fire-and-forget
        n.sendEvent();
    }

    Component {
        id: noteComponent
        Notification {
            id: n
            componentName: "plasma_workspace"
            eventId: "notification"
            autoDelete: false
            onClosed: {
                if (src.activeNote === n) { src.activeNote = null; src.alertShown = false; }
                n.destroy(1000);
            }
        }
    }

    // deferred, so dependent bindings (formatted, level …) are up to date
    onAlertTargetChanged: Qt.callLater(evaluateAlert)
    onValueChanged: Qt.callLater(evaluateAlert)
    onNotifyAllowedChanged: Qt.callLater(evaluateAlert)

    Timer {
        id: confirmTimer
        interval: Math.max(0, src.alertDelay)
        onTriggered: if (src.alertTarget > src.alertLevel) src.fireAlert(src.alertTarget)
    }


    // ---- history for graphs ---------------------------------------------
    Charts.HistoryProxySource {
        id: hist
        source: Charts.SingleValueSource { value: src.valid ? src.value : src.minimum }
        maximumHistory: Math.max(5, Math.round(src.historyLength * 1000 / src.interval))
        interval: src.interval
        fillMode: Charts.HistoryProxySource.FillFromEnd
    }
}
