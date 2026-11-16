# SPDX-FileCopyrightText: 2026 Paderman
# SPDX-License-Identifier: GPL-2.0-or-later
#
# python3 patch.py <package copy> <demo.js> <layout.json> <mode> <out.png> <width> <height>
# Turns a copy of the widget into a screenshot rig: simulated data (Demo.js),
# preset layout, fixed size, and a timer that saves the widget as PNG and quits.
import json, re, shutil, sys, glob, os
pkg, demo, layout_file, mode, out, W, H = sys.argv[1:8]
ID = "io.github.paderman.hardwaretiles.screenshot"
ui = pkg + "/contents/ui/"

def edit(f, pairs):
    s = open(ui + f).read()
    for old, new in pairs:
        if old not in s:
            sys.exit(f"patch.py: '{old[:50]}' not found in {f}")
        s = s.replace(old, new, 1)
    open(ui + f, "w").write(s)

# own id (and translation domain) so it never mixes with the real widget
m = json.load(open(pkg + "/metadata.json"))
old_id = m["KPlugin"]["Id"]
m["KPlugin"]["Id"] = ID
json.dump(m, open(pkg + "/metadata.json", "w"), indent=4, ensure_ascii=False)
for mo in glob.glob(pkg + "/contents/locale/*/LC_MESSAGES/*.mo"):
    os.rename(mo, os.path.join(os.path.dirname(mo), "plasma_applet_" + ID + ".mo"))

d = open(demo).read()
if mode in ("multi", "cards"):
    d = d.replace("var multi = false;", "var multi = true;")
open(ui + "Demo.js", "w").write(d)

edit("Reader.qml", [
    ('import "NvidiaKeys.js" as NK', 'import "NvidiaKeys.js" as NK\nimport "Demo.js" as Demo'),
    # no real sensors: the Instantiator that makes the Sensor objects gets no id
    ("readonly property string activeSensorId: enabled_ && isSensor ? sensorId : \"\"",
     'readonly property string activeSensorId: ""'),
    ("    readonly property real value: !enabled_ ? NaN",
     "    property int demoTick: 0\n"
     "    Timer { interval: reader.interval; running: true; repeat: true; onTriggered: reader.demoTick++ }\n"
     "    readonly property var demo: (demoTick, Demo.sensor(isCommand ? command : sensorId, Qt.locale().name.indexOf(\"de\") === 0))\n"
     "    readonly property real value: !enabled_ ? NaN"),
    (": isCommand ? (cmdOk ? cmdValue : NaN)", ": isCommand ? demo.value"),
    (": (sensor.status === Sensors.Sensor.Ready && !noGpuTemp ? Number(sensor.value) : NaN)", ": demo.value"),
    ("isSensor && sensor.maximum > 0 ? sensor.maximum", "isSensor && demo.max > 0 ? demo.max"),
    ("running: reader.enabled_ && reader.isCommand && reader.command !== \"\"", "running: false"),
    ("pcieExec.connectSource(\"sh '\" + script + \"' \" + addr);",
     "pcieExec.newData(\"demo\", { \"exit code\": 0, \"stdout\": Demo.pcieInfo(addr) });"),
])
s = open(ui + "Reader.qml").read()
s = re.sub(r"readonly property string sensorUnit: \{.*?\n    \}", "readonly property string sensorUnit: demo.unit", s, count=1, flags=re.S)
open(ui + "Reader.qml", "w").write(s)

