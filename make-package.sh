#!/bin/bash
# SPDX-FileCopyrightText: 2026 Paderman
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Builds sensordeck-<version>.plasmoid (a zip of package/ with translations),
# e.g. for the KDE Store. Needs gettext (msgfmt) and zip.
set -euo pipefail
cd "$(dirname "$0")"
./translate/build.sh
version=$(tools/check-version.sh)
mkdir -p dist
out="dist/sensordeck-$version.plasmoid"
rm -f "$out"
(cd package && zip -qr "../$out" . -x '*/__pycache__/*')
echo "Built $out"
