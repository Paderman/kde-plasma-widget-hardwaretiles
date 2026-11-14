#!/bin/bash
# SPDX-FileCopyrightText: 2026 Paderman
# SPDX-License-Identifier: GPL-2.0-or-later
# Removes the demo widget package (remove the widget from the desktop first).
kpackagetool6 -t Plasma/Applet -r io.github.paderman.sensordeck.multigpudemo && rm -rf "$(dirname "$0")/build"
