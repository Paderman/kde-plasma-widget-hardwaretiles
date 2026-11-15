// SPDX-FileCopyrightText: 2026 Paderman
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import "UpdateCheck.js" as UpdateCheck
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import "Hardware.js" as Hardware

Item {
    id: full

    // ---- size & columns -------------------------------------------------------
    // columns: 0 = automatic. fitToSize (desktop only): shrink the tiles until
    // everything fits without scrolling – never above the configured size.
    // size slider: while the settings are open their preview value wins
    readonly property real userScale: Number(root.setting("tileScale")) / 100
    readonly property bool inPopup: Plasmoid.formFactor === PlasmaCore.Types.Horizontal
                                    || Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property int columnsSetting: Number(root.setting("columns"))
    readonly property bool autoCols: columnsSetting <= 0
    // background opacity 0…1 – only on the desktop, the panel popup keeps its own
    readonly property real bgFactor: inPopup ? 1 : root.bgOpacity / 100
    readonly property bool fit: root.setting("fitToSize") && !inPopup
    // size of the smallest ring gauge – all rings use it (see ringTimer)
    property real ringSize: 0
    // extra height of the highest two-line ring name – rings stay level (see ringTimer)
    property real ringExtra: 0
    readonly property real minFitScale: 0.55

    // estimated height of a tile in grid units (mirrors SensorTile.implicitHeight)
    function tileUnits(it) {
        const n = it.compare && root.multiGpu ? root.shownGpus.filter(g => !!g.gpu).length : 1;
        const st = it.style;
        if (st === "curve") return 9.5;
        if (st === "ring" || st === "graph") return 7.4;
        if (st === "bar") return n > 1 ? Math.max(5, 2.8 + n * 1.75) : 5;
        if (n > 1) return Math.max(5, 2.6 + n * 1.3);
        return it.source === "pcie" ? 6.6 : 5.4;
    }
    // grid height in grid units for a column count (colW = column width in units)
    // -> {units, holes}; holes = empty cells at the end of rows
    function measure(c, colW) {
        const minW = st => st === "curve" ? 13 : st === "graph" ? 9 : 7.5;
        let total = 1.0;          // outer margins (2 × gap)
        let rowH = 0, col = 0, rows = 0, holes = 0;
        const endRow = () => {
            if (rowH > 0) { total += rowH; rows++; holes += c - col; }
            rowH = 0; col = 0;
        };
        entries.forEach((e, i) => {
            if (e.header) {
                endRow();
                total += 1.45 + (i > 0 ? 0.3 : 0);
                rows++;
                return;
            }
            const it = root.items[e.idx] || {};
            const left = c - col;
            let span = it.wide ? Math.min(2, c) : 1;
            if (span > left) {
                if (left * colW + (left - 1) * 0.5 >= minW(it.style)) span = left;
                else endRow();
            }
            rowH = Math.max(rowH, tileUnits(it));
            col += span;
            if (col >= c) endRow();
        });
        endRow();
        return { units: total + Math.max(0, rows - 1) * 0.5, holes: holes };
    }
    // -> {cols, scale}
    readonly property var plan: {
        const g = Kirigami.Units.gridUnit;
        const W = Math.max(1, width), H = Math.max(1, height);
        const fixed = Math.max(1, Math.min(8, columnsSetting));
        const cands = [];
        for (let c = autoCols ? 1 : fixed; c <= (autoCols ? 8 : fixed); ++c) {
            // tiles must stay at least ~7.5 units wide
            const widthU = W / (7.5 * c + 0.5 * (c + 1));
            let u = g * userScale;
            if (autoCols && widthU < u && c > 1) {
                if (!fit) continue;          // without fitting: only columns that keep the size
                u = widthU;
            }
            let m = measure(c, (W / u - 0.5 * (c + 1)) / c);
            if (fit) {
                // two passes: the gap filling of wide tiles depends on the size itself
                for (let k = 0; k < 2; ++k) {
                    u = Math.min(u, H / m.units * 0.985);
                    m = measure(c, (W / u - 0.5 * (c + 1)) / c);
                }
            }
            cands.push({ cols: c, u: u, holes: m.holes });
        }
        // fit: biggest tiles win (compared before clamping, so even when nothing fits
        // the layout that needs the least scrolling wins); among (nearly) equal sizes
        // the one with the fewest empty cells, then fewer columns.
        // no fit: as many columns as keep the configured size
        let best = null;
        if (fit) {
            const maxU = Math.max.apply(null, cands.map(x => x.u));
            cands.filter(x => x.u >= maxU * 0.99).forEach(x => {
                if (!best || x.holes < best.holes) best = x;
            });
        } else if (cands.length) {
            best = cands[cands.length - 1];
        }
        if (!best) best = { cols: 1, u: g * userScale };
        const minU = g * Math.min(userScale, minFitScale);
        return { cols: best.cols, scale: Math.max(best.u, fit ? minU : 0) / g };
    }
    // fine correction when the estimate was a bit off (measured after layout)
    property real fitCorrection: 1.0
    onPlanChanged: fitCorrection = 1.0

    readonly property real scale_: fit ? Math.max(minFitScale * 0.9, plan.scale * fitCorrection) : plan.scale
    readonly property int cols: plan.cols
    readonly property real gap: Math.round(Kirigami.Units.gridUnit * 0.5 * scale_)
    readonly property real u: Kirigami.Units.gridUnit * scale_

    // width of one grid column
    readonly property real colWidth: Math.max(1, (scroll.availableWidth - (cols - 1) * gap) / cols)
    // smallest width a tile still looks good at
    function minTileWidth(style) {
        return (style === "curve" ? 13 : style === "graph" ? 9 : 7.5) * u;
    }
    // What the grid shows: tiles ({idx, group}) and – in section mode – a
    // full-width header per card ({header, group, title, info, slot}).
    // Tiles keep their relative order inside a section, so moving within a
    // section maps 1:1 onto the stored order.
    readonly property string sectionMode: root.setting("gpuSectionMode")
                                          || (root.setting("gpuSections") ? "auto" : "never")
    readonly property bool sections: sectionMode === "always" ? root.shownGpus.length > 0
                                   : sectionMode === "never" ? false : root.multiGpu
    readonly property var entries: {
        const its = root.items;
        if (!sections) {
            const flat = its.map((it, i) => ({ idx: i, group: "" })).filter(e => !root.compareCollapsed(e.idx));
            if (editing) flat.push({ add: true, group: "" });
            return flat;
        }
        const groups = root.shownGpus.map(g => ({
            key: g.addr, title: g.tag, slot: g.slot,
            addr: g.gpu ? g.addr : "", driver: g.gpu ? g.gpu.driver : "",
            info: g.gpu ? [g.gpu.name !== g.tag ? g.gpu.name : "", g.gpu.info, "PCI " + g.addr.replace(/^0000:/, "")]
                              .filter(x => !!x).join("  ·  ")
                        : "",
            idxs: []
        }));
        const cmp = { key: "~compare", title: i18n("Comparison"), slot: -1, addr: "", driver: "",
                      info: root.shownGpus.map(g => g.tag).join("  ·  "), idxs: [] };
        const sys = { key: "~system", title: i18n("System"), slot: -1, addr: "", driver: "", info: "", idxs: [] };
        const byAddr = {};
        groups.forEach(g => byAddr[g.key] = g);
        its.forEach((it, i) => {
            let g = sys;
            if (it.compare) g = groups.length > 1 ? cmp : (groups[0] || sys);   // one card: nothing to compare
            else if (Hardware.usesGpu(root.rawItems[i])) g = byAddr[it.gpuAddr] || sys;
            // the PCIe link of a card is shown in its section header instead
            if (it.source === "pcie" && g.addr && (!it.key || it.key === g.addr)) return;
            if (root.compareCollapsed(i)) return;
            g.idxs.push(i);
        });
        const out = [];
        groups.concat([cmp, sys]).forEach(g => {
            if (!g.idxs.length) return;
            out.push({ header: true, group: g.key, title: g.title, info: g.info, slot: g.slot, addr: g.addr, driver: g.driver });
            g.idxs.forEach(i => out.push({ idx: i, group: g.key }));
            if (editing) out.push({ add: true, group: g.key });
        });
        return out;
    }

    // Column span per entry. "Wide" tiles take 2 columns – but if only one column
    // is left in the current row and that is wide enough for the tile, they fill
    // the gap instead of wrapping to the next row. Headers take a whole row.
    readonly property var spans: {
        const out = [];
        let col = 0;
        entries.forEach(e => {
            if (e.header) { out.push(cols); col = 0; return; }
            const it = root.items[e.idx] || {};
            const left = cols - col;
            let span = it.wide ? Math.min(2, cols) : 1;
            if (span > left) {
                const w = left * colWidth + (left - 1) * gap;
                if (w >= minTileWidth(it.style)) span = left;
                else col = 0;        // wraps to the next row
            }
            out.push(span);
            col += span;
            if (col >= cols) col = 0;
        });
        return out;
    }
    // "Edit tiles" mode (context menu): drag tiles to move them, × removes,
    // + adds – until it is ended. Not stored: closing the popup ends it too.
    property bool editing: false
    onVisibleChanged: if (!visible) editing = false
    readonly property bool canEdit: !Plasmoid.immutable && !root.needsSetup
    onCanEditChanged: if (!canEdit) editing = false

    Layout.minimumWidth: Kirigami.Units.gridUnit * 8
    Layout.minimumHeight: Kirigami.Units.gridUnit * 5
    Layout.preferredWidth: root.needsSetup ? Kirigami.Units.gridUnit * 30 : grid.implicitWidth + gap * 2
    Layout.preferredHeight: root.needsSetup ? Kirigami.Units.gridUnit * 30 : grid.implicitHeight + gap * 2

    // ---- drag & drop --------------------------------------------------------
    property int dragFrom: -1
    property int dragTo: -1
    property point grabOffset: Qt.point(0, 0)

    function tileIndexAt(p) {
        for (let i = 0; i < tiles.count; ++i) {
            const t = tiles.itemAt(i);
            if (!t || !entries[i] || entries[i].idx === undefined) continue;
            const q = t.mapToItem(full, 0, 0);
            if (p.x >= q.x && p.x < q.x + t.width && p.y >= q.y && p.y < q.y + t.height) return i;
        }
        return -1;
    }
    function startDrag(i, tile, pos) {
        grabOffset = pos;
        dragFrom = i;
        dragTo = -1;
        proxy.width = tile.width;
        proxy.height = tile.height;
        const q = tile.mapToItem(full, 0, 0);
        proxy.x = q.x; proxy.y = q.y;
        tile.grabToImage(result => {
            if (dragFrom === i) { proxy.source = result.url; tile.dragging = true; }
        });
    }
    function updateDrag(p) {
        proxy.x = p.x - grabOffset.x;
        proxy.y = p.y - grabOffset.y;
        const t = tileIndexAt(p);
        // only within the same section (a tile can't change its graphics card by dragging)
        dragTo = t !== dragFrom && t >= 0 && entries[t].group === entries[dragFrom].group ? t : -1;
    }
    function finishDrag() {
        const from = dragFrom, to = dragTo;
        const t = tiles.itemAt(from);
        if (t && t.item) t.item.dragging = false;
        dragFrom = -1; dragTo = -1;
        proxy.source = "";
        if (from >= 0 && to >= 0 && entries[from] && entries[to])
            root.moveItem(entries[from].idx, entries[to].idx);
    }
    function cancelDrag() {
        dragTo = -1;
        finishDrag();
    }

    // first-run setup
    Loader {
        anchors.fill: parent
        active: root.needsSetup
        z: 10
        sourceComponent: SetupWizard {
            probe: root.hardware
            preselect: Plasmoid.configuration.gpuAddress
            canCancel: root.rawItems.length > 0
            onFinished: (addr, opts) => root.applySetup(addr, opts)
            onCancelled: Plasmoid.configuration.setupDone = true
        }
    }

    // one-time question about the update check / note about a new version
    Kirigami.InlineMessage {
        id: banner
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: full.gap }
        visible: !root.needsSetup && (root.askUpdates || root.updateBanner)
        type: Kirigami.MessageType.Information
        showCloseButton: !root.askUpdates
        onLinkActivated: (link) => Qt.openUrlExternally(link)
        text: root.askUpdates
            ? i18n("Should Sensor Deck look for new versions once a week? It then connects to github.com – GitHub sees your IP address, as with any website visit; nothing else is sent. You can change this any time in the settings.")
            : i18n("Sensor Deck %1 is available (installed: %2).", Plasmoid.configuration.updateLatest, UpdateCheck.current)
        actions: [
            Kirigami.Action {
                visible: root.askUpdates
                text: i18n("Yes, check weekly")
                icon.name: "dialog-ok"
                onTriggered: root.answerUpdates(true)
            },
            Kirigami.Action {
                visible: root.askUpdates
                text: i18n("No, thanks")
                icon.name: "dialog-cancel"
                onTriggered: root.answerUpdates(false)
            },
            Kirigami.Action {
                visible: !root.askUpdates
                text: i18n("Open download page")
                icon.name: "download"
                onTriggered: root.openUpdatePage()
            }
        ]
        onVisibleChanged: if (!visible && !root.askUpdates && root.updateBanner)
            Plasmoid.configuration.updateDismissed = Plasmoid.configuration.updateLatest
    }

    // shown while the "Edit tiles" mode is on
    Kirigami.InlineMessage {
        id: editBanner
        anchors {
            left: parent.left; right: parent.right; margins: full.gap
            top: banner.visible ? banner.bottom : parent.top
        }
        visible: full.editing
        type: Kirigami.MessageType.Positive
        icon.source: "document-edit"
        text: i18n("Drag a tile to move it within its section. × removes a tile, + adds one.")
        actions: [
            Kirigami.Action {
                visible: root.canUndoRemove
                text: root.canUndoRemove ? i18n("Restore “%1”", root.undoRemove.label) : ""
                icon.name: "edit-undo"
                onTriggered: root.restoreRemoved()
            },
            Kirigami.Action {
                visible: root.undoOrder !== null
                text: i18n("Undo last move")
                icon.name: "edit-undo"
                onTriggered: root.undoMove()
            },
            Kirigami.Action {
                text: i18n("Done")
                icon.name: "dialog-ok-apply"
                onTriggered: full.editing = false
            }
        ]
    }

    QQC2.ScrollView {
        id: scroll
        visible: !root.needsSetup
        anchors.fill: parent
        anchors.margins: full.gap
        anchors.topMargin: full.gap + (banner.visible ? banner.height + full.gap : 0)
                           + (editBanner.visible ? editBanner.height + full.gap : 0)
        contentWidth: availableWidth
        QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

        // all ring gauges get the size of the smallest one (see SensorTile.ringLimit)
        Timer {
            id: ringTimer
            interval: 0
            onTriggered: {
                let m = Infinity, e = 0;
                for (let i = 0; i < tiles.count; ++i) {
                    const l = tiles.itemAt(i);
                    const t = l && l.isTile ? l.item : null;
                    if (t && t.style === "ring" && !t.comparing && t.ringNatural > 0) {
                        m = Math.min(m, t.ringNatural);
                        e = Math.max(e, t.ringExtra);
                    }
                }
                full.ringSize = m === Infinity ? 0 : m;
                full.ringExtra = e;
            }
        }

        GridLayout {
            id: grid
            onImplicitHeightChanged: if (full.fit) correctTimer.restart()
            width: parent.width
            columns: full.cols
            columnSpacing: full.gap
            rowSpacing: full.gap
            uniformCellWidths: true

            Repeater {
                id: tiles
                model: full.entries
                delegate: Loader {
                    id: entry
                    required property var modelData
                    required property int index
                    readonly property bool isHeader: modelData.header === true
                    readonly property bool isAdd: modelData.add === true
                    readonly property bool isTile: !isHeader && !isAdd
                    Layout.columnSpan: full.spans[index] || 1
                    Layout.fillWidth: true
                    Layout.fillHeight: !isHeader
                    Layout.preferredWidth: item ? (isHeader ? 0 : item.implicitWidth * Layout.columnSpan) : 0
                    Layout.minimumHeight: item ? item.implicitHeight : 0
                    Layout.maximumHeight: isHeader && item ? item.implicitHeight : Number.POSITIVE_INFINITY
                    Layout.topMargin: isHeader && index > 0 ? full.gap * 0.6 : 0
                    sourceComponent: isHeader ? headerComponent : isAdd ? addComponent : tileComponent

                    // "+" field at the end of a section (edit mode): opens the suggestions
                    property Component addComponent: QQC2.AbstractButton {
                        id: addField
                        implicitWidth: full.u * 7.5
                        implicitHeight: full.u * 5.4
                        hoverEnabled: true
                        Accessible.name: i18n("Add tile")
                        onClicked: addMenu.openFor(entry.modelData.group, addField)
                        background: Rectangle {
                            radius: Kirigami.Units.cornerRadius * 2
                            color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b,
                                           addField.down ? 0.22 : addField.hovered ? 0.14 : 0.06)
                            border.width: 1
                            border.color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b,
                                                  addField.hovered ? 0.8 : 0.45)
                        }
                        contentItem: ColumnLayout {
                            spacing: Kirigami.Units.smallSpacing
                            Item { Layout.fillHeight: true }
                            Kirigami.Icon {
                                Layout.alignment: Qt.AlignHCenter
                                source: "list-add"
                                implicitWidth: Math.round(full.u * 1.6)
                                implicitHeight: implicitWidth
                                color: Kirigami.Theme.highlightColor
                            }
                            QQC2.Label {
                                Layout.alignment: Qt.AlignHCenter
                                Layout.maximumWidth: addField.width - Kirigami.Units.smallSpacing * 2
                                text: i18n("Add tile")
                                font.pixelSize: Math.max(9, Math.round(full.u * 0.75))
                                elide: Text.ElideRight
                                opacity: 0.85
                            }
                            Item { Layout.fillHeight: true }
                        }
                    }

                    property Component headerComponent: GpuSectionHeader {
                        title: entry.modelData.title
                        info: entry.modelData.info
                        accent: Hardware.gpuColor(entry.modelData.slot, root.lightTheme)
                        addr: entry.modelData.addr || ""
                        driver: entry.modelData.driver || ""
                        interval: root.interval
                        u: full.u
                        fillFactor: full.bgFactor
                        backing: root.tileBacking
                    }

                    property Component tileComponent: SensorTile {
                        id: tileDelegate
                        ringLimit: full.ringSize
                        ringExtraMax: full.ringExtra
                        onRingNaturalChanged: ringTimer.restart()
                        onRingExtraChanged: ringTimer.restart()
                        readonly property int itemIndex: entry.modelData.idx
                        srcs: root.compareSources(itemIndex)
                        // compare tile with only one card left: show that card like a normal tile
                        src: srcs.length === 1 ? srcs[0].src : root.source(itemIndex)
                        style: (root.items[itemIndex] || {}).style || "ring"
                        tileStyle: root.setting("tileStyle")
                        fillFactor: full.bgFactor
                        backing: root.tileBacking
                        scale_: full.scale_
                        gpuColor: full.sections || !root.multiGpu ? "transparent"
                                  : Hardware.gpuColor((root.items[itemIndex] || {}).gpuSlot, root.lightTheme)
                        dropTarget: full.dragTo === entry.index
                        inSection: full.sections
                        arranging: full.editing

                        // edit mode: a plain left drag moves the tile
                        MouseArea {
                            anchors.fill: parent
                            enabled: full.editing
                            acceptedButtons: Qt.LeftButton
                            preventStealing: true
                            cursorShape: full.dragFrom === entry.index ? Qt.ClosedHandCursor : Qt.OpenHandCursor

                            property point pressPos
                            readonly property bool mine: full.dragFrom === entry.index

                            onPressed: mouse => pressPos = Qt.point(mouse.x, mouse.y)
                            onPositionChanged: mouse => {
                                if (mine) {
                                    full.updateDrag(mapToItem(full, mouse.x, mouse.y));
                                    return;
                                }
                                if (full.dragFrom >= 0) return;
                                if (Math.hypot(mouse.x - pressPos.x, mouse.y - pressPos.y) < Qt.styleHints.startDragDistance)
                                    return;
                                full.startDrag(entry.index, tileDelegate, pressPos);
                                full.updateDrag(mapToItem(full, mouse.x, mouse.y));
                            }
                            onReleased: if (mine) full.finishDrag()
                            onCanceled: if (mine) full.cancelDrag()
                        }

                        // edit mode: small red × in the top right corner removes the tile
                        QQC2.AbstractButton {
                            id: removeBtn
                            visible: full.editing && full.dragFrom < 0
                            z: 200
                            width: Math.round(Math.max(Kirigami.Units.iconSizes.small + 6, full.u * 1.3))
                            height: width
                            anchors { top: parent.top; right: parent.right; margins: Math.round(full.u * 0.25) }
                            hoverEnabled: true
                            Accessible.name: i18n("Remove tile")
                            onClicked: root.removeTile(tileDelegate.itemIndex, tileDelegate.src ? tileDelegate.src.label : "")
                            background: Rectangle {
                                radius: width / 2
                                color: removeBtn.down ? Qt.darker(Kirigami.Theme.negativeTextColor, 1.25)
                                       : removeBtn.hovered ? Qt.lighter(Kirigami.Theme.negativeTextColor, 1.1)
                                       : Kirigami.Theme.negativeTextColor
                                border.width: 1
                                border.color: Qt.rgba(0, 0, 0, 0.25)
                            }
                            contentItem: Kirigami.Icon {
                                source: "window-close"
                                color: "white"
                                isMask: true
                                implicitWidth: Math.round(removeBtn.width * 0.6)
                                implicitHeight: implicitWidth
                            }
                            QQC2.ToolTip.text: i18n("Remove tile")
                            QQC2.ToolTip.visible: hovered && root.setting("tooltipsEnabled")
                            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                        }
                    }
                }
            }
        }
    }

    // ---- menu entries shared by the tile menu and the widget menu
    component HidingItem: QQC2.MenuItem {
        height: visible ? implicitHeight : 0
    }
    component UpdateItem: HidingItem {
        text: root.updateAvailable ? i18n("Sensor Deck %1 is available – open download page", Plasmoid.configuration.updateLatest) : ""
        icon.name: "update-none"
        visible: root.updateAvailable
        onTriggered: root.openUpdatePage()
    }
    component RestoreRemovedItem: HidingItem {
        text: root.canUndoRemove ? i18n("Restore “%1”", root.undoRemove.label) : ""
        icon.name: "edit-undo"
        visible: root.canUndoRemove
        onTriggered: root.restoreRemoved()
    }
    component EditModeItem: HidingItem {
        text: full.editing ? i18n("Finish editing") : i18n("Edit tiles")
        icon.name: full.editing ? "dialog-ok-apply" : "document-edit"
        visible: full.canEdit
        onTriggered: full.editing = !full.editing
    }
    component UndoMoveItem: HidingItem {
        text: i18n("Undo last move")
        icon.name: "edit-undo"
        visible: root.undoOrder !== null
        onTriggered: root.undoMove()
    }
    component ResetOrderItem: QQC2.MenuItem {
        text: i18n("Restore original arrangement")
        icon.name: "edit-reset"
        enabled: root.orderChanged
        onTriggered: root.resetOrder()
    }
    component ConfigureItem: QQC2.MenuItem {
        text: i18n("Configure Sensor Deck …")
        icon.name: "configure"
        onTriggered: Plasmoid.internalAction("configure").trigger()
    }
    // submenu with one checkable entry per value of a setting; applies at once
    component ChoiceMenu: QQC2.Menu {
        id: choice
        popupType: QQC2.Popup.Window
        property var options: []         // [{ text, value }]
        property string current: ""
        signal chosen(string value)
        Instantiator {
            model: choice.options
            delegate: QQC2.MenuItem {
                id: opt
                required property var modelData
                text: modelData.text
                checkable: true
                checked: choice.current === modelData.value
                // clicking breaks the binding – restore it
                onTriggered: { choice.chosen(modelData.value); opt.checked = Qt.binding(() => choice.current === opt.modelData.value); }
            }
            onObjectAdded: (index, object) => choice.insertItem(index, object)
            onObjectRemoved: (index, object) => choice.removeItem(object)
        }
    }
    component TileStyleMenu: ChoiceMenu {
        title: i18n("Tile style")
        icon.name: "preferences-desktop-color"
        options: [
            { text: i18n("Glass (subtle)"), value: "glass" },
            { text: i18n("Filled"), value: "solid" },
            { text: i18n("Outline (accent colour)"), value: "outline" }
        ]
        current: Plasmoid.configuration.tileStyle || "glass"
        onChosen: value => Plasmoid.configuration.tileStyle = value
    }
    component SectionsMenu: ChoiceMenu {
        title: i18n("Sections per graphics card")
        icon.name: "view-split-top-bottom"
        options: [
            { text: i18n("From two graphics cards"), value: "auto" },
            { text: i18n("Always (even with one card)"), value: "always" },
            { text: i18n("Never (several cards: coloured edge)"), value: "never" }
        ]
        current: full.sectionMode
        onChosen: value => Plasmoid.configuration.gpuSectionMode = value
    }

    // saved views (Settings → Profiles): load with one click
    component ProfilesMenu: QQC2.Menu {
        id: pm
        popupType: QQC2.Popup.Window
        title: i18n("Profile")
        icon.name: "bookmarks"
        QQC2.MenuItem {
            text: i18n("No profiles saved yet")
            enabled: false
            visible: root.profiles.length === 0
            height: visible ? implicitHeight : 0
        }
        Instantiator {
            model: root.profiles
            delegate: QQC2.MenuItem {
                id: pi
                required property var modelData
                text: modelData.name + (modelData.name === root.activeProfile && root.profileChanged ? "  ·  " + i18n("changed") : "")
                checkable: true
                checked: modelData.name === root.activeProfile
                onTriggered: { root.loadProfile(modelData.name); pi.checked = Qt.binding(() => pi.modelData.name === root.activeProfile); }
            }
            onObjectAdded: (index, object) => pm.insertItem(index + 1, object)
            onObjectRemoved: (index, object) => pm.removeItem(object)
        }
        QQC2.MenuSeparator { }
        HidingItem {
            text: i18n("Undo profile change")
            icon.name: "edit-undo"
            visible: root.profileBackup !== null
            onTriggered: root.undoProfileChange()
        }
        QQC2.MenuItem {
            text: i18n("Manage profiles …")
            icon.name: "configure"
            onTriggered: {
                Plasmoid.configuration.openPage = "ConfigProfiles.qml@" + Date.now();
                Plasmoid.internalAction("configure").trigger();
            }
        }
    }

    // hint where Plasma's own widget actions are (only where its handle exists)
    component HandleHintItem: HidingItem {
        text: i18n("Tip: press and hold an empty spot – move, resize, remove widget")
        icon.name: "help-hint"
        enabled: false
        visible: !full.inPopup && !Plasmoid.immutable
    }

    // ---- context menu of a tile -------------------------------------------------
    QQC2.Menu {
        id: tileMenu
        // own window: the compositor keeps it on screen and above the panel
        popupType: QQC2.Popup.Window
        property int idx: -1
        property string name: ""
        readonly property var it: root.rawItems[idx] || ({})
        property var card: null
        function openFor(i, src, tile) {
            idx = i;
            name = src ? src.label : "";
            card = tile;
            if (card) card.menuOpen = true;
            popup();
        }
        onClosed: { if (card) card.menuOpen = false; card = null; }
        // checkable items lose their binding when clicked – set it again
        function rebind(item, fn) { item.checked = Qt.binding(fn); }

        QQC2.MenuItem {
            text: tileMenu.name
            enabled: false
        }
        QQC2.MenuItem {
            text: i18n("Edit in settings …")
            icon.name: "document-edit"
            onTriggered: root.editTile(tileMenu.idx)
        }
        QQC2.MenuSeparator { }
        QQC2.Menu {
            id: styleMenu
            // own window: the compositor keeps it on screen and above the panel
            popupType: QQC2.Popup.Window
            title: i18n("Appearance")
            enabled: tileMenu.it.style !== "curve"
            QQC2.MenuItem {
                id: miRing
                text: i18n("Ring"); checkable: true; checked: tileMenu.it.style === "ring"
                onTriggered: { root.setTileProp(tileMenu.idx, "style", "ring"); tileMenu.rebind(miRing, () => tileMenu.it.style === "ring"); }
            }
            QQC2.MenuItem {
                id: miBar
                text: i18n("Bar"); checkable: true; checked: tileMenu.it.style === "bar"
                onTriggered: { root.setTileProp(tileMenu.idx, "style", "bar"); tileMenu.rebind(miBar, () => tileMenu.it.style === "bar"); }
            }
            QQC2.MenuItem {
                id: miGraph
                text: i18n("History graph"); checkable: true; checked: tileMenu.it.style === "graph"
                onTriggered: { root.setTileProp(tileMenu.idx, "style", "graph"); tileMenu.rebind(miGraph, () => tileMenu.it.style === "graph"); }
            }
            QQC2.MenuItem {
                id: miValue
                text: i18n("Value only"); checkable: true; checked: tileMenu.it.style === "value"
                onTriggered: { root.setTileProp(tileMenu.idx, "style", "value"); tileMenu.rebind(miValue, () => tileMenu.it.style === "value"); }
            }
        }
        QQC2.MenuItem {
            text: i18n("Double width")
            checkable: true
            id: miWide
            checked: !!tileMenu.it.wide
            onTriggered: { root.setTileProp(tileMenu.idx, "wide", !tileMenu.it.wide); tileMenu.rebind(miWide, () => !!tileMenu.it.wide); }
        }
        QQC2.MenuItem {
            text: i18n("Notifications")
            checkable: true
            id: miNotify
            checked: !!tileMenu.it.notify
            onTriggered: { root.setTileProp(tileMenu.idx, "notify", !tileMenu.it.notify); tileMenu.rebind(miNotify, () => !!tileMenu.it.notify); }
        }
        // ---- widget-wide entries (same as the menu on the empty area);
        // removing tiles is done in the "Edit tiles" mode (×)
        QQC2.MenuSeparator { }
        QQC2.MenuItem { text: i18n("Sensor Deck"); enabled: false }
        UpdateItem { }
        RestoreRemovedItem { }
        EditModeItem { }
        UndoMoveItem { }
        ResetOrderItem { }
        TileStyleMenu { }
        SectionsMenu { }
        ProfilesMenu { }
        ConfigureItem { }
        HandleHintItem { }
    }

    // ---- "+" field: suggestions for its section, then an own tile ---------------
    QQC2.Menu {
        id: addMenu
        // own window: the compositor keeps it on screen and above the panel
        popupType: QQC2.Popup.Window
        property string group: ""
        // suggestions of this section (all of them without sections), sorted by name
        readonly property var list: root.suggestions
            .filter(s => !full.sections || s.group === group)
            .filter(s => !(full.sections && s.tile.source === "pcie"))   // shown in the section header
            .slice().sort((a, b) => a.tile.label.localeCompare(b.tile.label))
        function openFor(g, field) {
            group = g;
            popup(field, 0, field.height);
        }
        QQC2.MenuItem {
            text: addMenu.list.length ? i18n("Suggestions for your hardware") : i18n("No further suggestions")
            enabled: false
        }
        Instantiator {
            model: addMenu.list
            delegate: QQC2.MenuItem {
                required property var modelData
                text: modelData.tile.label
                      + (root.multiGpu && !full.sections && modelData.group.charAt(0) !== "~"
                         ? "  ·  " + ((root.gpuInfo(modelData.group) || {}).tag || "") : "")
                icon.name: ({ ring: "view-statistics", graph: "office-chart-line", bar: "office-chart-bar",
                              curve: "office-chart-area", value: "format-number" })[modelData.tile.style] || "list-add"
                onTriggered: root.addTile(modelData.tile)
            }
            onObjectAdded: (index, object) => addMenu.insertItem(index + 1, object)
            onObjectRemoved: (index, object) => addMenu.removeItem(object)
        }
        QQC2.MenuSeparator { }
        QQC2.MenuItem {
            text: i18n("Own tile …")
            icon.name: "document-new"
            onTriggered: root.addCustomTile(addMenu.group)
        }
    }

    // ---- context menu of the empty area (gaps, headers, margins) ------------------
    // Plasma's own widget menu does not appear there because the scroll area takes
    // the click – so Sensor Deck offers its own entries. Removing, resizing and
    // alternatives stay with Plasma's handle (long press on the widget).
    QQC2.Menu {
        id: deckMenu
        // own window: the compositor keeps it on screen and above the panel
        popupType: QQC2.Popup.Window
        QQC2.MenuItem { text: i18n("Sensor Deck"); enabled: false }
        UpdateItem { }
        RestoreRemovedItem { }
        EditModeItem { }
        UndoMoveItem { }
        ResetOrderItem { }
        QQC2.MenuSeparator { }
        TileStyleMenu { }
        SectionsMenu { }
        ProfilesMenu { }
        ConfigureItem { }
        HandleHintItem { }
    }

    // one right-click area over the whole widget: a tile gets its own menu,
    // everything else the widget menu (left clicks, hover and wheel pass through)
    MouseArea {
        anchors.fill: parent
        z: 2000
        acceptedButtons: Qt.RightButton
        function tileAt(x, y) {
            if (!scroll.visible || !scroll.contains(scroll.mapFromItem(full, x, y))) return null;
            for (let i = 0; i < tiles.count; ++i) {
                const l = tiles.itemAt(i);
                const t = l && l.isTile ? l.item : null;
                if (t && t.contains(t.mapFromItem(full, x, y))) return t;
            }
            return null;
        }
        onPressed: mouse => {
            if (full.dragFrom >= 0) return;
            const t = tileAt(mouse.x, mouse.y);
            if (t) tileMenu.openFor(t.itemIndex, t.src, t);
            else deckMenu.popup();
        }
    }

    Timer {
        id: correctTimer
        interval: 60
        onTriggered: {
            const avail = scroll.availableHeight, need = grid.implicitHeight;
            if (!full.fit || need <= 0 || avail <= 0) return;
            if (need > avail + 1 && full.scale_ > full.minFitScale * 0.9)
                full.fitCorrection = Math.max(0.6, full.fitCorrection * avail / need * 0.99);
        }
    }

    // floating copy of the dragged tile
    Image {
        id: proxy
        z: 1000
        visible: full.dragFrom >= 0 && source.toString() !== ""
        // "lifts" when picked up, so a long press visibly succeeds
        scale: visible ? 1.05 : 1.0
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        opacity: 0.92
        smooth: true
    }

    // empty state
    ColumnLayout {
        anchors.centerIn: parent
        visible: root.items.length === 0 && !root.needsSetup
        Kirigami.Icon {
            Layout.alignment: Qt.AlignHCenter
            source: "view-statistics"
            implicitWidth: Kirigami.Units.iconSizes.large
            implicitHeight: implicitWidth
            opacity: 0.6
        }
        QQC2.Label {
            text: i18n("No sensors configured")
            opacity: 0.7
        }
        QQC2.Button {
            Layout.alignment: Qt.AlignHCenter
            icon.name: "configure"
            text: i18n("Configure …")
            onClicked: Plasmoid.configuration.setupDone = false
        }
    }
}
