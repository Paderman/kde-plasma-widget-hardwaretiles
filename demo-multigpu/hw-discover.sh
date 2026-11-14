#!/bin/sh
# SPDX-FileCopyrightText: 2026 Paderman
# SPDX-License-Identifier: GPL-2.0-or-later
# Demo: real hardware discovery + a simulated second NVIDIA card at 0000:09:00.0
d=$(dirname "$0")
sh "$d/hw-real.sh" | awk '{print} /^GPU\t/ && !done {print "GPU\t0000:09:00.0\t0x10de\tnvidia\t-\t1\tNVIDIA Corporation\tGA104 [GeForce RTX 3060 Ti]\tASUSTeK Computer Inc."; done=1}'
