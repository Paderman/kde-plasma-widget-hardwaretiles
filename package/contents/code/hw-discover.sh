#!/bin/sh
# SPDX-FileCopyrightText: 2026 Paderman
# SPDX-License-Identifier: GPL-2.0-or-later
# Hardware discovery for Hardware Tiles. Tab separated lines:
#   GPU   <pci addr> <vendor id> <driver> <drm card no|-> <nvidia-smi index|-1> <Vendor> <Device> <SVendor>
#   NVME  <pci addr> <model>
#   GDDR6 <1 if /run/gddr6/vram exists, else 0>
#   POWER <1 if the power service publishes /run/hardwaretiles-power/cpu, else 0>
#   NVFANS <nvidia-smi index> <number of fans whose speed the driver reports>
#   SENSORS            (everything after this line is `sensors -j` output)

T=$(printf '\t')

# nvidia-smi index per PCI address
nvmap=""
if command -v nvidia-smi >/dev/null 2>&1; then
    nvmap=$(nvidia-smi --query-gpu=index,pci.bus_id --format=csv,noheader 2>/dev/null)
fi

for d in /sys/bus/pci/devices/*; do
    case $(cat "$d/class" 2>/dev/null) in 0x0300*|0x0302*|0x0380*) ;; *) continue ;; esac
    addr=$(basename "$d")
    vid=$(cat "$d/vendor" 2>/dev/null)
    drv=-
    [ -e "$d/driver" ] && drv=$(basename "$(readlink -f "$d/driver")")
    card=-
    for c in "$d"/drm/card*; do
        [ -e "$c" ] || continue
        card=${c##*/card}
        break
    done
    nvi=-1
    if [ -n "$nvmap" ]; then
        # nvidia-smi prints 00000000:02:00.0 – compare the last 12 chars (0000:02:00.0)
        nvi=$(printf '%s\n' "$nvmap" | while IFS=', ' read -r i bus; do
            b=$(printf '%s' "$bus" | tr 'A-F' 'a-f')
            case $b in *"${addr#0000:}") echo "$i"; break ;; esac
        done)
        [ -n "$nvi" ] || nvi=-1
    fi
    vend=""; dev=""; svend=""
    if command -v lspci >/dev/null 2>&1; then
        info=$(lspci -vmm -s "$addr" 2>/dev/null)
        vend=$(printf '%s\n' "$info" | sed -n 's/^Vendor:[[:space:]]*//p' | head -1)
        dev=$(printf '%s\n' "$info" | sed -n 's/^Device:[[:space:]]*//p' | head -1)
        svend=$(printf '%s\n' "$info" | sed -n 's/^SVendor:[[:space:]]*//p' | head -1)
    fi
    echo "GPU$T$addr$T$vid$T$drv$T$card$T$nvi$T$vend$T$dev$T$svend"
done

for n in /sys/class/nvme/nvme*; do
    [ -e "$n/device" ] || continue
    addr=$(basename "$(readlink -f "$n/device")")
    model=$(sed 's/[[:space:]]*$//' "$n/model" 2>/dev/null)
    echo "NVME$T$addr$T$model"
done

if [ -e /run/gddr6/vram ]; then echo "GDDR6${T}1"; else echo "GDDR6${T}0"; fi
if [ -e /run/hardwaretiles-power/cpu ]; then echo "POWER${T}1"; else echo "POWER${T}0"; fi
# measured fan speeds of NVIDIA cards (driver library, needs python3)
if [ -n "$nvmap" ] && command -v python3 >/dev/null 2>&1; then
    python3 -I "$(dirname "$0")/nvml-fans.py" --probe 2>/dev/null
fi

# Fallback when the `sensors` program (package lm-sensors / lm_sensors) is missing:
# read /sys/class/hwmon directly and print the same JSON shape as `sensors -j`.
# Chip names follow libsensors (which ksystemstats uses): <name>-isa-<addr> for
# platform devices, <name>-pci-<addr> for PCI devices. Other buses are skipped.
. "$(dirname "$0")/distro.sh"

json_esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
sysfs_sensors() {
    printf '{'
    firstchip=1
    for h in /sys/class/hwmon/hwmon*; do
        [ -r "$h/name" ] || continue
        name=$(cat "$h/name")
        dev=$(readlink -f "$h/device" 2>/dev/null)
        [ -n "$dev" ] || continue
        sub=""
        [ -e "$dev/subsystem" ] && sub=$(basename "$(readlink -f "$dev/subsystem")")
        base=${dev##*/}
        case $sub in
            platform|isa)
                a=0
                case $base in *.*) a=${base##*.}; case $a in ''|*[!0-9]*) a=0 ;; esac ;; esac
                chip=$(printf '%s-isa-%04x' "$name" "$a") ;;
            pci)
                IFS=':.' read -r pd pb ps pf <<EOT
$base
EOT
                a=$(( ($(printf %d "0x$pd") << 16) + ($(printf %d "0x$pb") << 8) + ($(printf %d "0x$ps") << 3) + $(printf %d "0x$pf") ))
                chip=$(printf '%s-pci-%04x' "$name" "$a") ;;
            *) continue ;;
        esac
        dir=$h
        # older drivers keep the attributes on the device instead of the hwmon node
        set -- "$dir"/fan*_input "$dir"/temp*_input
        case "$*" in *"*_input"*" "*"*_input"*) dir=$dev ;; esac
        feats=""
        for f in "$dir"/fan*_input "$dir"/temp*_input; do
            [ -r "$f" ] || continue
            v=$(cat "$f" 2>/dev/null) || continue
            case $v in ''|*[!0-9-]*) continue ;; esac
            feat=${f##*/}; feat=${feat%_input}
            label=$feat
            [ -r "$dir/${feat}_label" ] && label=$(cat "$dir/${feat}_label")
            case $feat in temp*) v=$(awk -v x="$v" 'BEGIN { printf "%.3f", x / 1000 }') ;; esac
            feats="$feats${feats:+,}\"$(json_esc "$label")\":{\"${feat}_input\":$v}"
        done
        [ -n "$feats" ] || continue
        [ $firstchip -eq 1 ] || printf ','
        firstchip=0
        printf '"%s":{"Adapter":"sysfs",%s}' "$(json_esc "$chip")" "$feats"
    done
    printf '}\n'
}

detect_distro
echo "DISTRO$T$PM$T$PKG$T$DISTRO"

if command -v sensors >/dev/null 2>&1 && [ -z "$HARDWARETILES_SYSFS" ]; then
    echo "LMTOOL${T}1"
    echo "SENSORS"
    sensors -j 2>/dev/null
else
    echo "LMTOOL${T}0"
    echo "SENSORS"
    sysfs_sensors
fi
exit 0
