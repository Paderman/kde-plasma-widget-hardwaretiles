// SPDX-FileCopyrightText: 2026 Paderman
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.plasma5support as P5Support
import "UpdateCheck.js" as UpdateCheck

KCM.SimpleKCM {
    id: page
    property alias cfg_updateCheck: autoBox.checked
    property bool cfg_updateAsked
    property int cfg_updateLastCheck
    property string cfg_updateLatest
    property string cfg_updateUrl
    property string cfg_updateDismissed

    // default for the ResetHandler (middle click / right-click menu): off, as the
    // check connects to github.com only when someone wants it
    readonly property var defaults: ({ updateCheck: false })
    function isDefault(keys) { return keys.every(k => page["cfg_" + k] === defaults[k]); }
    function resetKeys(keys) { keys.forEach(k => page["cfg_" + k] = defaults[k]); }

    readonly property string site: "https://github.com/Paderman/kde-plasma-widget-hardwaretiles"

    // result of "Check now": "" | busy | latest | newer | none | error
    property string checkState: ""
    property string checkVersion: ""
    property string checkUrl: ""
    property string checkError: ""

    // ---- troubleshooting: restart the Plasma desktop (plasmashell)
    // Through systemd when Plasma runs as a user service (usual since Plasma 5.25),
    // otherwise quit and start it detached, so the restart survives plasmashell.
    readonly property string restartCmd:
        "if systemctl --user --quiet is-active plasma-plasmashell.service; then "
        + "systemctl --user --no-block restart plasma-plasmashell.service; "
        + "else setsid sh -c 'kquitapp6 plasmashell; sleep 1; kstart plasmashell' >/dev/null 2>&1 & fi"
    property string restartError: ""
    P5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source);
            // on success this window is gone a moment later – only errors arrive here
            if (data["exit code"] !== 0)
                page.restartError = String(data["stderr"] || "").trim() || i18n("Exit code %1", data["exit code"]);
        }
    }
    Kirigami.PromptDialog {
        id: restartDialog
        title: i18n("Restart Plasma desktop?")
        subtitle: i18n("Desktop, panels and widgets disappear for a few seconds and then start again. Open programs keep running. This settings window closes – changes that have not been applied are lost.")
        standardButtons: Kirigami.Dialog.NoButton
        customFooterActions: [
            Kirigami.Action {
                text: i18n("Restart")
                icon.name: "view-refresh"
                onTriggered: {
                    restartDialog.close();
                    page.restartError = "";
                    exec.connectSource(page.restartCmd);
                }
            },
            Kirigami.Action {
                text: i18n("Cancel")
                icon.name: "dialog-cancel"
                onTriggered: restartDialog.close()
            }
        ]
    }

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
            Kirigami.ContextualHelpButton {
                toolTipText: i18n("“Report a problem” and “Hardware not detected” each open a form on GitHub.")
            }
        }

        Item { Kirigami.FormData.isSection: true }

        RowLayout {
            Kirigami.FormData.label: i18n("Updates:")
            QQC2.CheckBox {
                id: autoBox
                text: i18n("Look for new versions once a week")
                onToggled: page.cfg_updateAsked = true
                ResetHandler { page: page; keys: ["updateCheck"] }
            }
            Kirigami.ContextualHelpButton {
                toolTipText: i18n("Once a week the widget asks GitHub for the newest version number and shows a note in the widget when a new version is out.")
            }
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
            Kirigami.ContextualHelpButton {
                toolTipText: i18n("Installed via “Get New Widgets” or Discover? Then Discover installs updates for you – the check here only informs you.")
            }
        }
        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 28
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            onLinkActivated: (link) => Qt.openUrlExternally(link)
            text: i18n("Privacy: the check only runs when you allow it or click “Check now”. Your computer then asks api.github.com for the newest version number. GitHub sees your IP address, as with any website visit; Hardware Tiles sends no other data and keeps no statistics. Details: <a href=\"%1\">GitHub privacy statement</a>.",
                       "https://docs.github.com/site-policy/privacy-policies/github-general-privacy-statement")
        }

        Item { Kirigami.FormData.isSection: true }

        RowLayout {
            Kirigami.FormData.label: i18n("Troubleshooting:")
            QQC2.Button {
                text: i18n("Restart Plasma desktop …")
                icon.name: "view-refresh"
                onClicked: restartDialog.open()
            }
            Kirigami.ContextualHelpButton {
                toolTipText: i18n("Helps when the widget or the desktop no longer reacts properly, e.g. after an update. Same as “systemctl --user restart plasma-plasmashell” in a terminal. If it happens again, please report it with “Report a problem”.")
            }
        }
        Kirigami.InlineMessage {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 28
            visible: page.restartError !== ""
            type: Kirigami.MessageType.Error
            text: i18n("Plasma could not be restarted: %1", page.restartError)
        }
    }
}
