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

    property var _timer: Timer {
        running: provider.active
        interval: provider.interval
        repeat: true
        triggeredOnStart: true
        onTriggered: provider._exec.connectSource(provider.cmd)
    }
}
