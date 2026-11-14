// SPDX-FileCopyrightText: 2026 Paderman
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.ksysguard.faces as Faces
import org.kde.kquickcontrols as KQC
import "Defaults.js" as Defaults
import "Hardware.js" as Hardware

KCM.SimpleKCM {
    id: page

    property string cfg_items
    property string cfg_gpuAddress
    property bool cfg_setupDone
    property string cfg_baseOrder
    property string cfg_layoutPreset
    property string cfg_layoutHash
    property string cfg_editTile

    HardwareProbe { id: probe }
    readonly property var gpu: Hardware.pickGpu(probe.hw, cfg_gpuAddress)

    readonly property var styles: [
        { value: "ring",  text: i18n("Ring") },
        { value: "bar",   text: i18n("Bar") },
        { value: "graph", text: i18n("History graph") },
        { value: "value", text: i18n("Value only") },
        { value: "curve", text: i18n("Fan curve") }
    ]
    readonly property var keys: Object.keys(Defaults.blank())

    ListModel { id: itemsModel }

    property bool loading: true
    Component.onCompleted: {
        load(Defaults.parse(cfg_items), false);
        const m = /^(.*)@(\d+)$/.exec(cfg_editTile || "");
        if (!m || Date.now() - parseInt(m[2]) >= 15000) return;
        const nw = /^new:(.*)$/.exec(m[1]);
        if (nw) {
            // "+ → Own tile …" in the widget: a new tile as an unsaved change –
            // "Cancel" leaves nothing behind. The request is used up right away.
            cfg_editTile = "";
            page.add({ label: i18n("New tile"), style: "ring", gpu: nw[1] });
            page.jumpTo(itemsModel.count - 1);
            return;
        }
        // opened from a tile's menu ("In den Einstellungen bearbeiten …"): go to that tile
        for (let i = 0; i < itemsModel.count; ++i)
            if (itemsModel.get(i).id === m[1]) { page.jumpTo(i); break; }
    }
    function jumpTo(i) {
        jumpTimer.target = i;
        jumpTimer.tries = 0;
        jumpTimer.lastY = -1;
        jumpTimer.start();
    }
    // index of the tile to scroll to / that flashes briefly (-1 = none)
    property int flashIndex: -1
    // The cards above the target still grow while the page builds up, so the
    // position is set again a few times until it no longer changes.
    Timer {
        id: jumpTimer
        property int target: -1
        property int tries: 0
        property real lastY: -1
        interval: 200
        onTriggered: {
            const card = cards.itemAt(target);
            const f = page.flickable;
            if (card && f) {
                const y = Math.max(0, Math.min(card.mapToItem(f.contentItem, 0, 0).y - Kirigami.Units.largeSpacing,
                                               f.contentHeight - f.height));
                f.contentY = y;
                if (tries === 0) { page.flashIndex = target; flashTimer.restart(); }
                if (Math.abs(y - lastY) < 1 && tries >= 2) return;   // settled
                lastY = y;
            }
            if (++tries < 12) restart();
        }
    }
    Timer { id: flashTimer; interval: 2500; onTriggered: page.flashIndex = -1 }

    function load(arr, store) {
        loading = true;
        itemsModel.clear();
        arr.forEach(it => itemsModel.append(it));
        loading = false;
        if (store) {
            cfg_baseOrder = "";   // a new layout has its own original order
            save();
        }
    }
    function save() {
        if (loading) return;
        const arr = [];
        for (let i = 0; i < itemsModel.count; ++i) {
            const o = itemsModel.get(i), it = {};
            keys.forEach(k => it[k] = o[k]);
            arr.push(it);
        }
        const json = JSON.stringify(arr);
        if (json !== cfg_items) cfg_items = json;
    }
    // graphics card of a tile: its own, else the main card
    function gpuOf(addr) { return addr ? Hardware.gpuByAddr(probe.hw, addr) : page.gpu; }
    // display: tokens resolved for the tile's GPU; storage: back to the {gpu} token
    function shown(id, addr) { return Hardware.resolveString(id || "", gpuOf(addr)); }
    function set(i, key, v) {
        if ((key === "sensorId" || key === "refSensorId" || key === "ySensorId") && typeof v === "string") {
            // a sensor of another card was picked -> the tile moves to that card
            const m = /^gpu\/(gpu\d+)\//.exec(v);
            const other = m ? probe.gpus.find(g => g.ksys === m[1]) : null;
            const cur = gpuOf(itemsModel.get(i).gpu);
            if (other && (!cur || other.addr !== cur.addr))
                itemsModel.setProperty(i, "gpu", page.gpu && other.addr === page.gpu.addr ? "" : other.addr);
            v = v.replace(/^gpu\/gpu\d+\//, "gpu/{gpu}/");
        }
        itemsModel.setProperty(i, key, v);
        save();
    }
    // entries of the per-tile GPU chooser: "" = main card, then every card
    readonly property var gpuChoices: [{ addr: "", text: i18n("Main card (%1)", page.gpu ? Hardware.gpuTag(page.gpu) : "–") }]
        .concat(probe.gpus.map(g => ({ addr: g.addr, text: Hardware.gpuTag(g) + "  (PCI " + g.addr.replace(/^0000:/, "") + ")" })))
    // translation function handed to the JS helpers (Hardware.build …)
    function tr(...a) { return i18n(...a); }

    // ---- layout templates
    readonly property var presets: [
        { key: "system", text: i18n("System overview"), icon: "computer",
          hint: i18n("Default tiles for your hardware: graphics card, processor, memory, SSDs, fans"),
          show: true, ok: probe.ready,
          build: () => Hardware.build(page.gpu, { gpuDetails: true, cpu: true, ram: true, storage: true, board: true, network: false }, probe.hw, page.tr) },
        { key: "allgpus", text: i18n("All graphics cards"), icon: "view-split-left-right",
          hint: i18n("One section per graphics card, plus comparison tiles and system"),
          show: probe.gpus.length > 1, ok: probe.ready,
          build: () => Hardware.build(probe.gpus, { gpuDetails: true, compare: true, cpu: true, ram: true, storage: true, board: false, network: false }, probe.hw, page.tr) },
        { key: "gpu", text: i18n("GPU focus"), icon: "video-display",
          hint: i18n("Only the selected graphics card, with all of its values"),
          show: true, ok: probe.ready && !!page.gpu,
          build: () => Hardware.build(page.gpu, { gpuDetails: true }, probe.hw, page.tr) }
    ]
    function presetName(key) {
        if (key === "wizard") return i18n("Setup wizard");
        const p = presets.find(p => p.key === key);
        return p ? p.text : "";
    }
    function loadPreset(p) {
        page.load(p.build(), true);
        cfg_layoutPreset = p.key;
        cfg_layoutHash = Defaults.signature(cfg_items);
    }
    readonly property string itemsSig: Defaults.signature(cfg_items)
    // layouts from before this was remembered: recognise an unchanged template by its tiles
    readonly property string detectedPreset: {
        if (cfg_layoutPreset || !probe.ready) return "";
        const p = presets.find(p => p.show && p.ok && Defaults.signature(JSON.stringify(p.build())) === itemsSig);
        return p ? p.key : "";
    }
    // template the tiles came from ("" = own layout) and whether they are still unchanged
    readonly property string basePreset: cfg_layoutPreset || detectedPreset
    readonly property bool layoutUnchanged: detectedPreset !== "" || (cfg_layoutPreset !== "" && itemsSig === cfg_layoutHash)

    // runs in the page: removing the tile destroys the card (and its button) that calls this
    function removeAt(i) {
        itemsModel.remove(i);
        save();
    }
    function add(o) {
        o.id = Defaults.newId();
        itemsModel.append(Defaults.normalize(o));
        save();
    }

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        // ---- layout templates
        Kirigami.AbstractCard {
            Layout.fillWidth: true
            contentItem: ColumnLayout {
                spacing: Kirigami.Units.smallSpacing
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.largeSpacing
                    QQC2.Label { text: i18n("Layout:"); font.weight: Font.DemiBold }
                    Flow {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        Repeater {
                            model: page.presets.filter(p => p.show)
                            QQC2.Button {
                                required property var modelData
                                readonly property bool isBase: page.basePreset === modelData.key
                                readonly property bool active: isBase && page.layoutUnchanged
                                text: modelData.text + (isBase && !page.layoutUnchanged ? " " + i18n("(modified)") : "")
                                icon.name: active ? "checkmark" : modelData.icon
                                highlighted: active
                                enabled: modelData.ok
                                onClicked: page.loadPreset(modelData)
                                QQC2.ToolTip.text: modelData.hint + "\n" + (active
                                    ? i18n("Is loaded and unchanged.")
                                    : isBase ? i18n("Clicking restores the template – your changes will be lost.")
                                             : i18n("Clicking replaces all tiles with this template."))
                                QQC2.ToolTip.visible: hovered
                                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                            }
                        }
                    }
                }
                RowLayout {
                    spacing: Kirigami.Units.smallSpacing
                    Kirigami.Icon {
                        Layout.preferredWidth: Kirigami.Units.iconSizes.small
                        Layout.preferredHeight: Kirigami.Units.iconSizes.small
                        source: page.layoutUnchanged ? "checkmark" : page.basePreset ? "document-edit" : "view-list-icons"
                        color: page.layoutUnchanged ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.textColor
                        isMask: true
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: page.layoutUnchanged ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.textColor
                        text: page.layoutUnchanged
                              ? (page.basePreset === "wizard"
                                 ? i18n("Created by the setup wizard – unchanged.")
                                 : i18n("Template “%1” is loaded – unchanged.", page.presetName(page.basePreset)))
                              : page.basePreset
                                ? i18n("Customised: based on “%1”, tiles have been changed.", page.presetName(page.basePreset))
                                : i18n("Custom layout.")
                    }
                }
                QQC2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    opacity: 0.6
                    font: Kirigami.Theme.smallFont
                    text: i18n("A template replaces all tiles – “System overview” restores the default tiles for your hardware. It takes effect only after “Apply”, “Cancel” keeps everything as it was.")
                }
            }
        }

        // ---- graphics card
        Kirigami.AbstractCard {
            Layout.fillWidth: true
            contentItem: GridLayout {
                columns: 2
                columnSpacing: Kirigami.Units.largeSpacing
                rowSpacing: Kirigami.Units.smallSpacing
                QQC2.Label { text: probe.gpus.length > 1 ? i18n("Main card:") : i18n("Graphics card:"); font.weight: Font.DemiBold }
                RowLayout {
                    Layout.fillWidth: true
                    QQC2.ComboBox {
                        wheelEnabled: false   // scrolling the page must not change the value
                        id: gpuBox
                        Layout.fillWidth: true
                        enabled: probe.gpus.length > 0
                        model: probe.gpus.map(g => g.name + (g.info ? "  ·  " + g.info : "") + "   (PCI " + g.addr.replace(/^0000:/, "") + ")")
                        currentIndex: page.gpu ? probe.gpus.findIndex(g => g.addr === page.gpu.addr) : -1
                        displayText: !probe.ready ? i18n("Searching …") : probe.gpus.length ? currentText : i18n("No supported graphics card found")
                        onActivated: (i) => page.cfg_gpuAddress = probe.gpus[i].addr
                    }
                    QQC2.ToolButton {
                        icon.name: "view-refresh"
                        onClicked: probe.refresh()
                        QQC2.ToolTip.text: i18n("Search again"); QQC2.ToolTip.visible: hovered
                    }
                }
                Item { width: 1 }
                QQC2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    font: Kirigami.Theme.smallFont
                    opacity: 0.6
                    text: probe.gpus.length > 1
                          ? i18n("GPU tiles without their own assignment show this card. Each tile can be set to another card below – or the “All graphics cards” layout (above) creates a separate section for each card.")
                          : i18n("All GPU tiles refer to this card.")
                }
                Item { width: 1 }
                RowLayout {
                    QQC2.Button {
                        icon.name: "tools-wizard"
                        text: i18n("Start setup wizard")
                        checkable: true
                        checked: !page.cfg_setupDone
                        onToggled: page.cfg_setupDone = !checked
                    }
                    QQC2.Label {
                        visible: !page.cfg_setupDone
                        text: i18n("Appears in the widget after “Apply”.")
                        opacity: 0.7
                    }
                }
            }
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: true
            type: Kirigami.MessageType.Information
            text: i18n("Sources: system sensors (ksystemstats – CPU, fans, NVMe, RAM …), NVIDIA values directly from nvidia-smi, or a shell command. On AMD GPUs the VRAM temperature is listed under “amdgpu … mem”. Tiles can also be edited directly in the widget: right-click → “Edit tiles”.")
        }

        Repeater {
            id: cards
            model: itemsModel
            delegate: Kirigami.AbstractCard {
                id: cardDelegate
                required property int index
                required property var model
                readonly property bool isCurve: model.style === "curve"
                Layout.fillWidth: true

                // frame that lights up when the page was opened for this tile
                Rectangle {
                    anchors.fill: parent
                    z: 10
                    radius: Kirigami.Units.cornerRadius
                    color: "transparent"
                    border.width: 2
                    border.color: Kirigami.Theme.highlightColor
                    opacity: page.flashIndex === cardDelegate.index ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 600 } }
                }

                contentItem: ColumnLayout {
                    spacing: Kirigami.Units.smallSpacing

                    // ---- title row
                    RowLayout {
                        Layout.fillWidth: true
                        Rectangle {
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 0.6
                            Layout.preferredHeight: Layout.preferredWidth
                            radius: width / 2
                            color: cardDelegate.model.color || Defaults.colorFor(cardDelegate.model.id)
                        }
                        QQC2.TextField {
                            Layout.fillWidth: true
                            placeholderText: i18n("Label (empty = automatic)")
                            text: cardDelegate.model.label
                            onTextEdited: page.set(cardDelegate.index, "label", text)
                        }
                        QQC2.ToolButton {
                            icon.name: "arrow-up"
                            enabled: cardDelegate.index > 0
                            onClicked: { itemsModel.move(cardDelegate.index, cardDelegate.index - 1, 1); page.save(); }
                            QQC2.ToolTip.text: i18n("Move up"); QQC2.ToolTip.visible: hovered
                        }
                        QQC2.ToolButton {
                            icon.name: "arrow-down"
                            enabled: cardDelegate.index < itemsModel.count - 1
                            onClicked: { itemsModel.move(cardDelegate.index, cardDelegate.index + 1, 1); page.save(); }
                            QQC2.ToolTip.text: i18n("Move down"); QQC2.ToolTip.visible: hovered
                        }
                        QQC2.ToolButton {
                            icon.name: "edit-copy"
                            onClicked: {
                                const o = itemsModel.get(cardDelegate.index), it = {};
                                page.keys.forEach(k => it[k] = o[k]);
                                it.id = Defaults.newId();
                                itemsModel.insert(cardDelegate.index + 1, it); page.save();
                            }
                            QQC2.ToolTip.text: i18n("Duplicate"); QQC2.ToolTip.visible: hovered
                        }
                        QQC2.ToolButton {
                            icon.name: "edit-delete-remove"
                            onClicked: page.removeAt(cardDelegate.index)
                            QQC2.ToolTip.text: i18n("Remove"); QQC2.ToolTip.visible: hovered
                        }
                    }

                    // ---- graphics card of this tile (only with several cards)
                    RowLayout {
                        Layout.fillWidth: true
                        visible: probe.gpus.length > 1 && Hardware.usesGpu(cardDelegate.model)
                        QQC2.Label { text: i18n("Graphics card:") }
                        QQC2.ComboBox {
                            wheelEnabled: false   // scrolling the page must not change the value
                            Layout.fillWidth: true
                            enabled: !cardDelegate.model.compare
                            model: page.gpuChoices
                            textRole: "text"
                            currentIndex: {
                                const a = cardDelegate.model.gpu || "";
                                const i = page.gpuChoices.findIndex(c => c.addr === a);
                                return i;
                            }
                            displayText: currentIndex >= 0 ? currentText
                                         : i18n("Not found (PCI %1)", (cardDelegate.model.gpu || "").replace(/^0000:/, ""))
                            onActivated: (i) => page.set(cardDelegate.index, "gpu", page.gpuChoices[i].addr)
                        }
                        QQC2.CheckBox {
                            text: i18n("Compare all cards")
                            enabled: !cardDelegate.isCurve
                            checked: cardDelegate.model.compare
                            onToggled: page.set(cardDelegate.index, "compare", checked)
                            QQC2.ToolTip.text: i18n("Shows the value of every graphics card in this tile – ring: one arc per card, graph: one line per card, bar/value: one row per card.")
                            QQC2.ToolTip.visible: hovered
                        }
                    }

                    // ---- main source (x axis for curves)
                    SourceEditor {
                        Layout.fillWidth: true
                        title: cardDelegate.isCurve ? i18n("Temperature (X):") : i18n("Source:")
                        source: cardDelegate.model.source
                        sensorId: page.shown(cardDelegate.model.sensorId, cardDelegate.model.gpu)
                        key: cardDelegate.model.key
                        command: cardDelegate.model.command
                        unit: cardDelegate.model.unit
                        onEdited: (field, value) => page.set(cardDelegate.index, field, value)
                    }

                    // ---- fan (y axis) for curves
                    SourceEditor {
                        Layout.fillWidth: true
                        visible: cardDelegate.isCurve
                        title: i18n("Fan (Y):")
                        source: cardDelegate.model.ySource
                        sensorId: page.shown(cardDelegate.model.ySensorId, cardDelegate.model.gpu)
                        key: cardDelegate.model.yKey
                        command: cardDelegate.model.yCommand
                        unit: cardDelegate.model.yUnit
                        onEdited: (field, value) => {
                            const map = { source: "ySource", sensorId: "ySensorId", key: "yKey", command: "yCommand", unit: "yUnit" };
                            page.set(cardDelegate.index, map[field], value);
                        }
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: Kirigami.Units.largeSpacing
                        rowSpacing: Kirigami.Units.smallSpacing

                        // reference / total sensor
                        QQC2.Label {
                            text: i18n("Total value:")
                            visible: !cardDelegate.isCurve && (cardDelegate.model.source === "sensor" || !cardDelegate.model.source)
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: !cardDelegate.isCurve && (cardDelegate.model.source === "sensor" || !cardDelegate.model.source)
                            spacing: 0
                            Faces.Choices {
                                Layout.fillWidth: true
                                supportsColors: false
                                labelsEditable: false
                                maxAllowedSensors: 1
                                selected: cardDelegate.model.refSensorId ? [page.shown(cardDelegate.model.refSensorId, cardDelegate.model.gpu)] : []
                                onSelectedChanged: {
                                    const id = (selected && selected.length) ? selected[0] : "";
                                    if (id !== page.shown(cardDelegate.model.refSensorId, cardDelegate.model.gpu)) page.set(cardDelegate.index, "refSensorId", id);
                                }
                            }
                            QQC2.Label {
                                text: i18n("Optional, e.g. “Total VRAM” → shows “1.0 / 10 GiB” and sets the maximum for bar/ring. NVIDIA values bring their total automatically.")
                                font: Kirigami.Theme.smallFont
                                opacity: 0.6
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }
                        }

                        QQC2.Label { text: i18n("Style:") }
                        RowLayout {
                            Layout.fillWidth: true
                            QQC2.ComboBox {
                                wheelEnabled: false   // scrolling the page must not change the value
                                model: page.styles
                                textRole: "text"
                                currentIndex: Math.max(0, page.styles.findIndex(s => s.value === cardDelegate.model.style))
                                onActivated: (i) => {
                                    const st = page.styles[i].value;
                                    page.set(cardDelegate.index, "style", st);
                                    if (st === "curve" && !cardDelegate.model.wide) page.set(cardDelegate.index, "wide", true);
                                }
                            }
                            QQC2.CheckBox {
                                text: i18n("Double width")
                                checked: cardDelegate.model.wide
                                onToggled: page.set(cardDelegate.index, "wide", checked)
                            }
                            QQC2.CheckBox {
                                text: i18n("In panel")
                                checked: cardDelegate.model.showInPanel
                                onToggled: page.set(cardDelegate.index, "showInPanel", checked)
                            }
                            QQC2.CheckBox {
                                text: i18n("Notify")
                                checked: cardDelegate.model.notify
                                enabled: cardDelegate.model.warn > 0 || cardDelegate.model.crit > 0
                                onToggled: page.set(cardDelegate.index, "notify", checked)
                                QQC2.ToolTip.text: i18n("Desktop notification when a threshold is exceeded")
                                QQC2.ToolTip.visible: hovered
                            }
                            Item { Layout.fillWidth: true }
                            KQC.ColorButton {
                                color: cardDelegate.model.color || Defaults.colorFor(cardDelegate.model.id)
                                onAccepted: (c) => page.set(cardDelegate.index, "color", c.toString())
                                QQC2.ToolTip.text: i18n("Accent colour"); QQC2.ToolTip.visible: hovered
                            }
                            QQC2.ToolButton {
                                icon.name: "edit-undo"
                                enabled: cardDelegate.model.color !== ""
                                onClicked: page.set(cardDelegate.index, "color", "")
                                QQC2.ToolTip.text: i18n("Automatic colour"); QQC2.ToolTip.visible: hovered
                            }
                        }

                        QQC2.Label { text: cardDelegate.isCurve ? i18n("Temperature axis:") : i18n("Range:") }
                        RowLayout {
                            Layout.fillWidth: true
                            QQC2.Label { text: i18n("Min"); opacity: 0.7 }
                            QQC2.SpinBox {
                                wheelEnabled: false   // scrolling the page must not change the value
                                from: -1000; to: 100000; editable: true
                                value: cardDelegate.model.min
                                onValueModified: page.set(cardDelegate.index, "min", value)
                            }
                            QQC2.Label { text: i18n("Max"); opacity: 0.7 }
                            QQC2.SpinBox {
                                wheelEnabled: false   // scrolling the page must not change the value
                                from: 0; to: 100000; editable: true
                                value: cardDelegate.model.max
                                textFromValue: (v) => v === 0 ? i18n("auto") : String(v)
                                valueFromText: (t) => t === i18n("auto") ? 0 : parseInt(t)
                                onValueModified: page.set(cardDelegate.index, "max", value)
                            }
                            QQC2.Label { text: i18n("Fan max"); opacity: 0.7; visible: cardDelegate.isCurve }
                            QQC2.SpinBox {
                                wheelEnabled: false   // scrolling the page must not change the value
                                visible: cardDelegate.isCurve
                                from: 0; to: 100000; editable: true
                                value: cardDelegate.model.yMax
                                textFromValue: (v) => v === 0 ? i18n("auto") : String(v)
                                valueFromText: (t) => t === i18n("auto") ? 0 : parseInt(t)
                                onValueModified: page.set(cardDelegate.index, "yMax", value)
                            }
                        }

                        QQC2.Label { text: i18n("Thresholds:") }
                        RowLayout {
                            Layout.fillWidth: true
                            Rectangle { width: 10; height: 10; radius: 5; color: "#ffb020" }
                            QQC2.SpinBox {
                                wheelEnabled: false   // scrolling the page must not change the value
                                from: 0; to: 100000; editable: true
                                value: cardDelegate.model.warn
                                textFromValue: (v) => v === 0 ? i18n("off") : String(v)
                                valueFromText: (t) => t === i18n("off") ? 0 : parseInt(t)
                                onValueModified: page.set(cardDelegate.index, "warn", value)
                            }
                            Rectangle { width: 10; height: 10; radius: 5; color: "#ff4d6d" }
                            QQC2.SpinBox {
                                wheelEnabled: false   // scrolling the page must not change the value
                                from: 0; to: 100000; editable: true
                                value: cardDelegate.model.crit
                                textFromValue: (v) => v === 0 ? i18n("off") : String(v)
                                valueFromText: (t) => t === i18n("off") ? 0 : parseInt(t)
                                onValueModified: page.set(cardDelegate.index, "crit", value)
                            }
                        }

                        QQC2.Label { text: i18n("Reference curve:"); visible: cardDelegate.isCurve }
                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: cardDelegate.isCurve
                            spacing: 0
                            QQC2.TextField {
                                Layout.fillWidth: true
                                font.family: "monospace"
                                placeholderText: "30:30 50:40 70:70 85:100"
                                text: cardDelegate.model.refCurve
                                onTextEdited: page.set(cardDelegate.index, "refCurve", text)
                            }
                            QQC2.Label {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                font: Kirigami.Theme.smallFont
                                opacity: 0.6
                                text: i18n("Optional: points “temperature:fan”, drawn dashed – e.g. your curve from GreenWithEnvy or CoolerControl. The solid line is learned by the widget from the measurements.")
                            }
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            QQC2.Button {
                icon.name: "list-add"
                text: i18n("Add sensor")
                onClicked: page.add({ style: "ring" })
            }
            QQC2.Button {
                icon.name: "list-add"
                text: i18n("Template …")
                onClicked: presetMenu.popup()
                QQC2.Menu {
                    id: presetMenu
                    QQC2.MenuItem {
                        text: i18n("GPU comparison: temperature (ring)")
                        visible: probe.gpus.length > 1; height: visible ? implicitHeight : 0
                        onTriggered: page.add({ label: i18n("GPU temperature"), sensorId: "gpu/{gpu}/temperature", style: "ring", max: 100, warn: 80, crit: 95, compare: true, notify: false })
                    }
                    QQC2.MenuItem {
                        text: i18n("GPU comparison: load (graph)")
                        visible: probe.gpus.length > 1; height: visible ? implicitHeight : 0
                        onTriggered: page.add({ label: i18n("GPU load"), sensorId: "gpu/{gpu}/usage", style: "graph", max: 100, wide: true, compare: true, notify: false })
                    }
                    QQC2.MenuItem {
                        text: i18n("GPU comparison: power (bar)")
                        visible: probe.gpus.length > 1; height: visible ? implicitHeight : 0
                        onTriggered: page.add({ label: i18n("GPU power"), sensorId: "gpu/{gpu}/power", style: "bar", compare: true, notify: false })
                    }
                    QQC2.MenuItem { text: i18n("GPU fan curve"); onTriggered: page.add({ label: i18n("GPU fan curve"), source: "nvidia", key: "temperature.gpu", style: "curve", min: 30, max: 90, ySource: "nvidia", yKey: "fan.speed", yMax: 100, wide: true }) }
                    QQC2.MenuItem { text: i18n("VRAM temperature (gddr6, NVIDIA)"); onTriggered: page.add({ label: i18n("VRAM temperature"), source: "command", command: "cat /run/gddr6/vram", unit: "°C", style: "ring", max: 110, warn: 90, crit: 100, showInPanel: true }) }
                    QQC2.MenuItem { text: i18n("VRAM used / total (NVIDIA)"); onTriggered: page.add({ label: i18n("VRAM used"), source: "nvidia", key: "memory.used", style: "bar" }) }
                    QQC2.MenuItem { text: i18n("GPU throttling (NVIDIA)"); onTriggered: page.add({ label: i18n("Throttling"), source: "nvidia", key: "clocks_event_reasons.active", style: "value", warn: 1, notify: false }) }
                    QQC2.MenuItem { text: i18n("CPU temperature (max.)"); onTriggered: page.add({ label: i18n("CPU temperature"), sensorId: "cpu/all/maximumTemperature", style: "ring", max: 100, warn: 75, crit: 90 }) }
                    QQC2.MenuItem { text: i18n("CPU power (power service)"); onTriggered: page.add({ label: i18n("CPU power"), source: "command", command: "cat /run/sensordeck-power/cpu", unit: "W", style: "value", notify: false }) }
                    QQC2.MenuItem { text: i18n("CPU usage (graph)"); onTriggered: page.add({ label: i18n("CPU load"), sensorId: "cpu/all/usage", style: "graph", max: 100, wide: true }) }
                    QQC2.MenuItem { text: i18n("Memory"); onTriggered: page.add({ label: i18n("Memory"), sensorId: "memory/physical/usedPercent", style: "bar", max: 100, warn: 80, crit: 92, notify: false }) }
                    QQC2.MenuItem { text: i18n("Network download"); onTriggered: page.add({ label: i18n("Download"), sensorId: "network/all/download", style: "graph" }) }
                }
            }
        }
    }
}
