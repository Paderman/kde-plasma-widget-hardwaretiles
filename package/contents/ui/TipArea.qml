// SPDX-FileCopyrightText: 2026 Paderman
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid

// Native Plasma tooltip with the delay and on/off switch from the settings.
// "wanted" is the caller's own condition (e.g. not while dragging).
// Every tile waits the full delay, also when moving straight from one to the next.
PlasmaCore.ToolTipArea {
    id: area

    property bool wanted: true
    readonly property bool allowed: Plasmoid.configuration.tooltipsEnabled
    readonly property int delay: Math.max(0, Plasmoid.configuration.tooltipDelay)
    property bool armed: false

    active: wanted && allowed && (armed || delay === 0)
    // hides by itself after this time; -1 = stays until the pointer leaves
    timeout: Plasmoid.configuration.tooltipDuration < 0 ? -1 : Math.max(1000, Plasmoid.configuration.tooltipDuration)

    HoverHandler {
        onHoveredChanged: {
            if (hovered) {
                if (area.delay === 0) area.arm();
                else wait.restart();
            } else {
                wait.stop();
                area.armed = false;
            }
        }
    }
    Timer {
        id: wait
        interval: area.delay
        onTriggered: area.arm()
    }
    function arm() {
        armed = true;
        if (active) showToolTip();
    }
}
