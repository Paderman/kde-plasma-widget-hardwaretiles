#!/bin/bash
# SPDX-FileCopyrightText: 2026 Paderman
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Renders README screenshots with simulated hardware – no real sensor values,
# nothing from your desktop. Each shot runs a patched copy of the widget in
# plasmoidviewer (offscreen) with its own config/data folders, so the real
# widget and your settings are not touched.
#
#   tools/screenshots/make-screenshots.sh [shot …]
#   shot = <mode>-<lang>-<scheme>, e.g. overview-en-dark (default: all below)
# Output: docs/screenshots/<shot>.png
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$(cd "$HERE/../.." && pwd)
OUTDIR="$SRC/docs/screenshots"
WORKROOT=${SCREENSHOT_WORK:-$(mktemp -d)}
mkdir -p "$OUTDIR" "$WORKROOT"

SHOTS=("$@")
[ ${#SHOTS[@]} -gt 0 ] || SHOTS=(overview-en-dark overview-de-dark multi-en-dark multi-de-dark
                                 wizard-en-dark wizard-de-dark overview-en-light overview-de-light)

"$SRC/translate/build.sh" >/dev/null

for shot in "${SHOTS[@]}"; do
    IFS=- read -r mode lang scheme <<<"$shot"
    case $mode in overview) W=1180; H=580 ;; multi) W=1180; H=760 ;; wizard) W=620; H=720 ;;
                  *) echo "unknown mode $mode"; exit 1 ;; esac
    W_="$WORKROOT/$shot"; rm -rf "$W_"; mkdir -p "$W_/config" "$W_/data" "$W_/cache"
    cp -a "$SRC/package" "$W_/pkg"
    # optional: other tile style (glass | solid | outline), e.g. TILE_STYLE=outline
    [ -n "${TILE_STYLE:-}" ] && sed -i "s|<entry name=\"tileStyle\" type=\"String\"><default>[a-z]*</default>|<entry name=\"tileStyle\" type=\"String\"><default>$TILE_STYLE</default>|" "$W_/pkg/contents/config/main.xml"

    # tile names in the shot's language
    tr="$W_/tr.json"
    python3 - "$SRC/translate/$lang.po" "$tr" <<'PY'
import sys, json, re
m = {}
if not sys.argv[1].endswith("/en.po"):
    import polib
    for e in polib.pofile(sys.argv[1]):
        if e.msgstr and not e.obsolete: m[e.msgid] = e.msgstr
json.dump(m, open(sys.argv[2], "w"), ensure_ascii=False)
PY
    lmode=$mode; [ "$mode" = wizard ] && lmode=overview
    node "$HERE/gen-layout.js" "$W_/pkg/contents" "$HERE/Demo.js" "$lmode" "$tr" > "$W_/layout.json"
    python3 "$HERE/patch.py" "$W_/pkg" "$HERE/Demo.js" "$W_/layout.json" "$mode" "$OUTDIR/$shot.png" "$W" "$H"

    # colours: Breeze Dark / Breeze Light
    scheme_file=/usr/share/color-schemes/Breeze${scheme^}.colors
    { cat "$scheme_file"; printf '\n[General]\nColorScheme=Breeze%s\n' "${scheme^}"; } > "$W_/config/kdeglobals"
    # Plasma theme too (distributions ship their own default, e.g. Kubuntu's dark theme)
    printf '[Theme]\nname=breeze-%s\n' "$scheme" > "$W_/config/plasmarc"

    loc=en_US.UTF-8; [ "$lang" = de ] && loc=de_DE.UTF-8
    export_env=(env XDG_CONFIG_HOME="$W_/config" XDG_DATA_HOME="$W_/data" XDG_CACHE_HOME="$W_/cache"
                LANG="$loc" LC_ALL="$loc" LANGUAGE="$lang" QT_SCALE_FACTOR=1)
    "${export_env[@]}" kpackagetool6 -t Plasma/Applet -i "$W_/pkg" >/dev/null
    rm -f "$OUTDIR/$shot.png"
    # invisible X server (Xvfb) with OpenGL – the graphs need it, "offscreen" draws no charts
    "${export_env[@]}" QT_QPA_PLATFORM=xcb xvfb-run -a -s "-screen 0 1920x1200x24" \
        plasmoidviewer -a io.github.paderman.sensordeck.screenshot \
        -s "$((W + 40))x$((H + 40))" > "$W_/viewer.log" 2>&1 &
    pid=$!
    # the widget saves the PNG after ~24 s; then stop the viewer
    for _ in $(seq 1 90); do
        [ -s "$OUTDIR/$shot.png" ] && break
        kill -0 $pid 2>/dev/null || break
        sleep 1
    done
    sleep 1
    pkill -P $pid 2>/dev/null || true; kill $pid 2>/dev/null || true; wait $pid 2>/dev/null || true
    if [ -s "$OUTDIR/$shot.png" ]; then echo "✓ $shot"; else echo "✗ $shot (see $W_/viewer.log)"; fi
done
