// SPDX-FileCopyrightText: 2026 Paderman
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import "Hardware.js" as Hardware

// Panel view: small chips with mini-ring + value for every tile marked "showInPanel".
MouseArea {
    id: compact

    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    // one chip per tile – compare tiles get one chip per graphics card: [{src, slot}]
    readonly property var indices: {
        root.sourcesRevision;
        const r = [];
        for (let i = 0; i < root.items.length; ++i) {
            const it = root.items[i];
            if (!it.showInPanel || root.compareCollapsed(i)) continue;
            const c = root.compareSources(i);
            if (c.length > 1) c.forEach(e => r.push({ src: e.src, slot: e.slot }));
            else if (c.length === 1) r.push({ src: c[0].src, slot: c[0].slot });
            else r.push({ src: root.source(i), slot: root.multiGpu ? it.gpuSlot : -1 });
        }
        return r;
    }

    Layout.minimumWidth: vertical ? 0 : (indices.length ? flow.implicitWidth : Kirigami.Units.iconSizes.medium)
    Layout.preferredWidth: Layout.minimumWidth
    Layout.minimumHeight: vertical ? (indices.length ? flow.implicitHeight : Kirigami.Units.iconSizes.medium) : 0
    Layout.preferredHeight: Layout.minimumHeight

    hoverEnabled: true
    onClicked: root.expanded = !root.expanded

    Kirigami.Icon {
        anchors.fill: parent
        visible: compact.indices.length === 0
        source: Plasmoid.icon
        active: compact.containsMouse
    }

    GridLayout {
        id: flow
        anchors.centerIn: parent
        flow: compact.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
        rows: compact.vertical ? -1 : 1
        columns: compact.vertical ? 1 : -1
        rowSpacing: Kirigami.Units.smallSpacing
        columnSpacing: Kirigami.Units.largeSpacing

        Repeater {
            model: compact.indices
            delegate: RowLayout {
                id: chip
                required property var modelData
                readonly property var src: modelData.src
                readonly property real h: compact.vertical ? Kirigami.Units.iconSizes.small * 1.4
                                                           : Math.min(compact.height, Kirigami.Units.iconSizes.medium)
                readonly property int gpuSlot: modelData.slot
                spacing: Math.round(Kirigami.Units.smallSpacing * 1.2)
                Layout.alignment: Qt.AlignCenter

                // which graphics card (only with several GPUs)
                Rectangle {
                    visible: chip.gpuSlot >= 0
                    Layout.preferredWidth: Math.max(4, Math.round(chip.h * 0.22))
                    Layout.preferredHeight: Layout.preferredWidth
                    Layout.alignment: Qt.AlignVCenter
                    Layout.rightMargin: -Math.round(Kirigami.Units.smallSpacing * 0.6)
                    radius: width / 2
                    color: Hardware.gpuColor(chip.gpuSlot, root.lightTheme)
                }
                RingGauge {
                    visible: Plasmoid.configuration.panelShowRings
                    Layout.preferredWidth: Math.round(chip.h * 0.8)
                    Layout.preferredHeight: Layout.preferredWidth
                    Layout.alignment: Qt.AlignVCenter
                    thickness: Math.max(2, width * 0.15)
                    glow: false
                    fraction: chip.src ? chip.src.fraction : 0
                    color: chip.src ? chip.src.color : Kirigami.Theme.highlightColor
                    trackColor: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
                }
                ColumnLayout {
                    spacing: -2
                    Layout.alignment: Qt.AlignVCenter
                    QQC2.Label {
                        visible: Plasmoid.configuration.panelShowLabels
                        text: chip.src ? chip.src.label : ""
                        font.pixelSize: Math.max(7, Math.round(chip.h * 0.3))
                        font.capitalization: Font.AllUppercase
                        font.weight: Font.DemiBold
                        opacity: 0.6
                    }
                    QQC2.Label {
                        text: chip.src ? chip.src.formatted.replace(" ", "") : "–"
                        font.pixelSize: Math.max(9, Math.round(chip.h * (Plasmoid.configuration.panelShowLabels ? 0.42 : 0.5)))
                        font.weight: Font.DemiBold
                        font.features: { "tnum": 1 }
                        color: chip.src && chip.src.level > 0 ? chip.src.color : Kirigami.Theme.textColor
                    }
                }
            }
        }
    }
}
