#!/bin/sh
# SPDX-FileCopyrightText: 2026 Paderman
# SPDX-License-Identifier: GPL-2.0-or-later
# Per-program statistics of a graphics card from /proc/<pid>/fdinfo (DRM client
# usage stats, like nvtop) – no root needed, but only programs of this user are
# visible. Prints one line per DRM client (several open files of the same
# client are counted once):
#   N <client id> <engine> <busy ns>                    (i915: drm-engine-*)
#   X <client id> <engine> <cycles> <total cycles>      (xe: drm-cycles-* / drm-total-cycles-*)
#   M <client id> <resident bytes>
#   P <client id> <pid> <program name>
# Usage: igpu-clients.sh <pci-address>

dev=$1
case $dev in ????:*) ;; *) dev=0000:$dev ;; esac

files=$(find /proc/[0-9]*/fd -maxdepth 1 -lname '/dev/dri/*' 2>/dev/null \
        | sed 's|/fd/|/fdinfo/|')
[ -n "$files" ] || exit 0

# shellcheck disable=SC2086
awk -v dev="$dev" '
function flush() {
    if (pdev == dev && id != "" && !(id in seen)) {
        seen[id] = 1
        for (e in ns) print "N", id, e, ns[e]
        for (e in cyc) print "X", id, e, cyc[e], tot[e] + 0
        print "M", id, mem
        split(FILENAME_prev, p, "/")
        comm = ""
        if ((getline comm < ("/proc/" p[3] "/comm")) > 0) close("/proc/" p[3] "/comm")
        gsub(/ /, "_", comm)
        print "P", id, p[3], comm
    }
    pdev = ""; id = ""; mem = 0
    delete ns; delete cyc; delete tot
}
FNR == 1 { if (NR > 1) flush(); FILENAME_prev = FILENAME }
/^drm-pdev:/       { pdev = $2 }
/^drm-client-id:/  { id = $2 }
/^drm-engine-[a-z-]+:/ && $3 == "ns" { e = $1; sub(/^drm-engine-/, "", e); sub(/:$/, "", e); ns[e] = $2 }
/^drm-cycles-/       { e = $1; sub(/^drm-cycles-/, "", e); sub(/:$/, "", e); cyc[e] = $2 }
/^drm-total-cycles-/ { e = $1; sub(/^drm-total-cycles-/, "", e); sub(/:$/, "", e); tot[e] = $2 }
/^drm-resident-(system|stolen-system|vram)[0-9]*:/ || /^drm-resident-(gtt|memory)[0-9]*:/ {
    v = $2; u = $3
    if (u == "KiB") v *= 1024; else if (u == "MiB") v *= 1048576; else if (u == "GiB") v *= 1073741824
    mem += v
}
END { if (NR > 0) flush() }
' $files 2>/dev/null
exit 0
