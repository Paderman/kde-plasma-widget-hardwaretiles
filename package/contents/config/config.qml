// SPDX-FileCopyrightText: 2026 Paderman
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18n("Sensors")
        icon: "view-statistics"
        source: "ConfigSensors.qml"
    }
    ConfigCategory {
        name: i18n("Notifications")
        icon: "preferences-desktop-notification-bell"
        source: "ConfigAlerts.qml"
    }
    ConfigCategory {
        name: i18n("Appearance")
        icon: "preferences-desktop-color"
        source: "ConfigAppearance.qml"
    }
    ConfigCategory {
        name: i18n("Profiles")
        icon: "bookmarks"
        source: "ConfigProfiles.qml"
    }
    ConfigCategory {
        name: i18n("About & updates")
        icon: "help-about"
        source: "ConfigAbout.qml"
    }
}
