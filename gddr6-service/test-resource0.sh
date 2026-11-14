#!/bin/bash
# SPDX-FileCopyrightText: 2026 Paderman
# SPDX-License-Identifier: GPL-2.0-or-later
# One-off test (run with pkexec): can the VRAM temperature be read via
# /sys/bus/pci/devices/<addr>/resource0 – as root and as a normal user that
# only got read permission on that file? Permissions are restored afterwards.
set -u
[[ $EUID -eq 0 ]] || { echo "Please run with pkexec."; exit 1; }
cd "$(dirname "$0")"
READER="$PWD/vram-reader.py"
USER_NAME=$(id -nu "${PKEXEC_UID:-${SUDO_UID:-1000}}")

echo "== Cards"
python3 -I "$READER" --list

for addr in $(python3 -I "$READER" --once | awk '{print $1}'); do
    RES=/sys/bus/pci/devices/$addr/resource0
    echo
    echo "== $addr"
    echo "Reference (gddr6 service): $(cat /run/gddr6/vram-$addr 2>/dev/null || cat /run/gddr6/vram) °C"
    echo "root via resource0:         $(python3 -I "$READER" --once "$addr" | awk '{print $2}') °C"

    orig=$(stat -c '%U:%G %a' "$RES")
    echo "Permissions before: $orig"
    printf 'Nutzer %s ohne Rechte:  ' "$USER_NAME"
    runuser -u "$USER_NAME" -- python3 -I "$READER" --once "$addr" 2>&1 | tail -1

    # temporarily: group of the user may read
    restore() { chown "${orig%% *}" "$RES"; chmod "${orig##* }" "$RES"; }
    trap restore EXIT
    chgrp "$(id -gn "$USER_NAME")" "$RES" && chmod 0640 "$RES"
    printf 'Nutzer %s mit Leserecht: ' "$USER_NAME"
    runuser -u "$USER_NAME" -- python3 -I "$READER" --once "$addr" 2>&1 | tail -1
    restore; trap - EXIT
    echo "Permissions after: $(stat -c '%U:%G %a' "$RES")"
done
