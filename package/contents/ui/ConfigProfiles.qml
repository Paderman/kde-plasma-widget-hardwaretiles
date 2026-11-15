// SPDX-FileCopyrightText: 2026 Paderman
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtCore
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtQuick.Dialogs as Dialogs
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support
import "Profiles.js" as Profiles
import "UpdateCheck.js" as UpdateCheck

// Profiles act at once (no "Apply"): they save or replace the stored view.
KCM.SimpleKCM {
    id: page

    HardwareProbe { id: probe }

    readonly property var cfg: Plasmoid.configuration
    readonly property var profiles: Profiles.list(cfg.profiles)
    readonly property string active: Profiles.find(profiles, cfg.activeProfile) ? cfg.activeProfile : ""
    readonly property var backup: { cfg.profileBackup; return Profiles.backup(cfg); }
    readonly property bool activeChanged: {
        cfg.items; cfg.tileStyle; cfg.tileScale; cfg.columns;
        return active !== "" && !Profiles.sameAs(cfg, Profiles.find(profiles, active));
    }

    function tileCount(p) {
        try { return JSON.parse(p.data.items || "[]").length; } catch (e) { return 0; }
    }
    function savedText(p) {
        const d = new Date(p.saved);
        return isNaN(d.getTime()) ? "" : d.toLocaleString(Qt.locale(), Locale.ShortFormat);
    }
    function say(type, text) { msg.type = type; msg.text = text; msg.visible = text !== ""; }

    function save(name) {
        Profiles.save(cfg, name, probe.gpus);
        nameField.text = "";
        say(Kirigami.MessageType.Positive, i18n("Saved as “%1”.", name));
    }
    function load(name) {
        const missing = Profiles.load(cfg, name, probe.gpus);
        if (missing > 0)
            say(Kirigami.MessageType.Warning, i18np("“%2” loaded. %1 tile belongs to a graphics card this computer does not have – it stays empty.",
                                                    "“%2” loaded. %1 tiles belong to a graphics card this computer does not have – they stay empty.", missing, name));
        else
            say(Kirigami.MessageType.Positive, i18n("“%1” loaded.", name));
    }
    function remove(name) {
        cfg.profiles = JSON.stringify(profiles.filter(p => p.name !== name));
        if (cfg.activeProfile === name) cfg.activeProfile = "";
        say(Kirigami.MessageType.Information, i18n("“%1” deleted.", name));
    }
    function rename(from, to) {
        to = to.trim();
        if (!to || to === from) return;
        if (Profiles.find(profiles, to)) { say(Kirigami.MessageType.Error, i18n("A profile named “%1” already exists.", to)); return; }
        cfg.profiles = JSON.stringify(profiles.map(p => p.name === from ? Object.assign({}, p, { name: to }) : p)
                                              .sort((a, b) => a.name.localeCompare(b.name)));
        if (cfg.activeProfile === from) cfg.activeProfile = to;
    }

    // ---- files: written and read with a shell command (QML has no file access)
    property var exportList: []
    readonly property string docs: String(StandardPaths.writableLocation(StandardPaths.DocumentsLocation))
    function exportTo(url) {
        const text = Profiles.exportText(exportList, UpdateCheck.current);
        exec.mode = "export";
        exec.connectSource("printf %s '" + Profiles.toBase64(text) + "' | base64 -d > " + Profiles.shellPath(url));
    }
    function importFrom(url) {
        exec.mode = "import";
        // at most 1 MiB – a profile file is a few kilobytes
        exec.connectSource("head -c 1048576 " + Profiles.shellPath(url));
    }
    property var pending: []          // imported profiles waiting for confirmation
    function addImported(list) {
        let all = profiles.slice();
        const names = [];
        list.forEach(p => {
            const n = Profiles.uniqueName(all, p.name);
            all.push(Object.assign({}, p, { name: n }));
            names.push(n);
        });
        all.sort((a, b) => a.name.localeCompare(b.name));
        cfg.profiles = JSON.stringify(all);
        say(Kirigami.MessageType.Positive, i18np("Imported: %2", "%1 profiles imported: %2", names.length, names.join(", ")));
    }

    P5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        property string mode: ""
        onNewData: (source, data) => {
            disconnectSource(source);
            if (data["exit code"] !== 0) {
                page.say(Kirigami.MessageType.Error, (mode === "export" ? i18n("The file could not be saved.") : i18n("The file could not be read."))
                         + (data["stderr"] ? "\n" + String(data["stderr"]).trim() : ""));
                return;
            }
            if (mode === "export") {
                page.say(Kirigami.MessageType.Positive, i18np("Profile exported.", "%1 profiles exported.", page.exportList.length));
                return;
            }
            const r = Profiles.parseImport(String(data["stdout"] || ""));
            if (r.error) {
                page.say(Kirigami.MessageType.Error, i18n("This file does not contain Hardware Tiles profiles."));
                return;
            }
            // tiles can run shell commands – show foreign ones before anything is stored
            const cmds = [];
            r.profiles.forEach(p => Profiles.commands(p.data).forEach(c => { if (cmds.indexOf(c) < 0) cmds.push(c); }));
            if (cmds.length) {
                page.pending = r.profiles;
                commandDialog.commands = cmds;
                commandDialog.open();
            } else {
                page.addImported(r.profiles);
            }
        }
    }

    Dialogs.FileDialog {
        id: exportDialog
        fileMode: Dialogs.FileDialog.SaveFile
        defaultSuffix: "json"
        currentFolder: page.docs
        nameFilters: [i18n("Hardware Tiles profiles (*.json)")]
        onAccepted: page.exportTo(selectedFile)
    }
    Dialogs.FileDialog {
        id: importDialog
        fileMode: Dialogs.FileDialog.OpenFile
        currentFolder: page.docs
        nameFilters: [i18n("Hardware Tiles profiles (*.json)"), i18n("All files (*)")]
        onAccepted: page.importFrom(selectedFile)
    }

    Kirigami.PromptDialog {
        id: commandDialog
        property var commands: []
        title: i18n("This profile runs commands")
        subtitle: i18n("Some tiles in it run these shell commands on this computer every few seconds:")
                  + "\n\n" + commands.join("\n") + "\n\n"
                  + i18n("Only import profiles from sources you trust.")
        standardButtons: QQC2.Dialog.NoButton
        customFooterActions: [
            Kirigami.Action {
                text: i18n("Import anyway")
                icon.name: "document-import"
                onTriggered: { page.addImported(page.pending); page.pending = []; commandDialog.close(); }
            },
            Kirigami.Action {
                text: i18n("Cancel")
                icon.name: "dialog-cancel"
                onTriggered: { page.pending = []; commandDialog.close(); }
            }
        ]
    }
    Kirigami.PromptDialog {
        id: deleteDialog
        property string name: ""
        title: i18n("Delete profile")
        subtitle: i18n("Delete the profile “%1”? The current view stays as it is.", name)
        standardButtons: QQC2.Dialog.Ok | QQC2.Dialog.Cancel
        onAccepted: page.remove(name)
    }
    Kirigami.PromptDialog {
        id: overwriteDialog
        property string name: ""
        title: i18n("Replace profile")
        subtitle: i18n("A profile named “%1” already exists. Replace it with the current view?", name)
        standardButtons: QQC2.Dialog.Ok | QQC2.Dialog.Cancel
        onAccepted: page.save(name)
    }
    Kirigami.PromptDialog {
        id: renameDialog
        property string name: ""
        title: i18n("Rename profile")
        standardButtons: QQC2.Dialog.Ok | QQC2.Dialog.Cancel
        onOpened: { renameField.text = name; renameField.selectAll(); renameField.forceActiveFocus(); }
        onAccepted: page.rename(name, renameField.text)
        QQC2.TextField {
            id: renameField
            onAccepted: renameDialog.accept()
        }
    }

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: i18n("A profile stores the current view: tiles and their order, appearance and notification settings. Loading a profile replaces the view at once – the previous one can be restored.")
        }

        Kirigami.InlineMessage {
            id: msg
            Layout.fillWidth: true
            visible: false
            showCloseButton: true
        }
        Kirigami.InlineMessage {
            Layout.fillWidth: true
            type: Kirigami.MessageType.Information
            visible: page.backup !== null
            text: i18n("The view before the last profile was loaded can be restored.")
            actions: [
                Kirigami.Action {
                    text: i18n("Undo profile change")
                    icon.name: "edit-undo"
                    onTriggered: { Profiles.undo(page.cfg); page.say(Kirigami.MessageType.Positive, i18n("Previous view restored.")); }
                }
            ]
        }

        // ---- save
        Kirigami.Heading { level: 3; text: i18n("Save current view") }
        RowLayout {
            Layout.fillWidth: true
            QQC2.TextField {
                id: nameField
                Layout.fillWidth: true
                Layout.maximumWidth: Kirigami.Units.gridUnit * 16
                maximumLength: 80
                placeholderText: i18n("Name, e.g. “Gaming”")
                onAccepted: saveBtn.clicked()
            }
            QQC2.Button {
                id: saveBtn
                text: i18n("Save")
                icon.name: "document-save"
                enabled: nameField.text.trim() !== ""
                onClicked: {
                    const n = nameField.text.trim();
                    if (Profiles.find(page.profiles, n)) { overwriteDialog.name = n; overwriteDialog.open(); }
                    else page.save(n);
                }
            }
        }
        QQC2.Button {
            visible: page.activeChanged
            text: i18n("Save changes to “%1”", page.active)
            icon.name: "document-save"
            onClicked: page.save(page.active)
        }

        // ---- list
        Kirigami.Heading { level: 3; text: i18n("Saved profiles") }
        QQC2.Label {
            visible: page.profiles.length === 0
            opacity: 0.7
            text: i18n("No profiles saved yet.")
        }
        Repeater {
            model: page.profiles
            delegate: RowLayout {
                id: row
                required property var modelData
                readonly property bool isActive: modelData.name === page.active
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Icon {
                    source: row.isActive ? "checkmark" : "bookmarks"
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                    opacity: row.isActive ? 1 : 0.6
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    QQC2.Label {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        font.bold: row.isActive
                        text: row.modelData.name
                              + (row.isActive ? "  ·  " + (page.activeChanged ? i18n("loaded, changed since") : i18n("loaded")) : "")
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        opacity: 0.7
                        font: Kirigami.Theme.smallFont
                        text: [i18np("%1 tile", "%1 tiles", page.tileCount(row.modelData)), page.savedText(row.modelData)]
                              .filter(s => s).join("  ·  ")
                    }
                }
                QQC2.Button {
                    text: i18n("Load")
                    icon.name: "document-open"
                    onClicked: page.load(row.modelData.name)
                }
                QQC2.ToolButton {
                    icon.name: "edit-rename"
                    display: QQC2.AbstractButton.IconOnly
                    text: i18n("Rename")
                    QQC2.ToolTip.text: text
                    QQC2.ToolTip.visible: hovered
                    onClicked: { renameDialog.name = row.modelData.name; renameDialog.open(); }
                }
                QQC2.ToolButton {
                    icon.name: "document-export"
                    display: QQC2.AbstractButton.IconOnly
                    text: i18n("Export to file …")
                    QQC2.ToolTip.text: text
                    QQC2.ToolTip.visible: hovered
                    onClicked: {
                        page.exportList = [row.modelData];
                        exportDialog.selectedFile = page.docs + "/" + encodeURIComponent(row.modelData.name.replace(/[\/\\:*?"<>|]/g, "_")) + ".json";
                        exportDialog.open();
                    }
                }
                QQC2.ToolButton {
                    icon.name: "edit-delete"
                    display: QQC2.AbstractButton.IconOnly
                    text: i18n("Delete")
                    QQC2.ToolTip.text: text
                    QQC2.ToolTip.visible: hovered
                    onClicked: { deleteDialog.name = row.modelData.name; deleteDialog.open(); }
                }
            }
        }

        // ---- files
        Kirigami.Separator { Layout.fillWidth: true }
        RowLayout {
            QQC2.Button {
                text: i18n("Import …")
                icon.name: "document-import"
                onClicked: importDialog.open()
            }
            QQC2.Button {
                text: i18n("Export all …")
                icon.name: "document-export"
                enabled: page.profiles.length > 0
                onClicked: {
                    page.exportList = page.profiles;
                    exportDialog.selectedFile = page.docs + "/hardwaretiles-profiles.json";
                    exportDialog.open();
                }
            }
            Kirigami.ContextualHelpButton {
                toolTipText: i18n("Exported files can be imported on another computer. Tiles of a graphics card that computer does not have are moved to a card of the same maker; learned fan curves are not part of a profile.")
            }
        }
    }
}