edit("NvidiaProvider.qml", [
    ('import "NvidiaKeys.js" as NK', 'import "NvidiaKeys.js" as NK\nimport "Demo.js" as Demo'),
    ("onTriggered: provider._exec.connectSource(provider.cmd)",
     "onTriggered: provider._exec.newData(\"demo\", { \"exit code\": 0, \"stdout\": Demo.nvidiaStdout(provider.queryKeys) })"),
    ("onTriggered: provider._fanExec.connectSource(\"python3 -I '\" + provider.fanScript + \"'\")",
     "onTriggered: provider._fanExec.newData(\"demo\", { \"exit code\": 0, \"stdout\": Demo.nvmlFans() })"),
])
edit("HardwareProbe.qml", [
    ('import "Hardware.js" as Hardware', 'import "Hardware.js" as Hardware\nimport "Demo.js" as Demo'),
    ("        running = true;\n        _exec.connectSource(\"sh '\" + script + \"'\");",
     "        probe.hw = Hardware.parse(Demo.hwDiscover());\n        probe.ready = true;"),
])
edit("main.qml", [("Math.max(250, Plasmoid.configuration.updateInterval)", "Math.max(60, Plasmoid.configuration.updateInterval)")])

# fixed size, a background like the Plasma dialog, and the screenshot timer
edit("FullView.qml", [
    ("    Layout.preferredWidth: root.needsSetup ? Kirigami.Units.gridUnit * 30 : grid.implicitWidth + gap * 2\n"
     "    Layout.preferredHeight: root.needsSetup ? Kirigami.Units.gridUnit * 30 : grid.implicitHeight + gap * 2",
     f"    Layout.preferredWidth: {W}\n    Layout.preferredHeight: {H}\n"
     f"    Layout.minimumWidth: {W}\n    Layout.minimumHeight: {H}\n"
     "    Rectangle {\n        z: -100\n        anchors.fill: parent\n        radius: Kirigami.Units.cornerRadius * 2\n"
     "        color: Kirigami.Theme.backgroundColor\n"
     "        border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)\n    }\n"
     "    Timer {\n        interval: 24000; running: true\n"
     f"        onTriggered: full.grabToImage(r => {{ r.saveToFile(\"{out}\"); Qt.quit(); }})\n    }}"),
])
s = open(ui + "FullView.qml").read()
s = s.replace("    Layout.minimumWidth: Kirigami.Units.gridUnit * 8\n    Layout.minimumHeight: Kirigami.Units.gridUnit * 5\n", "", 1)
open(ui + "FullView.qml", "w").write(s)

# edit: "Edit tiles" with one tile picked up with the keyboard (Space).
# Switched on late: in this rig (Xvfb, simulated values) the graphs drop to the
# minimum about 17 s after the edit mode starts – the real widget does not
if mode == "edit":
    edit("FullView.qml", [("    Timer {\n        interval: 24000; running: true\n",
         "    Timer {\n        interval: 14000; running: true\n"
         "        onTriggered: full.editing = true\n    }\n"
         "    Timer {\n        interval: 16000; running: true\n"
         "        onTriggered: { const l = full.navEntries(); full.select(l[2]); full.grabbed = full.armed; }\n    }\n"
         "    Timer {\n        interval: 24000; running: true\n")])

# wizard: show step 2 (the area choices); "cards" shows step 1 (choosing graphics cards) with two cards
if mode == "wizard":
    edit("SetupWizard.qml", [("    property int step: 0\n",
         "    property int step: 0\n    Timer { interval: 3000; running: true; onTriggered: wiz.step = 1 }\n")])

# defaults: preset layout, fast updates (graphs fill within seconds), no questions
lay = json.load(open(layout_file))
def setdef(xml, name, value):
    from xml.sax.saxutils import escape
    pat = re.compile(r'(<entry name="%s" type="\w+"><default>).*?(</default></entry>)' % name, re.S)
    if not pat.search(xml):
        sys.exit("patch.py: config entry %s not found" % name)
    return pat.sub(lambda mm: mm.group(1) + escape(value) + mm.group(2), xml, count=1)
p = pkg + "/contents/config/main.xml"
x = open(p).read()
wizard = mode in ("wizard", "cards")
for k, v in {"items": "" if wizard else lay["items"], "curveData": lay["curveData"],
             "setupDone": "false" if wizard else "true", "layoutPreset": lay["preset"],
             "layoutHash": lay["hash"], "updateInterval": "400", "historyLength": "20",
             "updateAsked": "true"}.items():
    x = setdef(x, k, v)
open(p, "w").write(x)
