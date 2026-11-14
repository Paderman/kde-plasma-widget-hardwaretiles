#!/bin/bash
# SPDX-FileCopyrightText: 2026 Paderman
# SPDX-License-Identifier: GPL-2.0-or-later
# Installs the VRAM temperature service for Sensor Deck (run with pkexec/sudo).
#  - group gpu-sensors + udev rule: read access to the NVIDIA card's resource0 only
#  - service gddr6-vram: runs as a throw-away user (DynamicUser), no root, no /dev/mem
#  - publishes /run/gddr6/vram, vram_all, vram-<pci address>
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Please run with pkexec or sudo."; exit 1; }
cd "$(dirname "$0")"
command -v python3 >/dev/null || { echo "python3 is missing."; exit 1; }

getent group gpu-sensors >/dev/null || groupadd --system gpu-sensors
install -Dm755 vram-reader.py /usr/local/libexec/sensordeck-vram-reader
install -Dm644 70-sensordeck-vram.rules /etc/udev/rules.d/70-sensordeck-vram.rules
install -Dm644 gddr6-vram.service /etc/systemd/system/gddr6-vram.service
rm -f /usr/local/libexec/gddr6-vram-feeder          # old root feeder (gddr6 + /dev/mem)

udevadm control --reload
udevadm trigger --action=change --subsystem-match=pci --attr-match=vendor=0x10de
udevadm settle

systemctl daemon-reload
systemctl enable gddr6-vram.service
# restart: "enable --now" would keep an already running (old) service
systemctl restart gddr6-vram.service
sleep 3

for f in /sys/bus/pci/devices/*/resource0; do
    d=${f%/resource0}
    [[ $(cat "$d/vendor") == 0x10de && $(cat "$d/class") == 0x03* ]] && echo "Permissions ${d##*/}/resource0: $(stat -c '%U:%G %a' "$f")"
done
echo "Service runs as: $(ps -o user= -p "$(systemctl show -p MainPID --value gddr6-vram)" 2>/dev/null || echo '?')"
if [[ -s /run/gddr6/vram ]]; then
    echo "OK – VRAM temperature: $(cat /run/gddr6/vram) °C"
    for f in /run/gddr6/vram-*; do
        [[ -e $f ]] && echo "   ${f#/run/gddr6/vram-}: $(cat "$f") °C"
    done
else
    echo "Service is running, but there is no value yet. Log:"
    journalctl -u gddr6-vram -n 15 --no-pager
fi
