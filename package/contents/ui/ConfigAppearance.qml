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
    property int cfg_columns
    property int cfg_updateInterval
    property int cfg_historyLength
    property alias cfg_tileScale: scale.value
    property alias cfg_backgroundOpacity: bgOpacity.value
    property alias cfg_tileOpacity: tileOpacity.value
    property alias cfg_tooltipsEnabled: tipsBox.checked
    property alias cfg_tooltipDelay: tipDelay.value
    property int cfg_tooltipDuration
    property int cfg_moveFlashDuration
    property int cfg_removeFadeDuration
    // duration slider: 1…10 s, the last step (11) = unlimited (-1)
    function durationStep(ms) { return ms < 0 ? 11 : Math.max(1, Math.min(10, Math.round(ms / 1000))); }
    property string cfg_tileStyle
    property alias cfg_panelShowLabels: panelLabels.checked
    property alias cfg_panelShowRings: panelRings.checked
    property bool cfg_gpuSections
    property string cfg_gpuSectionMode
    property alias cfg_fitToSize: fitBox.checked

    // live preview: every unsaved value of this page shows in the widget right
    // away; stored only with OK / Apply, closing the settings brings back the rest
    readonly property var previewKeys: ["columns", "fitToSize", "tileStyle", "tileScale", "backgroundOpacity",
        "tileOpacity", "gpuSectionMode", "gpuSections", "panelShowLabels", "panelShowRings",
        "tooltipsEnabled", "tooltipDelay", "tooltipDuration", "moveFlashDuration", "removeFadeDuration"]
    property bool previewOn: false
    readonly property string previewJson: {
        if (!previewOn) return "";
        const out = {};
        let any = false;
        previewKeys.forEach(k => {
            const stored = Plasmoid.configuration[k];
            let v = page["cfg_" + k];
            if (typeof stored === "number") v = Math.round(Number(v));   // sliders give reals
            if (v !== stored) { out[k] = v; any = true; }
        });
        return any ? JSON.stringify(out) : "";
    }
    onPreviewJsonChanged: if (Plasmoid.configuration.appearancePreview !== previewJson) Plasmoid.configuration.appearancePreview = previewJson
    Component.onCompleted: previewOn = true
    Component.onDestruction: Plasmoid.configuration.appearancePreview = ""

    // only this page's values (the tiles stay); saved with "Anwenden"
    function resetToDefaults() {
        resetKeys(Object.keys(defaults));
    }
    // single settings back to their default: middle click or right-click menu
    // on the control (ResetHandler); takes effect with "Apply" like any change
    readonly property var defaults: Defaults.settings.appearance
    function sameValue(a, b) { return typeof b === "number" ? Math.round(Number(a)) === b : a === b; }
    function isDefault(keys) { return keys.every(k => sameValue(page["cfg_" + k], defaults[k])); }
    function resetKeys(keys) {
        keys.forEach(k => page["cfg_" + k] = defaults[k]);
        syncControls();
    }
    // controls that are not bound to their cfg_ value
    function syncControls() {
        styleBox.currentIndex = Math.max(0, styleBox.indexOfValue(cfg_tileStyle));
        sectionBox.currentIndex = Math.max(0, sectionBox.indexOfValue(cfg_gpuSectionMode));
        tipDuration.value = durationStep(cfg_tooltipDuration);
    }

    Kirigami.FormLayout {
        RowLayout {
            Kirigami.FormData.label: i18n("Columns:")
            StepSlider {
                id: columns
                steps: [0, 1, 2, 3, 4, 5, 6, 7, 8]
                value: page.cfg_columns
                format: (v) => v === 0 ? i18n("Automatic") : String(v)
                onPicked: (v) => page.cfg_columns = v
                ResetHandler { page: page; keys: ["columns"] }
            }
            Kirigami.ContextualHelpButton {
                toolTipText: i18n("“Automatic”: the number of columns at which the tiles get biggest in the widget's size.")
            }
        }
        RowLayout {
            Kirigami.FormData.label: i18n("On the desktop:")
            QQC2.CheckBox {
                id: fitBox
                ResetHandler { page: page; keys: ["fitToSize"] }
                text: i18n("Shrink tiles so everything fits without scrolling")
            }
            Kirigami.ContextualHelpButton {
                toolTipText: i18n("All tiles get smaller together until they fit into the widget – no scroll bar needed. Without it, the tiles keep their size and the view can be scrolled.")
            }
        }
        RowLayout {
            Kirigami.FormData.label: i18n("Tile style:")
            QQC2.ComboBox {
                wheelEnabled: false   // scrolling the page must not change the value
                id: styleBox
                ResetHandler { page: page; keys: ["tileStyle"] }
                textRole: "text"; valueRole: "value"
                model: [
                    { text: i18n("Glass (subtle)"), value: "glass" },
                    { text: i18n("Filled"), value: "solid" },
                    { text: i18n("Outline (accent colour)"), value: "outline" }
                ]
                Component.onCompleted: currentIndex = Math.max(0, indexOfValue(cfg_tileStyle))
                onActivated: cfg_tileStyle = currentValue
            }
            Kirigami.ContextualHelpButton {
                toolTipText: i18n("Glass: subtly see-through · Filled: solid surface · Outline: only a frame in the accent colour")
            }
        }
        RowLayout {
            Kirigami.FormData.label: i18n("Size:")
            QQC2.Slider {
                id: scale
                ResetHandler { page: page; keys: ["tileScale"]; valueText: page.defaults.tileScale + " %" }
                from: 60; to: 180; stepSize: 5
                Layout.preferredWidth: Kirigami.Units.gridUnit * 10
            }
            QQC2.Label { text: Math.round(scale.value) + " %" }
            Kirigami.ContextualHelpButton {
                toolTipText: i18n("Scales text, rings and spacing of all tiles.")
            }
        }
        RowLayout {
            Kirigami.FormData.label: i18n("Background opacity:")
            QQC2.Slider {
                id: bgOpacity
                ResetHandler { page: page; keys: ["backgroundOpacity"]; valueText: page.defaults.backgroundOpacity + " %" }
                from: 0; to: 100; stepSize: 5
                Layout.preferredWidth: Kirigami.Units.gridUnit * 10
            }
            QQC2.Label { text: Math.round(bgOpacity.value) + " %" }
            Kirigami.ContextualHelpButton {
                toolTipText: i18n("Only on the desktop. The less background, the more solid the tiles get, so values stay readable on any wallpaper – “Tile opacity” sets how solid they are at 0 %. 100 % background is the normal Plasma background.")
            }
        }
        RowLayout {
            Kirigami.FormData.label: i18n("Tile opacity:")
            QQC2.Slider {
                id: tileOpacity
                enabled: bgOpacity.value < 100
                ResetHandler { page: page; keys: ["tileOpacity"]; valueText: page.defaults.tileOpacity + " %" }
                from: 50; to: 100; stepSize: 5
                Layout.preferredWidth: Kirigami.Units.gridUnit * 10
            }
            QQC2.Label { text: Math.round(tileOpacity.value) + " %"; enabled: bgOpacity.value < 100 }
            Kirigami.ContextualHelpButton {
                // xgettext:no-javascript-format
                toolTipText: i18n("How solid the tiles get when the background is faded out completely. Only available below 100 % background.")
            }
        }
        RowLayout {
            Kirigami.FormData.label: i18n("Tooltips:")
            QQC2.CheckBox {
                id: tipsBox
                ResetHandler { page: page; keys: ["tooltipsEnabled"] }
                text: i18n("Show details when the mouse pointer rests on a tile")
            }
            Kirigami.ContextualHelpButton {
                toolTipText: i18n("The tooltip shows the full name, the current values and a short explanation of the tile.")
            }
        }
        RowLayout {
            Kirigami.FormData.label: i18n("Tooltip delay:")
            QQC2.Slider {
                id: tipDelay
                enabled: tipsBox.checked
                ResetHandler { page: page; keys: ["tooltipDelay"]; valueText: i18n("%1 s", (page.defaults.tooltipDelay / 1000).toLocaleString(Qt.locale(), "f", 1)) }
                from: 0; to: 2000; stepSize: 100
                Layout.preferredWidth: Kirigami.Units.gridUnit * 10
            }
            QQC2.Label {
                enabled: tipsBox.checked
                text: tipDelay.value < 50 ? i18n("Immediately")
                    : i18n("%1 s", (Math.round(tipDelay.value / 100) / 10).toLocaleString(Qt.locale(), "f", 1))
            }
            Kirigami.ContextualHelpButton {
                toolTipText: i18n("How long the mouse pointer has to rest on a tile before its tooltip appears.")
            }
        }
        RowLayout {
            Kirigami.FormData.label: i18n("Tooltip duration:")
            QQC2.Slider {
                id: tipDuration
                enabled: tipsBox.checked
                ResetHandler { page: page; keys: ["tooltipDuration"]; valueText: page.defaults.tooltipDuration < 0 ? i18n("Unlimited") : i18n("%1 s", Math.round(page.defaults.tooltipDuration / 1000)) }
                from: 1; to: 11; stepSize: 1
                snapMode: QQC2.Slider.SnapAlways
                Layout.preferredWidth: Kirigami.Units.gridUnit * 10
                Component.onCompleted: value = page.durationStep(page.cfg_tooltipDuration)
                onMoved: page.cfg_tooltipDuration = value >= 11 ? -1 : Math.round(value) * 1000
            }
            QQC2.Label {
                enabled: tipsBox.checked
                text: tipDuration.value >= 11 ? i18n("Unlimited") : i18n("%1 s", Math.round(tipDuration.value))
            }
            Kirigami.ContextualHelpButton {
                toolTipText: i18n("“Unlimited”: the tooltip stays as long as the mouse pointer rests on the tile.")
            }
        }
        RowLayout {
            Kirigami.FormData.label: i18n("Highlight moved tile:")
            StepSlider {
                steps: [0, 1000, 1500, 2000, 2500, 3000, 4000, 5000, 7000, 10000]
                value: page.cfg_moveFlashDuration
                format: (v) => v <= 0 ? i18n("Off") : i18n("%1 s", (v / 1000).toLocaleString(Qt.locale(), "f", v % 1000 ? 1 : 0))
                onPicked: (v) => page.cfg_moveFlashDuration = v
                ResetHandler { page: page; keys: ["moveFlashDuration"] }
            }
            Kirigami.ContextualHelpButton {
                toolTipText: i18n("In “Edit tiles”: how long a tile flashes at its new place after it was moved.")
            }
        }
        RowLayout {
            Kirigami.FormData.label: i18n("Fade out removed tile:")
            StepSlider {
                steps: [0, 300, 500, 800, 1000, 1200, 1500, 2000, 3000]
                value: page.cfg_removeFadeDuration
                format: (v) => v <= 0 ? i18n("Off") : i18n("%1 s", (v / 1000).toLocaleString(Qt.locale(), "f", v % 100 ? 2 : 1))
                onPicked: (v) => page.cfg_removeFadeDuration = v
                ResetHandler { page: page; keys: ["removeFadeDuration"] }
            }
            Kirigami.ContextualHelpButton {
                toolTipText: i18n("In “Edit tiles”: how long a removed tile (× or Delete) turns red and fades out before the others move up. “Off”: it disappears at once.")
            }
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Sections per graphics card:")
            QQC2.ComboBox {
                wheelEnabled: false   // scrolling the page must not change the value
                id: sectionBox
                ResetHandler { page: page; keys: ["gpuSectionMode", "gpuSections"] }
                textRole: "text"; valueRole: "value"
                model: [
                    { text: i18n("From two graphics cards"), value: "auto" },
                    { text: i18n("Always (even with one card)"), value: "always" },
                    { text: i18n("Never (several cards: coloured edge)"), value: "never" }
                ]
                Component.onCompleted: currentIndex = Math.max(0, indexOfValue(cfg_gpuSectionMode || (cfg_gpuSections ? "auto" : "never")))
                onActivated: cfg_gpuSectionMode = currentValue
            }
            Kirigami.ContextualHelpButton {
                toolTipText: i18n("Every graphics card gets its own heading, its tiles below it.")
            }
        }
        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 20
            wrapMode: Text.WordWrap
            opacity: 0.6
            font: Kirigami.Theme.smallFont
            text: i18n("Move, remove or add tiles right in the widget: right-click → “Edit tiles”.")
        }

        Item { Kirigami.FormData.isSection: true }

        RowLayout {
            Kirigami.FormData.label: i18n("Update:")
            StepSlider {
                id: interval
                steps: [250, 500, 1000, 1500, 2000, 3000, 5000, 10000]
                value: page.cfg_updateInterval
                format: (v) => i18n("every %1 s", Number(v / 1000).toLocaleString(Qt.locale(), "f", v % 1000 === 0 ? 0 : v % 500 === 0 ? 1 : 2))
                onPicked: (v) => page.cfg_updateInterval = v
                ResetHandler { page: page; keys: ["updateInterval"] }
            }
            Kirigami.ContextualHelpButton {
                toolTipText: i18n("How often the values are read. Shorter looks smoother but costs a little more computing time.")
            }
        }
        RowLayout {
            Kirigami.FormData.label: i18n("History in graphs:")
            StepSlider {
                id: history
                steps: [10, 20, 30, 45, 60, 120, 180, 300, 600, 900]
                value: page.cfg_historyLength
                format: (v) => v < 60 ? i18n("%1 s", v) : i18n("%1 min", Math.round(v / 60))
                onPicked: (v) => page.cfg_historyLength = v
                ResetHandler { page: page; keys: ["historyLength"] }
            }
            Kirigami.ContextualHelpButton {
                toolTipText: i18n("Which period of time a history graph shows.")
            }
        }

        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18n("Panel") }

        RowLayout {
            Kirigami.FormData.label: i18n("In the panel:")
            QQC2.CheckBox {
                id: panelRings
                ResetHandler { page: page; keys: ["panelShowRings"] }
                text: i18n("Show mini rings")
            }
            Kirigami.ContextualHelpButton {
                toolTipText: i18n("Which sensors appear in the panel is set per entry on the “Sensors” page. The widget's background on the desktop can be switched in edit mode.")
            }
        }
        RowLayout {
            QQC2.CheckBox {
                id: panelLabels
                ResetHandler { page: page; keys: ["panelShowLabels"] }
                text: i18n("Show labels")
            }
            Kirigami.ContextualHelpButton {
                toolTipText: i18n("Shows the name of the sensor next to the value in the panel.")
            }
        }

        Item { Kirigami.FormData.isSection: true }

        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            wrapMode: Text.WordWrap
            opacity: 0.7
            text: i18n("Reset a single setting: right-click it, or click it with the middle mouse button (scroll wheel).")
        }
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
