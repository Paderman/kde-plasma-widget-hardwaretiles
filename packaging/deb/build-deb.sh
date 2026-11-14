#!/bin/sh
# SPDX-FileCopyrightText: 2026 Paderman
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Builds dist/plasma-widget-sensordeck_<version>_all.deb (needs dpkg-deb, fakeroot, gettext).
set -eu
SRC=$(cd "$(dirname "$0")/../.." && pwd)
VERSION=$("$SRC/tools/check-version.sh")
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
ROOT="$WORK/root"
"$SRC/packaging/stage.sh" "$ROOT" >/dev/null

# Debian keeps the licence in the copyright file, not in /usr/share/licenses
rm -rf "$ROOT/usr/share/licenses"
cat > "$ROOT/usr/share/doc/sensordeck/copyright" <<EOT
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: Sensor Deck
Source: https://github.com/Paderman/sensordeck

Files: *
Copyright: 2026 Paderman
License: GPL-2.0-or-later
 On Debian systems, the complete text of the GNU General Public License
 version 2 can be found in /usr/share/common-licenses/GPL-2.
EOT
chmod 644 "$ROOT/usr/share/doc/sensordeck/copyright"

mkdir -p "$ROOT/DEBIAN"
SIZE=$(du -sk "$ROOT/usr" | cut -f1)
cat > "$ROOT/DEBIAN/control" <<EOT
Package: plasma-widget-sensordeck
Version: $VERSION
Architecture: all
Maintainer: Paderman <https://github.com/Paderman>
Installed-Size: $SIZE
Depends: plasma-workspace (>= 4:6.0) | plasma-workspace (>= 6.0)
Recommends: lm-sensors, pciutils
Suggests: nvidia-smi
Section: kde
Priority: optional
Homepage: https://github.com/Paderman/sensordeck
Description: GPU & system monitor widget for KDE Plasma 6
 Sensor Deck shows the graphics card in detail – VRAM temperature, throttling
 reason, PCIe link and a self-learning fan curve – plus CPU, memory, SSDs,
 mainboard fans and network, as rings, bars and graphs. Includes a setup
 wizard, desktop notifications for critical values and plain-language
 tooltips.
EOT

mkdir -p "$SRC/dist"
OUT="$SRC/dist/plasma-widget-sensordeck_${VERSION}_all.deb"
fakeroot dpkg-deb --build --root-owner-group -Zxz "$ROOT" "$OUT" >/dev/null
echo "Built $OUT"
