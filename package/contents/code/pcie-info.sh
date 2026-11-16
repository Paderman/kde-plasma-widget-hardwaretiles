#!/bin/sh
# SPDX-FileCopyrightText: 2026 Paderman
# SPDX-License-Identifier: GPL-2.0-or-later
# Prints the PCIe link of a graphics card, read from sysfs:
#   <device> <cur GT/s> <cur width or "-" = no PCIe> <card max GT/s> <card max width> <port> <slot max GT/s> <slot max width>
#   followed by lspci name lines (Vendor/Device/SVendor), if lspci is available
# Usage: pcie-info.sh [pci-address]   (empty = first graphics card with an active link)
#
# The relevant link is the one at the root port (CPU/chipset slot). AMD cards
# contain an internal PCIe switch, so the GPU function itself would only report
# the card-internal link - we therefore use the device directly below the root port.

dev=$1
if [ -n "$dev" ]; then
    case $dev in ????:*) ;; *) dev=0000:$dev ;; esac
    dev=/sys/bus/pci/devices/$dev
    [ -e "$dev" ] || exit 1
else
    first=""
    for d in /sys/bus/pci/devices/*; do
        case $(cat "$d/class" 2>/dev/null) in 0x0300*|0x0302*) ;; *) continue ;; esac
        [ -z "$first" ] && first=$d
        w=$(cat "$d/current_link_width" 2>/dev/null)
        if [ "${w:-0}" -gt 0 ] 2>/dev/null; then dev=$d; break; fi
    done
    [ -n "$dev" ] || dev=$first
    [ -n "$dev" ] || exit 1
fi

real=$(readlink -f "$dev")
# path: /sys/devices/pci0000:00/<root port>/<card top>/.../<gpu>
rest=${real#*/pci????:??/}
port=${rest%%/*}
rest2=${rest#*/}
top=${rest2%%/*}
[ "$rest2" = "$rest" ] && top=$port   # gpu directly on the root complex (integrated)
P=/sys/bus/pci/devices/$port
T=/sys/bus/pci/devices/$top

r() { v=$(cat "$1/$2" 2>/dev/null); v=${v%% GT/s*}; echo "${v:-0}"; }
# "-" instead of a width: the device has no PCIe link at all (chipset graphics
# behind a plain PCI bridge, e.g. Radeon HD 4200 in AMD 785G/RS880 boards)
cw=$(r "$T" current_link_width)
[ -e "$T/current_link_width" ] || cw=-

echo "$(basename "$real") $(r "$T" current_link_speed) $cw" \
     "$(r "$T" max_link_speed) $(r "$T" max_link_width)" \
     "$port $(r "$P" max_link_speed) $(r "$P" max_link_width)"

# following lines: device names from the PCI ID database ("Vendor:\t…", "Device:\t…", "SVendor:\t…")
if command -v lspci >/dev/null 2>&1; then
    lspci -vmm -s "$(basename "$real")" 2>/dev/null | grep -E '^(Vendor|Device|SVendor):'
fi
