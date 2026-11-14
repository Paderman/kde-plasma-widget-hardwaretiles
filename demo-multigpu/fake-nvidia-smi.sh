#!/bin/sh
# SPDX-FileCopyrightText: 2026 Paderman
# SPDX-License-Identifier: GPL-2.0-or-later
# Demo: real GPU as index 0 + a simulated "RTX 3060 Ti" as index 1, derived live
# from the real values (cooler, less load, smaller VRAM/power limit, own wave pattern).
want=""; query=""; rest=""
for a in "$@"; do :; done
while [ $# -gt 0 ]; do
    case $1 in
        -i) want=$2; shift 2 ;;
        --query-gpu=*) query=${1#--query-gpu=}; shift ;;
        *) rest="$rest $1"; shift ;;
    esac
done
real=$(nvidia-smi -i 0 --query-gpu="$query" $rest) || exit $?
case ",$want," in *,0,*|,,) printf '%s\n' "$real" ;; esac
case ",$want," in
*,1,*)
    printf '%s\n' "$real" | head -1 | awk -F', ' -v keys="$query" -v t="$(date +%s)" '
    BEGIN { OFS = ", "; n = split(keys, k, ","); w = (sin(t / 9) + 1) / 2; w2 = (sin(t / 23 + 1) + 1) / 2 }
    {
        for (i = 1; i <= n; i++) {
            v = $i
            if (k[i] == "index") v = 1
            else if (k[i] == "pci.bus_id") v = "00000000:09:00.0"
            else if (k[i] == "name") v = "NVIDIA GeForce RTX 3060 Ti"
            else if (k[i] == "temperature.gpu") v = sprintf("%.0f", 38 + 22 * w2 + (v - 40) * 0.2)
            else if (k[i] == "utilization.gpu") v = sprintf("%.0f", 15 + 70 * w)
            else if (k[i] == "utilization.memory") v = sprintf("%.0f", 10 + 40 * w)
            else if (k[i] == "fan.speed") v = sprintf("%.0f", 30 + 45 * w2)
            else if (k[i] == "power.draw") v = sprintf("%.1f", 25 + 160 * w)
            else if (k[i] == "enforced.power.limit") v = "200.00"
            else if (k[i] == "power.max_limit") v = "220.00"
            else if (k[i] == "memory.total") v = "8192"
            else if (k[i] == "memory.used") v = sprintf("%.0f", 900 + 5000 * w2)
            else if (k[i] == "memory.free") v = sprintf("%.0f", 8192 - 900 - 5000 * w2)
            else if (k[i] == "clocks.gr") v = sprintf("%.0f", 400 + 1400 * w)
            else if (k[i] == "clocks.max.gr") v = "2100"
            else if (k[i] == "clocks.mem") v = "7000"
            else if (k[i] == "clocks.max.mem") v = "7001"
            else if (k[i] == "pstate") v = (w > 0.3 ? "P2" : "P8")
            out = (i == 1 ? v : out OFS v)
        }
        print out
    }' ;;
esac
