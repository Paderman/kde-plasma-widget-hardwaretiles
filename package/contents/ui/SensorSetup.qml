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
    property string result: ""               // ok | nomodules | installfailed | nopm | nopkexec | cancelled
    property string modules: ""
    // pkexec missing: PackageKit can install it – code/install-package.py talks to it
    // over D-Bus like Discover, so KDE's own password dialog appears (needs python3
    // with GLib's gi). "pkexec" step: that installation is running
    property bool canPkcon: false
    property string pkconError: ""          // PackageKit's reason when it failed
    readonly property string pkgScript: Qt.resolvedUrl("../code/install-package.py").toString().replace(/^file:\/\//, "")
    property string step: ""
    readonly property string pkexecPackage: probe && probe.hw && probe.hw.pm === "apt" ? "pkexec" : "polkit"

    readonly property string script: Qt.resolvedUrl("../code/install-sensors.sh").toString().replace(/^file:\/\//, "")
    readonly property string readme: "https://github.com/Paderman/kde-plasma-widget-hardwaretiles#mainboard-sensors"

    // whether there is something to say – the parent decides about `visible`
    // (reading our own `visible` there would stay false while a parent is hidden)
    readonly property bool shown: running || result !== "" || state_ !== "ok"
    visible: shown
    type: result === "ok" ? Kirigami.MessageType.Positive
        : (result === "installfailed" || result === "nopm" || result === "pkexecfailed" || (result === "nopkexec" && !canPkcon)) ? Kirigami.MessageType.Error
        : result === "nomodules" ? Kirigami.MessageType.Warning
        : Kirigami.MessageType.Information
    showCloseButton: result !== "" && !running
    onVisibleChanged: if (!visible) result = ""

    text: {
        if (running && step === "pkexec") return i18n("Installing “%1” … KDE asks for the password.", pkexecPackage);
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
        case "nopkexec": {
            // Debian 13 and newer ship pkexec as a package of its own, not installed by default
            const pm = probe && probe.hw ? probe.hw.pm : "";
            const pkg = pkexecPackage;
            if (canPkcon)
                return i18n("The password prompt needs the program “pkexec”, which is not installed. Hardware Tiles can install the package “%1” for you – KDE asks for the password.", pkg);
            const cmd = pm === "apt" ? "sudo apt install pkexec" : pm === "dnf" ? "sudo dnf install polkit"
                      : pm === "zypper" ? "sudo zypper install polkit" : pm === "pacman" ? "sudo pacman -S polkit" : "";
            return cmd ? i18n("The password prompt needs the program “pkexec”, which is not installed. Install the package “%1” (in a terminal: %2) and try again.", pkg, cmd)
                       : i18n("The password prompt needs the program “pkexec”, which is not installed. Install the package “%1” and try again.", pkg);
        }
        case "pkexecfailed":
            return i18n("“%1” could not be installed. Please install it with your software center and try again.", pkexecPackage)
                + (pkconError ? "\n" + i18n("Message: %1", pkconError) : "");
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
            visible: !setup.running && setup.result === "nopkexec" && setup.canPkcon
            text: i18n("Install “%1”", setup.pkexecPackage)
            icon.name: "run-install"
            onTriggered: setup.installPkexec()
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
        step = "";
        result = "";
        // without pkexec no password prompt appears at all – say so instead of
        // "cancelled", and tell whether PackageKit could install it
        _exec.connectSource("if command -v pkexec >/dev/null 2>&1; then pkexec /bin/sh '" + script + "'; "
                            + "elif command -v python3 >/dev/null 2>&1 && python3 -c 'import gi' >/dev/null 2>&1; then echo 'RESULT nopkexec pkcon'; "
                            + "else echo 'RESULT nopkexec'; fi");
    }
    // PackageKit installs pkexec (its own password prompt), then the setup goes on
    function installPkexec() {
        running = true;
        step = "pkexec";
        result = "";
        pkconError = "";
        _exec.connectSource("python3 -I '" + pkgScript + "' " + pkexecPackage + "; "
                            + "command -v pkexec >/dev/null 2>&1 && echo PKEXEC_OK");
    }

    property var _exec: P5Support.DataSource {
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source);
            const out = String(data["stdout"] || "");
            if (source.indexOf("install-package.py") >= 0) {
                if (out.indexOf("PKEXEC_OK") >= 0) {
                    setup.run();                    // straight on with the sensor setup
                } else {
                    console.warn("Hardware Tiles: installing pkexec failed:", out);
                    const f = out.match(/^RESULT (?:failed )?(.*)$/m);
                    setup.pkconError = f && f[1] !== "ok" ? f[1].trim() : "";
                    setup.result = "pkexecfailed";
                    setup.step = "";
                    setup.running = false;
                }
            } else if (source.indexOf("pkexec") >= 0) {
                const m = out.match(/^RESULT (\w+)/m);
                setup.canPkcon = /^RESULT nopkexec pkcon/m.test(out);
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
