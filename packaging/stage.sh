#!/bin/sh
# SPDX-FileCopyrightText: 2026 Paderman
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Copies everything a system-wide install needs into a staging root:
#   stage.sh <destdir>
# Used by the .deb build, the RPM spec and the Arch PKGBUILD.
set -eu
DEST=${1:?usage: stage.sh <destdir>}
SRC=$(cd "$(dirname "$0")/.." && pwd)
ID=$(sed -n 's/.*"Id": *"\([^"]*\)".*/\1/p' "$SRC/package/metadata.json")

"$SRC/tools/check-version.sh" >/dev/null
"$SRC/translate/build.sh" >/dev/null

PLASMOID="$DEST/usr/share/plasma/plasmoids/$ID"
mkdir -p "$PLASMOID" "$DEST/usr/share/sensordeck" "$DEST/usr/share/doc/sensordeck" "$DEST/usr/share/licenses/sensordeck"
cp -r "$SRC/package/." "$PLASMOID/"
# optional VRAM temperature service (NVIDIA) – installed by the user on demand
cp -r "$SRC/gddr6-service" "$DEST/usr/share/sensordeck/"
# optional power service (processor / built-in graphics) – installed by the user on demand
cp -r "$SRC/power-service" "$DEST/usr/share/sensordeck/"
cp "$SRC/tools/hardware-report.sh" "$DEST/usr/share/sensordeck/"
cp "$SRC/README.md" "$SRC/README.de.md" "$DEST/usr/share/doc/sensordeck/"
cp "$SRC/LICENSE" "$DEST/usr/share/licenses/sensordeck/"
find "$DEST" -name '__pycache__' -prune -exec rm -rf {} +
find "$DEST" -type d -exec chmod 755 {} +
find "$DEST" -type f -exec chmod 644 {} +
find "$DEST" -type f -name '*.sh' -exec chmod 755 {} +
[ -f "$DEST/usr/share/sensordeck/gddr6-service/vram-reader.py" ] && chmod 755 "$DEST/usr/share/sensordeck/gddr6-service/vram-reader.py"
[ -f "$DEST/usr/share/sensordeck/power-service/power-reader.py" ] && chmod 755 "$DEST/usr/share/sensordeck/power-service/power-reader.py"
echo "$DEST"
