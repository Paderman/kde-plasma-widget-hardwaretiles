// SPDX-FileCopyrightText: 2026 Paderman
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import "UpdateCheck.js" as UpdateCheck

KCM.SimpleKCM {
    id: page
    property alias cfg_updateCheck: autoBox.checked
    property bool cfg_updateAsked
    property int cfg_updateLastCheck
    property string cfg_updateLatest
    property string cfg_updateUrl
    property string cfg_updateDismissed

    readonly property string site: "https://github.com/Paderman/kde-plasma-widget-sensordeck"

    // result of "Check now": "" | busy | latest | newer | none | error
    property string checkState: ""
    property string checkVersion: ""
    property string checkUrl: ""
    property string checkError: ""

    function checkNow() {
        checkState = "busy";
        UpdateCheck.fetchLatest(r => {
            if (r.status === "ok") {
                checkVersion = r.version;
                checkUrl = r.url;
                checkState = UpdateCheck.newer(r.version, UpdateCheck.current) ? "newer" : "latest";
                // remember it like the automatic check does (saved with "Apply")
                page.cfg_updateLatest = r.version;
                page.cfg_updateUrl = r.url;
            } else {
                checkError = r.error || "";
                checkState = r.status;
            }
        });
    }

    Kirigami.FormLayout {
        QQC2.Label {
            Kirigami.FormData.label: i18n("Version:")
            text: UpdateCheck.current
        }
        QQC2.Label {
            Kirigami.FormData.label: i18n("Licence:")
            text: "GPL-2.0-or-later · © 2026 Paderman"
        }
        RowLayout {
            Kirigami.FormData.label: i18n("Links:")
            QQC2.Button {
                text: i18n("Website")
                icon.name: "internet-services"
                onClicked: Qt.openUrlExternally(page.site)
            }
            QQC2.Button {
                text: i18n("Report a problem")
                icon.name: "tools-report-bug"
                onClicked: Qt.openUrlExternally(page.site + "/issues/new?template=bug_report.yml")
            }
            QQC2.Button {
                text: i18n("Hardware not detected")
                icon.name: "computer"
                onClicked: Qt.openUrlExternally(page.site + "/issues/new?template=hardware_report.yml")
            }
        }

        Item { Kirigami.FormData.isSection: true }

        QQC2.CheckBox {
            id: autoBox
            Kirigami.FormData.label: i18n("Updates:")
            text: i18n("Look for new versions once a week")
            onToggled: page.cfg_updateAsked = true
        }
        RowLayout {
            QQC2.Button {
                text: i18n("Check now")
                icon.name: "view-refresh"
                enabled: page.checkState !== "busy"
                onClicked: page.checkNow()
            }
            QQC2.BusyIndicator {
                visible: page.checkState === "busy"
                Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                Layout.preferredWidth: Layout.preferredHeight
            }
            QQC2.Label {
                visible: text !== ""
                text: {
                    switch (page.checkState) {
                    case "latest": return i18n("You have the latest version.");
                    case "newer":  return i18n("Version %1 is available.", page.checkVersion);
                    case "none":   return i18n("No version has been published yet.");
                    case "error":  return i18n("GitHub could not be reached (%1).", page.checkError);
                    }
                    return "";
                }
            }
            QQC2.Button {
                visible: page.checkState === "newer"
                text: i18n("Open download page")
                icon.name: "download"
                onClicked: Qt.openUrlExternally(page.checkUrl || UpdateCheck.releasesPage)
            }
        }
        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 28
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            onLinkActivated: (link) => Qt.openUrlExternally(link)
            text: i18n("Privacy: the check only runs when you allow it or click “Check now”. Your computer then asks api.github.com for the newest version number. GitHub sees your IP address, as with any website visit; Sensor Deck sends no other data and keeps no statistics. Details: <a href=\"%1\">GitHub privacy statement</a>.",
                       "https://docs.github.com/site-policy/privacy-policies/github-general-privacy-statement")
        }
        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 28
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            text: i18n("Installed via “Get New Widgets” or Discover? Then Discover installs updates for you – the check here only informs you.")
        }
    }
}
