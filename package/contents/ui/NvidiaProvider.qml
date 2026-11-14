// SPDX-FileCopyrightText: 2026 Paderman
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import org.kde.plasma.plasma5support as P5Support
import "NvidiaKeys.js" as NK

// Runs a single `nvidia-smi` query per interval for all needed GPUs and
// publishes the fields per nvidia-smi index.
QtObject {
    id: provider

    property bool active: false
    property int interval: 1500
    // nvidia-smi indices to query, e.g. [0, 1]
    property var indices: [0]

    // raw strings per GPU index, e.g. {0: {"fan.speed": "48", ...}, 1: {...}}
    property var raw: ({})
    property bool ok: false
    property int revision: 0

    readonly property var queryKeys: NK.allQueryKeys()
    readonly property string idxList: (indices && indices.length ? indices : [0]).join(",")
    readonly property string cmd: "nvidia-smi -i " + idxList + " --query-gpu=index," + queryKeys.join(",")
                                  + " --format=csv,noheader,nounits"

    function hasGpu(idx) {
        revision;
        return ok && !!raw[idx];
    }
    function decoded(key, idx) {
        revision;
        const r = raw[idx >= 0 ? idx : 0];
        return r ? NK.decode(key, r[key], r, (...a) => i18n(...a)) : { value: NaN, text: "" };
    }

    property var _exec: P5Support.DataSource {
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            const r = {};
            let n = 0;
            if (data["exit code"] === 0) {
                String(data["stdout"] || "").trim().split("\n").forEach(line => {
                    const parts = line.split(",");
                    if (parts.length < provider.queryKeys.length + 1) return;
                    const idx = parseInt(parts[0]);
                    if (isNaN(idx)) return;
                    const o = {};
                    provider.queryKeys.forEach((k, i) => o[k] = parts[i + 1]);
                    r[idx] = o;
                    n++;
                });
            }
            provider.raw = r;
            provider.ok = n > 0;
            provider.revision++;
            disconnectSource(source);
        }
    }

    // ---- fans, from the driver library (code/nvml-fans.py) ------------------
    // only runs while a tile shows a fan of an NVIDIA card
    property bool fansActive: false
    // per GPU index: [{ no, rpm, pct, target, since }] (-1 = not reported;
    // since = time the fan first stood still although it should turn, 0 = fine)
    property var fans: ({})
    property bool fansOk: false
    property int fanFailures: 0
    // a fan that should turn but stands still this long counts as stuck –
    // after a start from fan stop it needs a few seconds to spin up
    readonly property int stuckAfter: 15000
    // a fan slower than fanSlowPercent % of the fastest fan of the card (same target)
    // this long counts as slow – stiff bearing, dust, cable; fanSlowPercent 0 = off
    readonly property int slowAfter: 30000
    property bool fanWatch: true
    property int fanSlowPercent: 50

    function fanList(idx) {
        revision;
        return fansOk ? (fans[idx >= 0 ? idx : 0] || []) : [];
    }
    function hasFans(idx) { return fanList(idx).some(f => f.rpm >= 0); }
    // no = 0: average of all fans, otherwise fan no (from 1)
    function fanRpm(idx, no) {
        const l = fanList(idx).filter(f => f.rpm >= 0 && (no <= 0 || f.no === no));
        return l.length ? Math.round(l.reduce((a, f) => a + f.rpm, 0) / l.length) : NaN;
    }
    // fans (no = 0: all) that should turn but have stood still for stuckAfter
    function stuckFans(idx, no) {
        if (!fanWatch) return [];
        const now = Date.now();
        return fanList(idx).filter(f => (no <= 0 || f.no === no) && f.since > 0 && now - f.since >= stuckAfter);
    }
    // [{ fan, ref }]: fans that run clearly slower than the fastest fan ref
    function slowFans(idx, no) {
        if (!fanWatch || fanSlowPercent <= 0) return [];
        const now = Date.now(), l = fanList(idx);
        return l.filter(f => (no <= 0 || f.no === no) && f.slowSince > 0 && now - f.slowSince >= slowAfter)
                .map(f => ({ fan: f, ref: l.find(o => o.no === f.ref) || f }));
    }
    // several tiles may show the same fan – only one of them notifies
    property var _fanNoteAt: ({})
    function claimFanNote(idx) {
        const now = Date.now();
        if (now - (_fanNoteAt[idx] || 0) < 60000) return false;
        _fanNoteAt[idx] = now;
        return true;
    }

    readonly property string fanScript: Qt.resolvedUrl("../code/nvml-fans.py").toString().replace(/^file:\/\//, "")

    property var _fanExec: P5Support.DataSource {
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source);
            const now = Date.now();
            const r = {};
            let n = 0;
            if (data["exit code"] === 0) {
                String(data["stdout"] || "").trim().split("\n").forEach(line => {
                    const f = line.split("\t");
                    if (f[0] !== "FAN" || f.length < 6) return;
                    const idx = parseInt(f[1]), no = parseInt(f[2]);
                    if (isNaN(idx) || isNaN(no)) return;
                    const fan = { no: no, rpm: parseInt(f[3]), pct: parseInt(f[4]), target: parseInt(f[5]), since: 0 };
                    if (fan.rpm === 0 && fan.target > 0) {
                        const old = (provider.fans[idx] || []).find(o => o.no === no);
                        fan.since = old && old.since > 0 ? old.since : now;
                    }
                    (r[idx] = r[idx] || []).push(fan);
                    n++;
                });
            }
            // compare the fans of a card that run at the same target: the fastest is the
            // reference, a fan below fanSlowPercent % of it is slow (standing still is "stuck")
            for (const idx in r) {
                const l = r[idx];
                l.forEach(f => {
                    f.slowSince = 0; f.ref = 0;
                    if (l.length < 2 || f.rpm <= 0 || f.target < 0) return;
                    const peers = l.filter(o => o !== f && o.target === f.target && o.rpm > 0);
                    if (!peers.length) return;
                    const top = peers.reduce((a, o) => o.rpm > a.rpm ? o : a);
                    // below 300 RPM the measurement is too rough to compare
                    if (top.rpm < 300 || f.rpm * 100 >= top.rpm * provider.fanSlowPercent) return;
                    const old = (provider.fans[idx] || []).find(o => o.no === f.no);
                    f.slowSince = old && old.slowSince > 0 ? old.slowSince : now;
                    f.ref = top.no;
                });
            }
            provider.fans = r;
            provider.fansOk = n > 0;
            provider.fanFailures = n > 0 ? 0 : provider.fanFailures + 1;
            provider.revision++;
        }
    }
    property var _fanTimer: Timer {
        running: provider.fansActive
        // no python3 or a driver without the library: try again only now and then
        interval: provider.fanFailures >= 3 ? 60000 : provider.interval
        repeat: true
        triggeredOnStart: true
        onTriggered: provider._fanExec.connectSource("python3 -I '" + provider.fanScript + "'")
    }

    property var _timer: Timer {
        running: provider.active
        interval: provider.interval
        repeat: true
        triggeredOnStart: true
        onTriggered: provider._exec.connectSource(provider.cmd)
    }
}
