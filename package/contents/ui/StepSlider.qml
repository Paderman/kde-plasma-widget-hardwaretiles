// SPDX-FileCopyrightText: 2026 Paderman
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

// Slider over a list of fixed steps (e.g. 1, 2, 5, 10 minutes) with the value
// shown next to it. "value" follows the setting; moving emits picked(step).
// A stored value between two steps shows the nearest one and stays as it is
// until the slider is moved. Root is a plain Item so a ResetHandler can be
// put inside without being laid out like the slider and the label.
Item {
    id: ss

    property var steps: []
    property real value: 0
    property var format: (v) => String(v)
    signal picked(real value)

    // used by ResetHandler to show the default the same way
    function textFromValue(v) { return format(v); }
    function nearest(v) {
        let best = 0;
        for (let i = 1; i < steps.length; ++i)
            if (Math.abs(steps[i] - v) < Math.abs(steps[best] - v)) best = i;
        return best;
    }

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight
    onValueChanged: slider.value = nearest(value)
    onStepsChanged: slider.value = nearest(value)

    RowLayout {
        id: row
        anchors.fill: parent
        QQC2.Slider {
            id: slider
            from: 0
            to: Math.max(1, ss.steps.length - 1)
            stepSize: 1
            snapMode: QQC2.Slider.SnapAlways
            Layout.preferredWidth: Kirigami.Units.gridUnit * 10
            Component.onCompleted: value = ss.nearest(ss.value)
            onMoved: ss.picked(ss.steps[Math.round(value)])
        }
        QQC2.Label {
            // every move sets the value at once, so this always shows the setting
            text: ss.format(ss.value)
        }
    }
}
