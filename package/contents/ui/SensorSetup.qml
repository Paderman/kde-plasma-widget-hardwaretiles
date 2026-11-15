// SPDX-FileCopyrightText: 2026 Paderman
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as P5Support
import "Hardware.js" as Hardware

// Shown when no mainboard fans were found: explains why and offers a button that
// installs lm-sensors and detects the sensor chip (code/install-sensors.sh via
// pkexec – KDE asks for the administrator password). No terminal needed.
Kirigami.InlineMessage {
    id: setup
    property var probe                       // HardwareProbe

    readonly property string state_: probe && probe.ready ? Hardware.sensorSetupState(probe.hw) : "ok"
    property bool running: false
    property string result: ""               // ok | nomodules | installfailed | nopm | cancelled
    property string modules: ""

    readonly property string script: Qt.resolvedUrl("../code/install-sensors.sh").toString().replace(/^file:\/\//, "")
    readonly property string readme: "https://github.com/Paderman/kde-plasma-widget-hardwaretiles#mainboard-sensors"

    // whether there is something to say – the parent decides about `visible`
    // (reading our own `visible` there would stay false while a parent is hidden)
    readonly property bool shown: running || result !== "" || state_ !== "ok"
    visible: shown
    type: result === "ok" ? Kirigami.MessageType.Positive
        : (result === "installfailed" || result === "nopm") ? Kirigami.MessageType.Error
        : result === "nomodules" ? Kirigami.MessageType.Warning
        : Kirigami.MessageType.Information
    showCloseButton: result !== "" && !running
    onVisibleChanged: if (!visible) result = ""

    text: {
        if (running) return i18n("Setting up sensor support … this can take a minute.");
        switch (result) {
        case "ok":
            return state_ === "ok"
                ? i18n("Done – sensor driver loaded (%1). The fans are now offered.", modules)
                : i18n("Sensor driver loaded (%1), but no fan reports a speed yet. Fans that stand still appear once they spin.", modules);
        case "nomodules":
            return i18n("No supported sensor chip was found. Some mainboards need an extra driver – see the instructions.");
        case "installfailed":
        case "nopm":
            return i18n("The installation did not work. Please install “%1” with your software center and try again.", probe.hw.pmPackage || "lm-sensors");
        case "cancelled":
            return i18n("Cancelled – nothing was changed.");
        }
        return Hardware.sensorSetupText(probe ? probe.hw : null, (...a) => i18n(...a));
    }

    actions: [
        Kirigami.Action {
            visible: !setup.running && setup.result === "" && setup.state_ === "install"
            text: i18n("Install sensor support")
            icon.name: "run-install"
            onTriggered: setup.run()
        },
        Kirigami.Action {
            visible: !setup.running && setup.result === "" && setup.state_ === "detect"
            text: i18n("Detect sensor chip")
            icon.name: "edit-find"
            onTriggered: setup.run()
        },
        Kirigami.Action {
            visible: !setup.running && (setup.state_ === "manual" || setup.result === "nomodules" || setup.result === "installfailed" || setup.result === "nopm")
            text: i18n("Open instructions")
            icon.name: "help-contents"
            onTriggered: Qt.openUrlExternally(setup.readme)
        }
    ]

    function run() {
        running = true;
        result = "";
        _exec.connectSource("pkexec /bin/sh '" + script + "'");
    }

    property var _exec: P5Support.DataSource {
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source);
            if (source.indexOf("pkexec") === 0) {
                const out = String(data["stdout"] || "");
                const m = out.match(/^RESULT (\w+)/m);
                const mods = out.match(/^MODULES ?(.*)$/m);
                setup.modules = mods ? mods[1].trim().split(/\s+/).join(", ") : "";
                // no RESULT line: the password dialog was cancelled (pkexec exit 126/127)
                setup.result = m ? m[1] : "cancelled";
                if (setup.result === "ok") {
                    // ksystemstats reads the sensor chips only at start
                    connectSource("systemctl --user restart plasma-ksystemstats");
                } else {
                    setup.running = false;
                }
            } else {
                refreshTimer.start();
            }
        }
    }
    // give ksystemstats a moment before the hardware is probed again
    property var _timer: Timer {
        id: refreshTimer
        interval: 2500
        onTriggered: { setup.probe.refresh(); setup.running = false; }
    }
}
