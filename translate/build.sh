#!/bin/bash
# SPDX-FileCopyrightText: 2026 Paderman
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Compiles translate/<lang>.po into package/contents/locale/<lang>/LC_MESSAGES/,
# where Plasma finds them. Needs gettext (msgfmt).
set -euo pipefail
cd "$(dirname "$0")"

domain="plasma_applet_$(sed -n 's/.*"Id": *"\([^"]*\)".*/\1/p' ../package/metadata.json)"
rm -rf ../package/contents/locale
for po in *.po; do
    [ -e "$po" ] || continue
    lang="${po%.po}"
    mkdir -p "../package/contents/locale/$lang/LC_MESSAGES"
    msgfmt --check -o "../package/contents/locale/$lang/LC_MESSAGES/$domain.mo" "$po"
done
echo "Built $(ls *.po 2>/dev/null | wc -l) translations for $domain"
