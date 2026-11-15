// SPDX-FileCopyrightText: 2026 Paderman
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.notification
import "Defaults.js" as Defaults

KCM.SimpleKCM {
    id: page
    property alias cfg_alertsEnabled: enabledBox.checked
    property alias cfg_alertOnWarn: warnBox.checked
    property alias cfg_alertRecovery: recoveryBox.checked
    property int cfg_alertDelay
    property int cfg_alertCooldown
    property int cfg_alertHysteresis
    property alias cfg_fanWatch: fanBox.checked
    property int cfg_fanSlowPercent

    // only this page's values (thresholds per sensor stay); saved with "Anwenden"
    function resetToDefaults() {
        resetKeys(Object.keys(defaults));
    }
    // single settings back to their default: middle click or right-click menu
    // on the control (ResetHandler); takes effect with "Apply" like any change
    readonly property var defaults: Defaults.settings.alerts
    function sameValue(a, b) { return typeof b === "number" ? Math.round(Number(a)) === b : a === b; }
    function isDefault(keys) { return keys.every(k => sameValue(page["cfg_" + k], defaults[k])); }
    function resetKeys(keys) {
        keys.forEach(k => page["cfg_" + k] = defaults[k]);
        syncControls();
    }
    function syncControls() {}   // every control is bound to its cfg_ value


    Kirigami.FormLayout {
        QQC2.CheckBox {
            id: enabledBox
            ResetHandler { page: page; keys: ["alertsEnabled"] }
            Kirigami.FormData.label: i18n("Notifications:")
            text: i18n("Notify on critical values")
        }
        QQC2.CheckBox {
            id: warnBox
            ResetHandler { page: page; keys: ["alertOnWarn"] }
            enabled: enabledBox.checked
            text: i18n("Also when the warning threshold is reached")
        }
        QQC2.CheckBox {
            id: recoveryBox
            ResetHandler { page: page; keys: ["alertRecovery"] }
            enabled: enabledBox.checked
            text: i18n("All-clear when the value is back to normal")
        }

        Item { Kirigami.FormData.isSection: true }

        StepSlider {
            id: delay
            Kirigami.FormData.label: i18n("Trigger after:")
            enabled: enabledBox.checked
            steps: [0, 1, 2, 3, 5, 10, 15, 20, 30, 45, 60, 90, 120]
            value: page.cfg_alertDelay
            format: (v) => i18np("%1 second", "%1 seconds", v)
            onPicked: (v) => page.cfg_alertDelay = v
            ResetHandler { page: page; keys: ["alertDelay"] }
        }
        StepSlider {
            id: hyst
            Kirigami.FormData.label: i18n("Warn again only:")
            enabled: enabledBox.checked
            steps: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 15, 20, 30, 50]
            value: page.cfg_alertHysteresis
            format: (v) => i18n("%1 below the threshold", v)
            onPicked: (v) => page.cfg_alertHysteresis = v
            ResetHandler { page: page; keys: ["alertHysteresis"] }
        }
        StepSlider {
            id: cooldown
            Kirigami.FormData.label: i18n("Repeat at the earliest after:")
            enabled: enabledBox.checked
            steps: [0, 1, 2, 5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 240]
            value: page.cfg_alertCooldown
            format: (v) => i18np("%1 minute", "%1 minutes", v)
            onPicked: (v) => page.cfg_alertCooldown = v
            ResetHandler { page: page; keys: ["alertCooldown"] }
        }

        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            wrapMode: Text.WordWrap
            opacity: 0.7
            text: i18n("A notification is triggered when a value stays above its threshold for the set time – short spikes are ignored. You are warned again only after the value has dropped below the threshold by the set margin in between – in the sensor's unit, e.g. 3 °C or 3 %. Critical notifications stay until you close them and also appear in “Do not disturb” mode. Thresholds and the “Notify” switch are set per sensor on the “Sensors” page.")
        }

        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18n("Graphics card fans") }

        QQC2.CheckBox {
            id: fanBox
            ResetHandler { page: page; keys: ["fanWatch"] }
            Kirigami.FormData.label: i18n("Monitor fans:")
            text: i18n("Warn when a fan stands still or runs too slowly")
        }
        StepSlider {
            id: fanSlow
            Kirigami.FormData.label: i18n("Too slow below:")
            enabled: fanBox.checked
            steps: [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 65, 70, 75, 80, 85, 90]
            value: page.cfg_fanSlowPercent
            format: (v) => v === 0 ? i18n("Off (standstill only)")
                // xgettext:no-javascript-format
                : i18n("%1 % of the fastest fan", v)
            onPicked: (v) => page.cfg_fanSlowPercent = v
            ResetHandler { page: page; keys: ["fanSlowPercent"] }
        }
        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            wrapMode: Text.WordWrap
            opacity: 0.7
            text: i18n("For NVIDIA cards whose driver reports the measured fan speed. A fan that stands still for 15 seconds although the card wants it to turn is critical. A fan that runs clearly slower than the other fans of the card at the same setting for 30 seconds is a warning – the comparison needs at least two fans. Fans that the card switches off when idle do not trigger anything.")
        }

        Item { Kirigami.FormData.isSection: true }

        QQC2.Button {
            icon.name: "preferences-desktop-notification-bell"
            text: i18n("Send test notification")
            onClicked: testNote.sendEvent()
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
                    : i18n("Only affects the general settings on this page – your sensor tiles, their thresholds and the per-sensor “Notify” switch are kept.")
            }
        }
    }

    Notification {
        id: testNote
        componentName: "plasma_workspace"
        eventId: "notification"
        autoDelete: false
        title: i18n("VRAM temperature critical: 102 °C")
        text: i18n("Critical threshold of 100 °C exceeded.\n(This is just a test from Hardware Tiles.)")
        iconName: "temperature-high"
        urgency: Notification.CriticalUrgency
        flags: Notification.CloseOnTimeout
    }
}
