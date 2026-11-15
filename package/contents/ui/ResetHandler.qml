// SPDX-FileCopyrightText: 2026 Paderman
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Controls as QQC2

// Put inside a settings control: resets that one setting to its default –
// middle click directly, right click through a small menu. Left clicks and
// the wheel stay with the control. Takes effect like any change (Apply).
//
// page: the settings page with defaults (key -> value), resetKeys(keys)
// and isDefault(keys). keys: the cfg keys (without "cfg_") of this control.
Item {
    id: rh
    anchors.fill: parent
    // above the control's own parts (e.g. the text field of a spin box), so
    // middle and right clicks reach this first – middle click would paste there
    z: 1000

    property var page
    property var keys: []
    // the default as shown to the user; empty = worked out from the control
    property string valueText: ""

    readonly property var control: parent
    readonly property var def: page && keys.length ? page.defaults[keys[0]] : undefined
    readonly property string shownText: {
        if (valueText) return valueText;
        if (def === undefined || !control) return "";
        if (typeof def === "boolean") return def ? i18n("On") : i18n("Off");
        if (control.textFromValue) return control.textFromValue(def, Qt.locale());
        if (control.valueRole && Array.isArray(control.model)) {
            const m = control.model.find(e => e[control.valueRole] === def);
            return m ? m[control.textRole] : "";
        }
        return String(def);
    }
    readonly property bool atDefault: page ? page.isDefault(keys) : true

    TapHandler {
        acceptedButtons: Qt.MiddleButton
        onTapped: rh.page.resetKeys(rh.keys)
    }
    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: menu.popup()
    }
    KeyMenu {
        id: menu
        QQC2.MenuItem {
            icon.name: "edit-reset"
            text: rh.shownText ? i18n("Restore default (%1)", rh.shownText) : i18n("Restore default")
            enabled: !rh.atDefault
            onTriggered: rh.page.resetKeys(rh.keys)
        }
    }
}
