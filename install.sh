#!/bin/bash
# SPDX-FileCopyrightText: 2026 Paderman
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Installs or updates the Hardware Tiles plasmoid for the current user.
set -euo pipefail
cd "$(dirname "$0")"
ID=$(sed -n 's/.*"Id": *"\([^"]*\)".*/\1/p' package/metadata.json)
tools/check-version.sh >/dev/null

# translations (package/contents/locale) – needs gettext's msgfmt
if command -v msgfmt >/dev/null; then
    ./translate/build.sh
else
    echo "Note: msgfmt (gettext) not found – installing without translations (English only)."
fi

if kpackagetool6 -t Plasma/Applet -s "$ID" >/dev/null 2>&1; then
    kpackagetool6 -t Plasma/Applet -u package
else
    kpackagetool6 -t Plasma/Applet -i package
fi
echo "Done. Add the widget: right-click the desktop/panel → Add Widgets → “Hardware Tiles”."
echo "After an update you may need to reload Plasma: systemctl --user restart plasma-plasmashell"
