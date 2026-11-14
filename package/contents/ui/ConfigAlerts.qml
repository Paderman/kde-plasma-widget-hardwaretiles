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
    property alias cfg_alertDelay: delay.value
    property alias cfg_alertCooldown: cooldown.value
    property alias cfg_alertHysteresis: hyst.value

    // only this page's values (thresholds per sensor stay); saved with "Anwenden"
    function resetToDefaults() {
        const d = Defaults.settings.alerts;
        for (const k in d) page["cfg_" + k] = d[k];
    }

    Kirigami.FormLayout {
        QQC2.CheckBox {
            id: enabledBox
            Kirigami.FormData.label: i18n("Notifications:")
            text: i18n("Notify on critical values")
        }
        QQC2.CheckBox {
            id: warnBox
            enabled: enabledBox.checked
            text: i18n("Also when the warning threshold is reached")
        }
        QQC2.CheckBox {
            id: recoveryBox
            enabled: enabledBox.checked
            text: i18n("All-clear when the value is back to normal")
        }

        Item { Kirigami.FormData.isSection: true }

        QQC2.SpinBox {
            wheelEnabled: false   // scrolling the page must not change the value
            id: delay
            enabled: enabledBox.checked
            Kirigami.FormData.label: i18n("Trigger after:")
            from: 0; to: 120
            textFromValue: (v) => i18np("%1 second", "%1 seconds", v)
            valueFromText: (t) => parseInt(t)
        }
        QQC2.SpinBox {
            wheelEnabled: false   // scrolling the page must not change the value
            id: hyst
            enabled: enabledBox.checked
            Kirigami.FormData.label: i18n("Warn again only:")
            from: 0; to: 50
            textFromValue: (v) => i18n("%1 below the threshold", v)
            valueFromText: (t) => parseInt(t)
        }
        QQC2.SpinBox {
            wheelEnabled: false   // scrolling the page must not change the value
            id: cooldown
            enabled: enabledBox.checked
            Kirigami.FormData.label: i18n("Repeat at the earliest after:")
            from: 0; to: 240
            textFromValue: (v) => i18np("%1 minute", "%1 minutes", v)
            valueFromText: (t) => parseInt(t)
        }

        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            wrapMode: Text.WordWrap
            opacity: 0.7
            text: i18n("A notification is triggered when a value stays above its threshold for the set time – short spikes are ignored. You are warned again only after the value has dropped below the threshold by the set margin in between – in the sensor's unit, e.g. 3 °C or 3 %. Critical notifications stay until you close them and also appear in “Do not disturb” mode. Thresholds and the “Notify” switch are set per sensor on the “Sensors” page.")
        }

        Item { Kirigami.FormData.isSection: true }

        QQC2.Button {
            icon.name: "preferences-desktop-notification-bell"
            text: i18n("Send test notification")
            onClicked: testNote.sendEvent()
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
        text: i18n("Critical threshold of 100 °C exceeded.\n(This is just a test from Sensor Deck.)")
        iconName: "temperature-high"
        urgency: Notification.CriticalUrgency
        flags: Notification.CloseOnTimeout
    }
}
