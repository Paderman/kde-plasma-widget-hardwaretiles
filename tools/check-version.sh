#!/bin/sh
# SPDX-FileCopyrightText: 2026 Paderman
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Prints the version from package/metadata.json and fails if UpdateCheck.js
# (shown in the settings, used for the update check) has a different one.
cd "$(dirname "$0")/.." || exit 1
meta=$(sed -n 's/.*"Version": *"\([^"]*\)".*/\1/p' package/metadata.json | head -1)
js=$(sed -n 's/^var current = "\([^"]*\)".*/\1/p' package/contents/ui/UpdateCheck.js)
if [ -z "$meta" ] || [ "$meta" != "$js" ]; then
    echo "Version mismatch: metadata.json has '$meta', UpdateCheck.js has '$js'" >&2
    exit 1
fi
echo "$meta"
