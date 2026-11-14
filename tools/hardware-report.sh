#!/bin/sh
# SPDX-FileCopyrightText: 2026 Paderman
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Collects what Sensor Deck needs to support your hardware and writes it to
# sensordeck-hardware-report.md – attach that file to a "Hardware report" issue:
# https://github.com/Paderman/kde-plasma-widget-sensordeck/issues/new?template=hardware_report.yml
#
# Contains: distribution, kernel and Plasma version, graphics cards, mainboard
# name, sensor chips and their readings. No user name, host name or serial numbers.

export LC_ALL=C LANGUAGE=C
DIR=$(cd "$(dirname "$0")" && pwd)
# source checkout, user install or system-wide package
for PKGDIR in "$DIR/../package" "$HOME/.local/share/plasma/plasmoids/io.github.paderman.sensordeck" \
              /usr/share/plasma/plasmoids/io.github.paderman.sensordeck; do
    [ -r "$PKGDIR/contents/code/hw-discover.sh" ] && break
done
DISCOVER="$PKGDIR/contents/code/hw-discover.sh"
OUT=${1:-sensordeck-hardware-report.md}

section() { printf '\n<details><summary>%s</summary>\n\n```\n' "$1"; }
endsection() { printf '```\n</details>\n'; }

{
    echo "## Sensor Deck hardware report"
    echo
    distro=$(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME")
    echo "- Distribution: ${distro:-unknown}"
    echo "- Kernel: $(uname -r)"
    echo "- Plasma: $(plasmashell --version 2>/dev/null | sed 's/^plasmashell //')"
    # only the board name – vendor fields can hold serial-like strings
    echo "- Mainboard: $(cat /sys/class/dmi/id/board_name 2>/dev/null || echo unknown)"
    # laptops (chassis types 8, 9, 10, 14, 31): the model name tells more than the board
    case $(cat /sys/class/dmi/id/chassis_type 2>/dev/null) in
        8|9|10|14|31) echo "- Laptop: $(cat /sys/class/dmi/id/product_name 2>/dev/null)" ;;
    esac
    echo "- Sensor Deck: $(sed -n 's/.*"Version": *"\([^"]*\)".*/\1/p' "$PKGDIR/metadata.json" 2>/dev/null | head -1)"
    command -v sensors >/dev/null 2>&1 && echo "- lm-sensors: installed" || echo "- lm-sensors: NOT installed"
    command -v nvidia-smi >/dev/null 2>&1 && echo "- nvidia-smi: $(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1)"

    section "Graphics cards (lspci)"
    if command -v lspci >/dev/null 2>&1; then
        lspci -nnk 2>/dev/null | grep -A3 -E "VGA|3D controller|Display controller"
    else
        echo "lspci not available"
    fi
    endsection

    section "Loaded sensor drivers (hwmon)"
    for h in /sys/class/hwmon/hwmon*; do
        [ -r "$h/name" ] || continue
        printf '%s  %s\n' "$(cat "$h/name")" "$(readlink -f "$h/device" 2>/dev/null | sed 's|^/sys/devices/||')"
    done
    endsection

    section "Sensor Deck hardware detection (hw-discover.sh)"
    if [ -r "$DISCOVER" ]; then sh "$DISCOVER" 2>&1; else echo "hw-discover.sh not found"; fi
    endsection

    section "Plasma sensors (kstatsviewer --list, filtered)"
    if command -v kstatsviewer >/dev/null 2>&1; then
        timeout 20 kstatsviewer --list 2>/dev/null | grep -E '^(lmsensors/|gpu/|cpu/all/)' | sort
    else
        echo "kstatsviewer not available"
    fi
    endsection

    printf '\n<details><summary>Kernel modules for sensors</summary>\n\n```\n'
    lsmod 2>/dev/null | grep -E '^(nct|it87|it8|f71|w83|asus|gigabyte|dell_smm|thinkpad|k10temp|zenpower|coretemp|amdgpu|nvidia|i915|xe|drivetemp|sch5)' | awk '{print $1}'
    endsection
} > "$OUT"

echo "Report written to: $(readlink -f "$OUT")"
echo "Please check it and attach it to a new issue:"
echo "https://github.com/Paderman/kde-plasma-widget-sensordeck/issues/new?template=hardware_report.yml"
