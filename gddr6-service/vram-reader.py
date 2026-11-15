#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Paderman
# SPDX-License-Identifier: GPL-2.0-or-later
"""VRAM temperature of NVIDIA graphics cards, read from the card's own
register window (/sys/bus/pci/devices/<addr>/resource0) instead of /dev/mem.

Needs only read access to resource0 (no root, no iomem=relaxed). Register
offsets and decoding follow the gddr6 project (github.com/olealgoritme/gddr6),
which documented which register holds the memory temperature per GPU.

Usage:
  vram-reader.py --list          cards found and whether they are supported
  vram-reader.py --once [ADDR]   print the temperature(s) once
  vram-reader.py --raw ADDR OFF  print one raw register (hex offset), for testing
  vram-reader.py --serve [DIR] [SECONDS]
                                 publish continuously (default /run/gddr6, 1 s):
                                   DIR/vram          first card (plain number)
                                   DIR/vram_all      one line per card
                                   DIR/vram-<addr>   per PCI address (used by Hardware Tiles)
"""
import ctypes
import glob
import mmap
import os
import signal
import sys
import time

# ---------------------------------------------------------------- devices
# device id -> (register offset in BAR0, decode, memory type, name)
ADA = "ada"        # bits 11:0 / 32 = °C   (Ampere / Ada, mirror register)
MRCODE = "mrcode"  # GDDR MR code in bits 23:16 (Blackwell GDDR7)

DEVICES = {
    0x2684: (0xE2A8, ADA, "GDDR6X", "RTX 4090"),
    0x2685: (0xE2A8, ADA, "GDDR6X", "RTX 4090 D"),
    0x2702: (0xE2A8, ADA, "GDDR6X", "RTX 4080 Super"),
    0x2704: (0xE2A8, ADA, "GDDR6X", "RTX 4080"),
    0x2705: (0xE2A8, ADA, "GDDR6X", "RTX 4070 Ti Super"),
    0x2782: (0xE2A8, ADA, "GDDR6X", "RTX 4070 Ti"),
    0x2783: (0xE2A8, ADA, "GDDR6X", "RTX 4070 Super"),
    0x2786: (0xE2A8, ADA, "GDDR6X", "RTX 4070"),
    0x2860: (0xE2A8, ADA, "GDDR6", "RTX 4070 Max-Q / Mobile"),
    0x28E0: (0xE2A8, ADA, "GDDR6", "RTX 4060 Max-Q / Mobile"),
    0x28A0: (0xE2A8, ADA, "GDDR6", "RTX 4060 Laptop"),
    0x2203: (0xE2A8, ADA, "GDDR6X", "RTX 3090 Ti"),
    0x2204: (0xE2A8, ADA, "GDDR6X", "RTX 3090"),
    0x2208: (0xE2A8, ADA, "GDDR6X", "RTX 3080 Ti"),
    0x2206: (0xE2A8, ADA, "GDDR6X", "RTX 3080"),
    0x2216: (0xE2A8, ADA, "GDDR6X", "RTX 3080 LHR"),
    0x2484: (0xEE50, ADA, "GDDR6", "RTX 3070"),
    0x2488: (0xEE50, ADA, "GDDR6", "RTX 3070 LHR"),
    0x2531: (0xE2A8, ADA, "GDDR6", "RTX A2000"),
    0x2571: (0xE2A8, ADA, "GDDR6", "RTX A2000"),
    0x24B0: (0xE2A8, ADA, "GDDR6", "RTX A4000"),
    0x2232: (0xE2A8, ADA, "GDDR6", "RTX A4500"),
    0x2231: (0xE2A8, ADA, "GDDR6", "RTX A5000"),
    0x26B1: (0xE2A8, ADA, "GDDR6", "RTX 6000 Ada Generation"),
    0x27B8: (0xE2A8, ADA, "GDDR6", "L4"),
    0x26B9: (0xE2A8, ADA, "GDDR6", "L40S"),
    0x2236: (0xE2A8, ADA, "GDDR6", "A10"),
    0x2B85: (0x9A24C0, MRCODE, "GDDR7", "RTX 5090"),
}


def decode(kind, raw):
    if kind == MRCODE:
        code = min((raw >> 16) & 0xFF, 80)
        return (code - 20) * 2 if code > 19 else -(40 - code * 2)
    return (raw & 0x0FFF) / 0x20


# ---------------------------------------------------------------- MMIO read
# libc symbols of the running process (no ldconfig/gcc lookup - works in a sandbox)
_libc = ctypes.CDLL(None, use_errno=True)
_libc.mmap.restype = ctypes.c_void_p
_libc.mmap.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_int, ctypes.c_int,
                       ctypes.c_int, ctypes.c_long]
