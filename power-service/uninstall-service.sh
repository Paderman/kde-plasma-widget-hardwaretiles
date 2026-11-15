#!/bin/bash
# SPDX-FileCopyrightText: 2026 Paderman
# SPDX-License-Identifier: GPL-2.0-or-later
# Removes the power service, udev rule and group (run with pkexec/sudo).
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Please run with pkexec or sudo."; exit 1; }
systemctl disable --now hardwaretiles-power.service || true
rm -f /etc/systemd/system/hardwaretiles-power.service /usr/local/libexec/hardwaretiles-power-reader \
      /etc/udev/rules.d/70-hardwaretiles-power.rules
# names before 1.1.0 (Sensor Deck)
systemctl disable --now sensordeck-power.service 2>/dev/null || true
rm -f /etc/systemd/system/sensordeck-power.service /usr/local/libexec/sensordeck-power-reader \
      /etc/udev/rules.d/70-sensordeck-power.rules
systemctl daemon-reload
udevadm control --reload
# back to the kernel default (root only)
for f in /sys/class/powercap/*-rapl:*/energy_uj; do
    [[ -e $f ]] && chown root:root "$f" && chmod 0400 "$f"
done
getent group power-sensors >/dev/null && groupdel power-sensors || true
echo "Removed."
