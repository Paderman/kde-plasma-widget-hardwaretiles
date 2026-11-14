#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Paderman
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Fans of NVIDIA graphics cards, read from the driver's library (NVML) –
# nvidia-smi only reports a percentage, not the measured speed. Standard
# library only (ctypes), nothing to install. Lines, tab separated:
#   FAN <nvidia-smi index> <fan no, from 1> <rpm|-1> <percent|-1> <target percent|-1>
# With --probe only the number of fans that report a speed:
#   NVFANS <nvidia-smi index> <count>
# Exit code 1 if the library or the driver is missing.

import ctypes
import sys


class FanSpeedInfo(ctypes.Structure):
    # nvmlFanSpeedInfo_t – only newer drivers know nvmlDeviceGetFanSpeedRPM
    _fields_ = [("version", ctypes.c_uint), ("fan", ctypes.c_uint), ("speed", ctypes.c_uint)]


def main():
    probe = "--probe" in sys.argv[1:]
    try:
        nvml = ctypes.CDLL("libnvidia-ml.so.1")
    except OSError:
        return 1
    if nvml.nvmlInit_v2() != 0:
        return 1
    get_rpm = getattr(nvml, "nvmlDeviceGetFanSpeedRPM", None)
    get_target = getattr(nvml, "nvmlDeviceGetTargetFanSpeed", None)
    out = []
    try:
        count = ctypes.c_uint()
        if nvml.nvmlDeviceGetCount_v2(ctypes.byref(count)) != 0:
            return 1
        for idx in range(count.value):
            dev = ctypes.c_void_p()
            if nvml.nvmlDeviceGetHandleByIndex_v2(idx, ctypes.byref(dev)) != 0:
                continue
            fans = ctypes.c_uint()
            if nvml.nvmlDeviceGetNumFans(dev, ctypes.byref(fans)) != 0:
                continue
            with_rpm = 0
            for fan in range(fans.value):
                rpm = -1
                if get_rpm:
                    info = FanSpeedInfo()
                    info.version = ctypes.sizeof(FanSpeedInfo) | (1 << 24)
                    info.fan = fan
                    if get_rpm(dev, ctypes.byref(info)) == 0:
                        rpm = info.speed
                        with_rpm += 1
                if probe:
                    continue
                pct = ctypes.c_uint()
                p = pct.value if nvml.nvmlDeviceGetFanSpeed_v2(dev, fan, ctypes.byref(pct)) == 0 else -1
                tgt = ctypes.c_uint()
                t = tgt.value if get_target and get_target(dev, fan, ctypes.byref(tgt)) == 0 else -1
                out.append("FAN\t%d\t%d\t%d\t%d\t%d" % (idx, fan + 1, rpm, p, t))
            if probe:
                out.append("NVFANS\t%d\t%d" % (idx, with_rpm))
    finally:
        nvml.nvmlShutdown()
    print("\n".join(out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
