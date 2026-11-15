#!/bin/sh
# SPDX-FileCopyrightText: 2026 Paderman
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Started by the widget through `pkexec` (KDE asks for the administrator password):
#   1. installs lm-sensors with the distribution's package manager (if missing)
#   2. runs `sensors-detect --auto` to find the mainboard's sensor chip
#   3. loads the found kernel modules now and on every boot
#      (/etc/modules-load.d/hardwaretiles-sensors.conf)
# Prints machine-readable lines for the widget: STEP …, MODULES …, RESULT <code>
#   RESULT ok | nopm | installfailed | nomodules | notroot
export LC_ALL=C PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
. "$(dirname "$0")/distro.sh"

[ "$(id -u)" = 0 ] || { echo "RESULT notroot"; exit 1; }

if ! command -v sensors-detect >/dev/null 2>&1; then
    detect_distro
    echo "STEP install $PM $PKG"
    case $PM in
        apt)
            export DEBIAN_FRONTEND=noninteractive
            apt-get install -y "$PKG" || { apt-get update && apt-get install -y "$PKG"; } ;;
        dnf)    dnf install -y "$PKG" ;;
        zypper) zypper --non-interactive install "$PKG" ;;
        pacman) pacman -S --needed --noconfirm "$PKG" ;;
        *)      echo "RESULT nopm"; exit 2 ;;
    esac
    command -v sensors-detect >/dev/null 2>&1 || { echo "RESULT installfailed"; exit 3; }
fi

echo "STEP detect"
out=$(yes "" | sensors-detect --auto 2>&1)
# the module list is printed between two "#----cut here----" lines
mods=$(printf '%s\n' "$out" | awk '/^#----cut here----/ { n++; next } n == 1 && !/^#/ && NF { print $1 }' | sort -u)
echo "MODULES" $mods

loaded=""
for m in $mods; do
    modprobe "$m" 2>/dev/null && loaded="$loaded $m"
done
if [ -n "$loaded" ]; then
    {
        echo "# Written by Hardware Tiles: mainboard sensor drivers found by sensors-detect"
        for m in $loaded; do echo "$m"; done
    } > /etc/modules-load.d/hardwaretiles-sensors.conf
    rm -f /etc/modules-load.d/sensordeck-sensors.conf   # name before 1.1.0 (Sensor Deck)
    echo "RESULT ok"
else
    echo "RESULT nomodules"
fi
exit 0
