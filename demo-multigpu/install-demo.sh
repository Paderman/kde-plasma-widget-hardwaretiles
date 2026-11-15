#!/bin/bash
# SPDX-FileCopyrightText: 2026 Paderman
# SPDX-License-Identifier: GPL-2.0-or-later
# Builds and installs "Hardware Tiles (Multi-GPU-Demo)": the normal widget plus a
# simulated second graphics card. Does not touch the real Hardware Tiles widget.
set -euo pipefail
cd "$(dirname "$0")"
ID=io.github.paderman.hardwaretiles.multigpudemo
BUILD=build/package
rm -rf build && mkdir -p build && cp -a ../package "$BUILD"
C=$BUILD/contents

mv "$C/code/hw-discover.sh" "$C/code/hw-real.sh"
cp hw-discover.sh fake-nvidia-smi.sh "$C/code/"

python3 - "$C" "$ID" <<'PY'
import sys, json, re
c, pid = sys.argv[1], sys.argv[2]
m = json.load(open(c + "/../metadata.json"))
m["KPlugin"]["Id"] = pid
m["KPlugin"]["Name"] = "Hardware Tiles (Multi-GPU-Demo)"
m["KPlugin"]["Description"] = "Hardware Tiles with a simulated second graphics card"
m["KPlugin"].pop("Description[de]", None)
json.dump(m, open(c + "/../metadata.json", "w"), indent=4, ensure_ascii=False)

p = c + "/ui/NvidiaProvider.qml"; s = open(p).read()
s = s.replace('readonly property string cmd: "nvidia-smi -i "',
              'readonly property string fake: Qt.resolvedUrl("../code/fake-nvidia-smi.sh").toString().replace(/^file:\\/\\//, "")\n'
              '    readonly property string cmd: "sh \'" + fake + "\' -i "')
open(p, "w").write(s)

# VRAM temperature of the simulated card: real value minus 9 °C
p = c + "/ui/Hardware.js"; s = open(p).read()
s = s.replace('var VRAM_CMD_STRICT = "cat /run/gddr6/vram-{gpuaddr}";',
              'var VRAM_CMD_STRICT = "cat /run/gddr6/vram-{gpuaddr} 2>/dev/null || awk \'{print $1-9}\' /run/gddr6/vram";')
open(p, "w").write(s)
PY
grep -q fake-nvidia-smi "$C/ui/NvidiaProvider.qml"

LAYOUT=$(node gen-layout.js "$C")
python3 - "$C/config/main.xml" "$LAYOUT" <<'PY'
import sys, html
p, layout = sys.argv[1], sys.argv[2]
s = open(p).read()
s = s.replace('<entry name="items" type="String"><default></default></entry>',
              '<entry name="items" type="String"><default>' + html.escape(layout) + '</default></entry>')
s = s.replace('<entry name="setupDone" type="Bool"><default>false</default></entry>',
              '<entry name="setupDone" type="Bool"><default>true</default></entry>')
# demo: automatic columns
s = s.replace('<entry name="columns" type="Int"><default>3</default></entry>',
              '<entry name="columns" type="Int"><default>0</default></entry>')
open(p, "w").write(s)
PY

if kpackagetool6 -t Plasma/Applet -s $ID >/dev/null 2>&1; then
    kpackagetool6 -t Plasma/Applet -u "$BUILD"
else
    kpackagetool6 -t Plasma/Applet -i "$BUILD"
fi
echo "Demo installed: Add Widgets → “Hardware Tiles (Multi-GPU-Demo)”."
