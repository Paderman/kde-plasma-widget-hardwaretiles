// SPDX-FileCopyrightText: 2026 Paderman
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import org.kde.plasma.plasma5support as P5Support
import "Hardware.js" as Hardware

// Runs code/hw-discover.sh once (and on refresh()) and publishes the result.
QtObject {
    id: probe

    property var hw: ({ gpus: [], nvmes: [], gddr6: false, chips: {} })
    property bool ready: false
    property bool running: false
    readonly property var gpus: Hardware.supportedGpus(hw)

    readonly property string script: Qt.resolvedUrl("../code/hw-discover.sh").toString().replace(/^file:\/\//, "")

    function refresh() {
        running = true;
        _exec.connectSource("sh '" + script + "'");
    }

    property var _exec: P5Support.DataSource {
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            probe.hw = Hardware.parse(String(data["stdout"] || ""));
            probe.ready = true;
            probe.running = false;
            disconnectSource(source);
        }
    }

    Component.onCompleted: refresh()
}
