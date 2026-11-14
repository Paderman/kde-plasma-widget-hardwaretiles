#!/bin/bash
# SPDX-FileCopyrightText: 2026 Paderman
# SPDX-License-Identifier: GPL-2.0-or-later
# Installs the power service for Sensor Deck (run with pkexec/sudo).
#  - group power-sensors + udev rule: read access to the RAPL energy counters only
#  - service sensordeck-power: runs as a throw-away user (DynamicUser), no root
#  - publishes /run/sensordeck-power/cpu, cpu-cores, igpu, ram (W, 1 s average, 0.1 W steps)
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Please run with pkexec or sudo."; exit 1; }
cd "$(dirname "$0")"
command -v python3 >/dev/null || { echo "python3 is missing."; exit 1; }
ls -d /sys/class/powercap/*-rapl:* >/dev/null 2>&1 || {
    echo "This processor/kernel reports no RAPL energy counters (/sys/class/powercap) – nothing to do."; exit 1; }

getent group power-sensors >/dev/null || groupadd --system power-sensors
install -Dm755 power-reader.py /usr/local/libexec/sensordeck-power-reader
install -Dm644 70-sensordeck-power.rules /etc/udev/rules.d/70-sensordeck-power.rules
install -Dm644 sensordeck-power.service /etc/systemd/system/sensordeck-power.service

udevadm control --reload
udevadm trigger --action=change --subsystem-match=powercap
udevadm settle

systemctl daemon-reload
systemctl enable sensordeck-power.service
systemctl restart sensordeck-power.service
sleep 3

for f in /sys/class/powercap/*-rapl:*/energy_uj; do
    echo "Permissions ${f#/sys/class/powercap/}: $(stat -c '%U:%G %a' "$f")"
done
echo "Service runs as: $(ps -o user= -p "$(systemctl show -p MainPID --value sensordeck-power)" 2>/dev/null || echo '?')"
if [[ -s /run/sensordeck-power/cpu ]]; then
    echo "OK – power draw:"
    for f in /run/sensordeck-power/*; do
        echo "   ${f##*/}: $(cat "$f") W"
    done
else
    echo "Service is running, but there is no value yet. Log:"
    journalctl -u sensordeck-power -n 15 --no-pager
fi
