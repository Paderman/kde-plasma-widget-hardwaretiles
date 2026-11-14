#!/bin/sh
# SPDX-FileCopyrightText: 2026 Paderman
# SPDX-License-Identifier: GPL-2.0-or-later
# Load and clock of Intel graphics built into the processor, read from sysfs
# (no root needed). ksystemstats reports these as a constant 0.
#   <idle residency ms> <current MHz> <maximum MHz>      (-1 = not available)
# The load is derived by the widget from two idle readings: the share of time
# the graphics was NOT in its power-saving sleep (RC6 / gt idle).
# Usage: igpu-info.sh <pci-address>
# Drivers: i915 (cardN/gt_*_freq_mhz, power/rc6_residency_ms) and
#          xe (tile0/gt0/freq0/*, tile0/gt0/gtidle/idle_residency_ms)

dev=$1
case $dev in ????:*) ;; *) dev=0000:$dev ;; esac
d=/sys/bus/pci/devices/$dev
[ -e "$d" ] || { echo "-1 -1 0"; exit 1; }

r() { v=$(cat "$1" 2>/dev/null); echo "${v:--1}"; }

card=""
for c in "$d"/drm/card*; do
    [ -e "$c/gt_act_freq_mhz" ] && { card=$c; break; }
done

if [ -n "$card" ]; then                 # i915
    idle=$(r "$card/power/rc6_residency_ms")
    act=$(r "$card/gt_act_freq_mhz")
    max=$(r "$card/gt_RP0_freq_mhz")
    [ "$max" -gt 0 ] 2>/dev/null || max=$(r "$card/gt_max_freq_mhz")
else                                    # xe
    g=$d/tile0/gt0
    idle=$(r "$g/gtidle/idle_residency_ms")
    act=$(r "$g/freq0/act_freq")
    max=$(r "$g/freq0/rp0_freq")
    [ "$max" -gt 0 ] 2>/dev/null || max=$(r "$g/freq0/max_freq")
fi
echo "$idle $act $max"
