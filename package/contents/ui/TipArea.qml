// SPDX-FileCopyrightText: 2026 Paderman
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid

// Native Plasma tooltip with the delay and on/off switch from the settings.
// "wanted" is the caller's own condition (e.g. not while dragging).
// Every tile waits the full delay, also when moving straight from one to the next.
// Own content instead of Plasma's default: that one cuts the text after 8 lines
// (explanations with thresholds are longer). Looks the same otherwise.
PlasmaCore.ToolTipArea {
    id: area

    mainItem: Item {
        implicitWidth: tipRow.implicitWidth + Kirigami.Units.largeSpacing * 2
        implicitHeight: tipRow.implicitHeight + Kirigami.Units.largeSpacing * 2
        LayoutMirroring.enabled: Application.layoutDirection === Qt.RightToLeft
        LayoutMirroring.childrenInherit: true
        Kirigami.Theme.colorSet: Kirigami.Theme.Window
        Kirigami.Theme.inherit: false

        RowLayout {
            id: tipRow
            anchors.centerIn: parent
            spacing: Kirigami.Units.gridUnit
            Kirigami.Icon {
                animated: false
                source: area.icon
                visible: area.icon !== "" && valid
                Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                Layout.preferredHeight: Kirigami.Units.iconSizes.medium
            }
            ColumnLayout {
                Layout.maximumWidth: Kirigami.Units.gridUnit * 22
                spacing: 0
                Kirigami.Heading {
                    level: 3
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    wrapMode: Text.Wrap
                    text: area.mainText
                    textFormat: Text.PlainText
                    visible: text !== ""
                }
                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: area.subText
                    textFormat: area.textFormat
                    opacity: 0.75
                    visible: text !== ""
                }
            }
        }
    }

    property bool wanted: true
    readonly property bool allowed: root.setting("tooltipsEnabled")
    readonly property int delay: Math.max(0, Number(root.setting("tooltipDelay")))
    property bool armed: false

    active: wanted && allowed && (armed || delay === 0)
    // hides by itself after this time; -1 = stays until the pointer leaves
    readonly property int duration: Number(root.setting("tooltipDuration"))
    timeout: duration < 0 ? -1 : Math.max(1000, duration)

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
