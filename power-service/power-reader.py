#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Paderman
# SPDX-License-Identifier: GPL-2.0-or-later
"""Power draw of the processor (RAPL energy counters), published as coarse
watt values for Hardware Tiles.

Since 2020 the kernel lets only root read the RAPL energy counters
(/sys/class/powercap/intel-rapl:*/energy_uj): read very often and very
precisely they allow a side-channel attack (CVE-2020-8694, "Platypus").
This service reads them once per second and publishes only the average
power of that second, rounded to 0.1 W – far too coarse for such an attack,
precise enough for a monitor. The raw counters are never passed on.

Files in DIR (default /run/hardwaretiles-power), plain numbers in W:
  cpu         whole processor (package)      cpu-1, … further sockets
  cpu-cores   processor cores only (core)
  igpu        graphics built into the processor (uncore; Intel desktop/laptop)
  ram         memory controller / RAM (dram), if the processor reports it
  platform    whole platform (psys), if reported

Usage:
  power-reader.py --list                  zones found and whether they are readable
  power-reader.py --once                  measure one second, print the values
  power-reader.py --serve [DIR] [SECONDS] publish continuously (default 1 s)
"""
import glob
import os
import signal
import sys
import time

NAMES = {"core": "cpu-cores", "uncore": "igpu", "dram": "ram", "psys": "platform"}


def zones():
    """[(published name, energy file, wrap-around range in µJ)]"""
    out = []
    for d in sorted(glob.glob("/sys/class/powercap/*-rapl:*")):
        try:
            with open(os.path.join(d, "name")) as f:
                kind = f.read().strip()
        except OSError:
            continue
        if kind.startswith("package-"):
            n = int(kind.split("-")[1]) if kind.split("-")[1].isdigit() else 0
            # sub-zones (core/uncore/dram) of further sockets get the socket suffix
            name = "cpu" if n == 0 else "cpu-%d" % n
        else:
            name = NAMES.get(kind)
            if not name:
                continue
            parent = os.path.basename(os.path.dirname(os.path.realpath(d)))
            sock = parent.split(":")[1] if parent.count(":") == 1 else "0"
            if sock != "0":
                name += "-%s" % sock
        try:
            with open(os.path.join(d, "max_energy_range_uj")) as f:
                rng = int(f.read())
        except (OSError, ValueError):
            rng = 0
        out.append((name, os.path.join(d, "energy_uj"), rng))
    # the same name twice (e.g. intel-rapl and intel-rapl-mmio): keep the first
    seen, uniq = set(), []
    for z in out:
        if z[0] not in seen:
            seen.add(z[0])
            uniq.append(z)
    return uniq


def read(path):
    try:
        with open(path) as f:
            return int(f.read())
    except (OSError, ValueError):
        return None


def sample(zs):
    return {name: read(path) for name, path, _ in zs}, time.monotonic()


def watts(zs, a, b):
    (ea, ta), (eb, tb) = a, b
    dt = tb - ta
    res = {}
    if dt <= 0:
        return res
    for name, _, rng in zs:
        x, y = ea.get(name), eb.get(name)
        if x is None or y is None:
            continue
        d = y - x
        if d < 0:                       # counter wrapped around
            if rng <= 0:
                continue
            d += rng
        res[name] = round(d / dt / 1e6, 1)
    return res


def publish(d, values):
    for name, w in values.items():
        tmp = os.path.join(d, "." + name + ".tmp")
        with open(tmp, "w") as f:
            f.write("%.1f\n" % w)
        os.replace(tmp, os.path.join(d, name))


def serve(d, interval):
    os.makedirs(d, exist_ok=True)
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    zs, warned = [], False
    prev = None
    while True:
        if not zs:
            zs = [z for z in zones() if read(z[1]) is not None]
            if not zs:
                if not warned:
                    print("no readable RAPL energy counters (udev rule / group missing?) – retrying",
                          file=sys.stderr, flush=True)
                    warned = True
                time.sleep(10)
                continue
            print("publishing: " + ", ".join(z[0] for z in zs), file=sys.stderr, flush=True)
            prev = sample(zs)
        time.sleep(interval)
        cur = sample(zs)
        if any(v is None for v in cur[0].values()):
            zs = []                     # zones vanished (module reload) – find them again
            continue
        publish(d, watts(zs, prev, cur))
        prev = cur


def main(argv):
    if len(argv) < 2 or argv[1] in ("-h", "--help"):
        print(__doc__)
        return 0
    if argv[1] == "--list":
        zs = zones()
        if not zs:
            print("no RAPL zones found")
        for name, path, _ in zs:
            ok = "readable" if read(path) is not None else "NOT readable"
            print("%-10s %s  (%s)" % (name, path, ok))
        return 0
    if argv[1] == "--once":
        zs = [z for z in zones() if read(z[1]) is not None]
        if not zs:
            print("no readable RAPL energy counters", file=sys.stderr)
            return 1
        a = sample(zs)
        time.sleep(1)
        for name, w in watts(zs, a, sample(zs)).items():
            print("%-10s %5.1f W" % (name, w))
        return 0
    if argv[1] == "--serve":
        d = argv[2] if len(argv) > 2 else "/run/hardwaretiles-power"
        interval = max(1.0, float(argv[3])) if len(argv) > 3 else 1.0
        serve(d, interval)
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
