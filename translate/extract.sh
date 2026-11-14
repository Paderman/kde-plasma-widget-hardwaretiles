#!/bin/bash
# SPDX-FileCopyrightText: 2026 Paderman
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Collects all translatable texts into translate/template.pot and merges
# them into every existing translation (translate/<lang>.po).
# Needs gettext (xgettext, msgmerge).
set -euo pipefail
cd "$(dirname "$0")"

files=$(cd .. && find package -name '*.qml' -o -name '*.js' | sort)
(cd .. && xgettext --from-code=UTF-8 -L JavaScript \
    -ki18n:1 -ki18np:1,2 -ki18nc:1c,2 -ktr:1 \
    --package-name="Sensor Deck" \
    --msgid-bugs-address="https://github.com/Paderman/sensordeck/issues" \
    --add-comments=TRANSLATORS: \
    -o translate/template.pot $files)
# a stable header date keeps diffs small
sed -i 's/^"POT-Creation-Date: .*\\n"$/"POT-Creation-Date: \\n"/' template.pot

for po in *.po; do
    [ -e "$po" ] || continue
    msgmerge --quiet --update --backup=none "$po" template.pot
done
echo "template.pot: $(grep -c '^msgid ' template.pot) entries (incl. header)"
