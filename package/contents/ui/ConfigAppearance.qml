// SPDX-FileCopyrightText: 2026 Paderman
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.plasmoid
import "Defaults.js" as Defaults

KCM.SimpleKCM {
    id: page
    property alias cfg_columns: columns.value
    property alias cfg_updateInterval: interval.value
    property alias cfg_historyLength: history.value
    property alias cfg_tileScale: scale.value
    property string cfg_tileStyle
    property alias cfg_panelShowLabels: panelLabels.checked
    property alias cfg_panelShowRings: panelRings.checked
    property bool cfg_gpuSections
    property string cfg_gpuSectionMode
    property alias cfg_fitToSize: fitBox.checked

    // only this page's values (the tiles stay); saved with "Anwenden"
    function resetToDefaults() {
        const d = Defaults.settings.appearance;
        for (const k in d) page["cfg_" + k] = d[k];
        styleBox.currentIndex = Math.max(0, styleBox.indexOfValue(cfg_tileStyle));
        sectionBox.currentIndex = Math.max(0, sectionBox.indexOfValue(cfg_gpuSectionMode));
    }

    Kirigami.FormLayout {
        QQC2.SpinBox {
            wheelEnabled: false   // scrolling the page must not change the value
            id: columns
            Kirigami.FormData.label: i18n("Columns:")
            from: 0; to: 8
            textFromValue: (v) => v === 0 ? i18n("Automatic") : String(v)
            valueFromText: (t) => t === i18n("Automatic") ? 0 : parseInt(t)
        }
        QQC2.CheckBox {
            id: fitBox
            Kirigami.FormData.label: i18n("On the desktop:")
            text: i18n("Shrink tiles so everything fits without scrolling")
        }
        QQC2.ComboBox {
            wheelEnabled: false   // scrolling the page must not change the value
            id: styleBox
            Kirigami.FormData.label: i18n("Tile style:")
            textRole: "text"; valueRole: "value"
            model: [
                { text: i18n("Glass (subtle)"), value: "glass" },
                { text: i18n("Filled"), value: "solid" },
                { text: i18n("Outline (accent colour)"), value: "outline" }
            ]
            Component.onCompleted: currentIndex = Math.max(0, indexOfValue(cfg_tileStyle))
            onActivated: cfg_tileStyle = currentValue
        }
        RowLayout {
            Kirigami.FormData.label: i18n("Size:")
            QQC2.Slider {
                id: scale
                from: 60; to: 180; stepSize: 5
                Layout.preferredWidth: Kirigami.Units.gridUnit * 10
                // live preview in the widget; stored only with OK / Apply
                onValueChanged: Plasmoid.configuration.tileScalePreview = Math.round(value)
                Component.onDestruction: Plasmoid.configuration.tileScalePreview = 0
            }
            QQC2.Label { text: Math.round(scale.value) + " %" }
        }

        QQC2.ComboBox {
            wheelEnabled: false   // scrolling the page must not change the value
            id: sectionBox
            Kirigami.FormData.label: i18n("Sections per graphics card:")
            textRole: "text"; valueRole: "value"
            model: [
                { text: i18n("From two graphics cards"), value: "auto" },
                { text: i18n("Always (even with one card)"), value: "always" },
                { text: i18n("Never (several cards: coloured edge)"), value: "never" }
            ]
            Component.onCompleted: currentIndex = Math.max(0, indexOfValue(cfg_gpuSectionMode || (cfg_gpuSections ? "auto" : "never")))
            onActivated: cfg_gpuSectionMode = currentValue
        }
        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 20
            wrapMode: Text.WordWrap
            opacity: 0.6
            font: Kirigami.Theme.smallFont
            text: i18n("Move, remove or add tiles right in the widget: right-click → “Edit tiles”.")
        }

        Item { Kirigami.FormData.isSection: true }

        QQC2.SpinBox {
            wheelEnabled: false   // scrolling the page must not change the value
            id: interval
            Kirigami.FormData.label: i18n("Update:")
            from: 250; to: 10000; stepSize: 250
            textFromValue: (v) => i18n("every %1 s", Number(v / 1000).toLocaleString(Qt.locale(), "f", v % 1000 === 0 ? 0 : v % 500 === 0 ? 1 : 2))
            valueFromText: (t) => Math.round(parseFloat(t.replace(/[^0-9,.]/g, "").replace(",", ".")) * 1000)
        }
        QQC2.SpinBox {
            wheelEnabled: false   // scrolling the page must not change the value
            id: history
            Kirigami.FormData.label: i18n("History in graphs:")
            from: 10; to: 900; stepSize: 10
            textFromValue: (v) => i18n("%1 s", v)
            valueFromText: (t) => parseInt(t)
        }

        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18n("Panel") }

        QQC2.CheckBox {
            id: panelRings
            Kirigami.FormData.label: i18n("In the panel:")
            text: i18n("Show mini rings")
        }
        QQC2.CheckBox {
            id: panelLabels
            text: i18n("Show labels")
        }
        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 20
            wrapMode: Text.WordWrap
            opacity: 0.7
            text: i18n("Which sensors appear in the panel is set per entry on the “Sensors” page. The widget's background on the desktop can be switched in edit mode.")
        }

        Item { Kirigami.FormData.isSection: true }

        RowLayout {
            QQC2.Button {
                icon.name: "edit-reset"
                text: i18n("Restore defaults")
                onClicked: { page.resetToDefaults(); resetHint.done = true }
            }
            QQC2.Label {
                id: resetHint
                property bool done: false
                Layout.fillWidth: true
                Layout.maximumWidth: Kirigami.Units.gridUnit * 22
                wrapMode: Text.WordWrap
                opacity: 0.7
                text: done
                    ? i18n("Reset. It takes effect only after “Apply” – “Cancel” keeps everything as it was.")
                    : i18n("Only affects the settings on this page – your sensor tiles and notifications are kept.")
            }
        }
    }
}
