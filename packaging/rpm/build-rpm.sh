#!/bin/sh
# SPDX-FileCopyrightText: 2026 Paderman
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Builds dist/plasma-widget-hardwaretiles-<version>-1.noarch.rpm (needs rpmbuild, gettext, tar).
set -eu
SRC=$(cd "$(dirname "$0")/../.." && pwd)
VERSION=$("$SRC/tools/check-version.sh")
TOP=$(mktemp -d)
trap 'rm -rf "$TOP"' EXIT
mkdir -p "$TOP/SOURCES" "$TOP/SPECS"
tar -C "$SRC/.." --transform "s|^$(basename "$SRC")|hardwaretiles-$VERSION|" \
    --exclude=dist --exclude=.git --exclude='*/package/contents/locale' --exclude='__pycache__' \
    -czf "$TOP/SOURCES/hardwaretiles-$VERSION.tar.gz" "$(basename "$SRC")"
rpmbuild --define "_topdir $TOP" --define "version_override $VERSION" -bb "$SRC/packaging/rpm/hardwaretiles.spec"
mkdir -p "$SRC/dist"
find "$TOP/RPMS" -name '*.rpm' -exec cp {} "$SRC/dist/" \; -exec echo "Built" {} \;
