#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Paderman
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Installs one package through PackageKit (the way Discover does it), so that
# KDE's own password dialog asks for the administrator password. Used when
# `pkexec` itself is missing (Debian 13 ships it as a package of its own).
#   install-package.py <package name> [--resolve-only]
# `pkcon -y` cannot be used: "non-interactive" also forbids the password
# dialog, and without -y pkcon wants a confirmation on a terminal.
# PackageKit only accepts the calls of a transaction from the connection that
# created it – hence one process (GLib's D-Bus) instead of single gdbus calls.
# Prints: ID <package id> | RESULT ok | notfound | failed <reason> | nogi
import sys

try:
    from gi.repository import Gio, GLib
except Exception:
    print("RESULT nogi")
    sys.exit(1)

PK = "org.freedesktop.PackageKit"
TX = PK + ".Transaction"
bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)


def call(path, iface, method, args=None, rtype=None):
    return bus.call_sync(PK, path, iface, method, args, rtype, Gio.DBusCallFlags.NONE, -1, None)


def run(method, args):
    """Runs one transaction; returns (exit code, package ids, error text)."""
    tx = call("/org/freedesktop/PackageKit", PK, "CreateTransaction", None, GLib.VariantType("(o)")).unpack()[0]
    loop = GLib.MainLoop()
    res = {"ids": [], "err": "", "exit": None}

    def on_signal(conn, sender, path, iface, name, params, *data):
        p = params.unpack()
        if name == "Package":
            res["ids"].append(p[1])
        elif name == "ErrorCode":
            res["err"] = p[1]
        elif name == "Finished":
            res["exit"] = p[0]
            loop.quit()

    bus.signal_subscribe(PK, TX, None, tx, None, Gio.DBusSignalFlags.NONE, on_signal)
    # interactive: PackageKit may let KDE ask for the password
    call(tx, TX, "SetHints", GLib.Variant("(as)", (["interactive=true"],)))
    call(tx, TX, method, args)
    GLib.timeout_add_seconds(900, loop.quit)
    loop.run()
    return res["exit"], res["ids"], res["err"]


def main():
    pkg = sys.argv[1]
    try:
        code, ids, err = run("Resolve", GLib.Variant("(tas)", (0, [pkg])))
        ids = [i for i in ids if i.split(";")[0] == pkg]
        if not ids:
            print("RESULT notfound")
            return 1
        print("ID " + ids[0])
        if "--resolve-only" in sys.argv:
            return 0
        # only trusted packages, like pkcon and Discover
        code, _, err = run("InstallPackages", GLib.Variant("(tas)", (2, [ids[0]])))
        if code == 1:
            print("RESULT ok")
            return 0
        print("RESULT failed " + (err or "cancelled"))
        return 1
    except GLib.Error as e:
        print("RESULT failed " + e.message[:200])
        return 1


sys.exit(main())