_libc.munmap.argtypes = [ctypes.c_void_p, ctypes.c_size_t]
MAP_FAILED = ctypes.c_void_p(-1).value


def read_reg(addr, off):
    """One aligned 32-bit read at BAR0+off of the card at PCI address addr."""
    path = "/sys/bus/pci/devices/%s/resource0" % addr
    pg = mmap.PAGESIZE
    base = off & ~(pg - 1)
    fd = os.open(path, os.O_RDONLY | os.O_SYNC)
    try:
        p = _libc.mmap(None, pg, mmap.PROT_READ, mmap.MAP_SHARED, fd, base)
        if p is None or p == MAP_FAILED:
            e = ctypes.get_errno()
            raise OSError(e, "mmap %s: %s" % (path, os.strerror(e)))
        try:
            return ctypes.c_uint32.from_address(p + (off - base)).value
        finally:
            _libc.munmap(p, pg)
    finally:
        os.close(fd)


# ---------------------------------------------------------------- discovery
def cards():
    """[(addr, device id, entry or None)] for all NVIDIA display controllers."""
    out = []
    for d in sorted(glob.glob("/sys/bus/pci/devices/*")):
        try:
            vendor = open(d + "/vendor").read().strip()
            cls = open(d + "/class").read().strip()
            dev = int(open(d + "/device").read().strip(), 16)
        except OSError:
            continue
        if vendor != "0x10de" or not cls.startswith("0x03"):
            continue
        out.append((os.path.basename(d), dev, DEVICES.get(dev)))
    return out


def temperature(addr, entry):
    off, kind = entry[0], entry[1]
    return decode(kind, read_reg(addr, off))


def fmt(t):
    return "%d" % round(t) if abs(t - round(t)) < 0.05 else "%.1f" % t


def put(directory, name, text):
    tmp = os.path.join(directory, "." + name + ".tmp")
    with open(tmp, "w") as f:
        f.write(text + "\n")
    os.replace(tmp, os.path.join(directory, name))


def serve(directory, interval):
    """Publish the temperatures until SIGTERM/SIGINT; files are removed on exit."""
    os.makedirs(directory, exist_ok=True)
    stop = []
    for sig in (signal.SIGTERM, signal.SIGINT):
        signal.signal(sig, lambda *_: stop.append(1))
    supported = [(a, e) for a, d, e in cards() if e]
    if not supported:
        print("No supported NVIDIA card found.", file=sys.stderr)
        return 1
    for a, e in supported:
        print("%s: %s (%s), register 0x%X" % (a, e[3], e[2], e[0]), flush=True)
    written, failing = set(), set()
    try:
        while not stop:
            values = []
            for addr, e in supported:
                try:
                    t = fmt(temperature(addr, e))
                except OSError as err:
                    if addr not in failing:          # log once per failure streak
                        print("%s: %s" % (addr, err), file=sys.stderr, flush=True)
                        failing.add(addr)
                    continue
                if addr in failing:
                    print("%s: readable again" % addr, flush=True)
                    failing.discard(addr)
                put(directory, "vram-" + addr, t)
                written.add("vram-" + addr)
                values.append(t)
            if values:
                put(directory, "vram", values[0])
                put(directory, "vram_all", "\n".join(values))
                written.update(("vram", "vram_all"))
            time.sleep(interval)
    finally:
        for name in written:
            try:
                os.remove(os.path.join(directory, name))
            except OSError:
                pass
    return 0


def main(argv):
    if len(argv) >= 2 and argv[1] == "--list":
        for addr, dev, e in cards():
            print("%s  0x%04x  %s" % (addr, dev, ("%s (%s)" % (e[3], e[2])) if e else "not supported"))
        return 0
    if len(argv) >= 4 and argv[1] == "--raw":
        print("0x%08x" % read_reg(argv[2], int(argv[3], 16)))
        return 0
    if len(argv) >= 2 and argv[1] == "--once":
        want = argv[2] if len(argv) > 2 else None
        rc = 1
        for addr, dev, e in cards():
            if not e or (want and addr != want):
                continue
            t = temperature(addr, e)
            print("%s %g" % (addr, t))
            rc = 0
        return rc
    if len(argv) >= 2 and argv[1] == "--serve":
        directory = argv[2] if len(argv) > 2 else "/run/gddr6"
        interval = float(argv[3]) if len(argv) > 3 else 1.0
        return serve(directory, max(0.2, interval))
    print(__doc__.strip())
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
