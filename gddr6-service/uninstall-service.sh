#!/bin/bash
# SPDX-FileCopyrightText: 2026 Paderman
# SPDX-License-Identifier: GPL-2.0-or-later
# Removes the VRAM temperature service, udev rule and group (run with pkexec/sudo).
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Please run with pkexec or sudo."; exit 1; }
systemctl disable --now gddr6-vram.service || true
rm -f /etc/systemd/system/gddr6-vram.service /usr/local/libexec/sensordeck-vram-reader \
      /usr/local/libexec/gddr6-vram-feeder /etc/udev/rules.d/70-sensordeck-vram.rules
systemctl daemon-reload
udevadm control --reload
# back to the kernel default (root only)
for f in /sys/bus/pci/devices/*/resource0; do
    d=${f%/resource0}
    [[ $(cat "$d/vendor") == 0x10de && $(cat "$d/class") == 0x03* ]] && chown root:root "$f" && chmod 0600 "$f"
done
getent group gpu-sensors >/dev/null && groupdel gpu-sensors || true
echo "Removed."
