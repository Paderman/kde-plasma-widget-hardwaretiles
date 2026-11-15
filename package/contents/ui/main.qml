// SPDX-FileCopyrightText: 2026 Paderman
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.ksvg as KSvg
import "Defaults.js" as Defaults
import "Hardware.js" as Hardware
import "UpdateCheck.js" as UpdateCheck
import "NvidiaKeys.js" as NK
import "Profiles.js" as Profiles

PlasmoidItem {
    id: root

    // ---- hardware & chosen GPU ----------------------------------------------
    HardwareProbe { id: probe }
    readonly property alias hardware: probe
    // live preview of the tile settings (ConfigSensors) – stored only with OK / Apply
    readonly property var layoutPreview: {
        try { const p = JSON.parse(Plasmoid.configuration.layoutPreview || "null"); return p && typeof p.items === "string" ? p : null; }
        catch (e) { return null; }
    }
    readonly property bool previewing: layoutPreview !== null
    // live preview of the Appearance page: its unsaved values win over the stored ones
    readonly property var appearancePreview: {
        try { const p = JSON.parse(Plasmoid.configuration.appearancePreview || "null"); return p && typeof p === "object" ? p : null; }
        catch (e) { return null; }
    }
    function setting(key) {
        const p = appearancePreview;
        return p && (key in p) ? p[key] : Plasmoid.configuration[key];
    }
    readonly property string itemsJson: previewing ? layoutPreview.items : Plasmoid.configuration.items
    readonly property string gpuAddress: previewing ? String(layoutPreview.gpu || "") : Plasmoid.configuration.gpuAddress
    // tile changes made in the widget itself; ignored during a preview – they
    // would be based on the previewed tiles and store them behind the settings' back
    function storeItems(json) {
        if (previewing) return false;
        Plasmoid.configuration.items = json;
        return true;
    }
    readonly property var gpu: Hardware.pickGpu(probe.hw, gpuAddress)
    readonly property bool needsSetup: !Plasmoid.configuration.setupDone
    // light colour scheme: warning colours get darker for contrast
    readonly property bool lightTheme: Kirigami.ColorUtils.brightnessForColor(Kirigami.Theme.backgroundColor) === Kirigami.ColorUtils.Light

    // tiles as stored (with {gpu} tokens) …
    readonly property var rawItems: {
        // guarantee unique ids even if the config was edited by hand
        const seen = {};
        return Defaults.parse(itemsJson).map((it, i) => {
            if (seen[it.id]) it.id = it.id + "-" + i;
            seen[it.id] = true;
            return it;
        });
    }
    // graphics card of each tile: its own ("gpu" field), else the widget's main card;
    // null for tiles that have nothing to do with a GPU
    readonly property var tileGpus: rawItems.map(it => !Hardware.usesGpu(it) || it.compare ? null
                                                   : it.gpu ? Hardware.gpuByAddr(probe.hw, it.gpu) : gpu)
    readonly property bool hasCompare: rawItems.some(it => it.compare)
    // cards that are actually shown, in hardware order: [{addr, gpu, tag, slot}]
    readonly property var shownGpus: {
        const addrs = {};
        // compare tiles show every card
        if (hasCompare) Hardware.supportedGpus(probe.hw).forEach(g => addrs[g.addr] = g);
        rawItems.forEach((it, i) => {
            if (!Hardware.usesGpu(it) || it.compare) return;
            const g = tileGpus[i];
            addrs[g ? g.addr : (it.gpu || "")] = g;
        });
        const known = Hardware.supportedGpus(probe.hw).filter(g => g.addr in addrs);
        // cards that are configured but not (yet) found keep their place at the end
        const missing = Object.keys(addrs).filter(a => !addrs[a])
                              .map(a => ({ addr: a,
                                           name: !a ? i18n("Graphics card")
                                               : probe.ready ? i18n("Graphics card %1 (not found)", a.replace(/^0000:/, ""))
                                               : i18n("Graphics card %1", a.replace(/^0000:/, "")),
                                           missing: true }));
        const list = known.concat(missing);
        // short names, made unique ("RTX 3080 #1", "RTX 3080 #2")
        const tags = list.map(g => g.missing ? g.name : Hardware.gpuTag(g));
        return list.map((g, i) => {
            const same = tags.filter(t => t === tags[i]).length > 1;
            const n = tags.slice(0, i + 1).filter(t => t === tags[i]).length;
            return { addr: g.addr, gpu: g.missing ? null : g, slot: i,
                     tag: same ? tags[i] + " #" + n : tags[i] };
        });
    }
    readonly property bool multiGpu: shownGpus.length > 1
    function gpuInfo(addr) {
        for (let i = 0; i < shownGpus.length; ++i) if (shownGpus[i].addr === addr) return shownGpus[i];
        return null;
    }

    // … and resolved for their graphics card
    readonly property var items: rawItems.map((it, i) => {
        if (!Hardware.usesGpu(it) || it.compare) return Hardware.resolve(it, gpu, -1, "");
        const g = tileGpus[i];
        const info = gpuInfo(g ? g.addr : (it.gpu || ""));
        return Hardware.resolve(it, g, multiGpu && info ? info.slot : -1, multiGpu && info ? info.tag : "");
    })

    // compare tiles: one resolved config per card (aligned with items, null = normal tile)
    readonly property var compareCfgs: rawItems.map(it => {
        if (!it.compare) return null;
        const cards = shownGpus.filter(g => !!g.gpu);
        if (!cards.length) return [Hardware.resolve(Hardware.forGpu(it, "", true), gpu, -1, "")];
        return cards.map((g, k) => Hardware.resolve(Hardware.forGpu(it, g.addr, g.addr === (gpu ? gpu.addr : cards[0].addr)),
                                                    g.gpu, multiGpu ? g.slot : -1, multiGpu ? g.tag : ""));
    })
    // every data source that has to exist (normal tiles + one per card of compare tiles)
    readonly property var allCfgs: {
        const out = [];
        items.forEach((it, i) => { if (compareCfgs[i]) compareCfgs[i].forEach(c => out.push(c)); else out.push(it); });
        return out;
    }

    // called by the setup wizard; gpuAddrs: one or more PCI addresses (first = main card)
    function applySetup(gpuAddrs, opts) {
        if (!Array.isArray(gpuAddrs)) gpuAddrs = gpuAddrs ? [gpuAddrs] : [];
        const gs = gpuAddrs.map(a => Hardware.gpuByAddr(probe.hw, a)).filter(g => !!g);
        const g = gs.length ? gs[0] : Hardware.pickGpu(probe.hw, "");
        Plasmoid.configuration.gpuAddress = g ? g.addr : "";
        Plasmoid.configuration.items = JSON.stringify(Hardware.build(gs.length > 1 ? gs : (gpuAddrs.length ? g : null), opts, probe.hw, (...a) => i18n(...a)));
        Plasmoid.configuration.baseOrder = "";
        Plasmoid.configuration.layoutPreset = "wizard";
        Plasmoid.configuration.layoutHash = Defaults.signature(Plasmoid.configuration.items);
        undoOrder = null;
        Plasmoid.configuration.setupDone = true;
    }

    readonly property int interval: Math.max(250, Plasmoid.configuration.updateInterval)

    // ---- shared nvidia-smi query (only runs if a tile needs it) ------------
    NvidiaProvider {
        id: nvidia
        interval: root.interval
        readonly property var users: root.allCfgs.filter(it => it.source === "nvidia"
                                                        || (it.style === "curve" && it.ySource === "nvidia"))
        indices: {
            const out = [];
            users.forEach(it => { if (it.nvIndex >= 0 && out.indexOf(it.nvIndex) < 0) out.push(it.nvIndex); });
            return out.sort((a, b) => a - b);
        }
        active: indices.length > 0
        fanWatch: Plasmoid.configuration.fanWatch
        fanSlowPercent: Plasmoid.configuration.fanSlowPercent
        fansActive: users.some(it => it.source === "nvidia" && NK.fanNo(it.key) >= 0)
    }

    // ---- data sources, keyed by tile id ------------------------------------
    property var sourceMap: ({})
    property int sourcesRevision: 0

    Component {
        id: sourceComponent
        SensorSource { }
    }

    function syncSources() {
        const keep = {};
        allCfgs.forEach(it => {
            let s = sourceMap[it.id];
            if (!s) {
                s = sourceComponent.createObject(root, {
                    cfg: it,
                    nvidia: nvidia,
                    lightTheme: Qt.binding(() => root.lightTheme),
                    interval: Qt.binding(() => root.interval),
                    historyLength: Qt.binding(() => Plasmoid.configuration.historyLength),
                    alertsEnabled: Qt.binding(() => Plasmoid.configuration.alertsEnabled),
                    alertOnWarn: Qt.binding(() => Plasmoid.configuration.alertOnWarn),
                    alertRecovery: Qt.binding(() => Plasmoid.configuration.alertRecovery),
                    alertDelay: Qt.binding(() => Plasmoid.configuration.alertDelay * 1000),
                    alertCooldown: Qt.binding(() => Plasmoid.configuration.alertCooldown * 60000),
                    hysteresis: Qt.binding(() => Plasmoid.configuration.alertHysteresis)
                });
                sourceMap[it.id] = s;
                if (s.isCurve) s.importCurve(storedCurves()[it.id]);
            } else if (JSON.stringify(s.cfg) !== JSON.stringify(it)) {
                // learned curve only makes sense for the same pair of sensors
                const o = s.cfg;
                if (o.source !== it.source || o.sensorId !== it.sensorId || o.key !== it.key || o.command !== it.command
                    || o.ySource !== it.ySource || o.ySensorId !== it.ySensorId || o.yKey !== it.yKey || o.yCommand !== it.yCommand)
                    s.resetCurve();
                s.cfg = it;
            }
            keep[it.id] = true;
        });
        for (const id in sourceMap) {
            if (!keep[id]) { sourceMap[id].destroy(); delete sourceMap[id]; }
        }
        sourcesRevision++;
    }
    onAllCfgsChanged: syncSources()
    Component.onCompleted: {
        Qt.callLater(() => root.desktopContainer = root.findContainer());
        // a size preview left over (settings were open when Plasma stopped)
        Plasmoid.configuration.appearancePreview = "";
        Plasmoid.configuration.layoutPreview = "";
        // existing widgets already have a layout: don't show the wizard there
        if (!Plasmoid.configuration.setupDone && Plasmoid.configuration.items !== "")
            Plasmoid.configuration.setupDone = true;
        syncSources();
    }

    // ---- learned fan curves survive restarts ---------------------------------
    function storedCurves() {
        try { return JSON.parse(Plasmoid.configuration.curveData || "{}") || {}; } catch (e) { return {}; }
    }
    function saveCurves() {
        const out = {};
        allCfgs.forEach(it => {
            const s = sourceMap[it.id];
            if (s && s.isCurve && Object.keys(s.bins).length) out[it.id] = s.exportCurve();
        });
        const json = JSON.stringify(out);
        if (json !== (Plasmoid.configuration.curveData || "{}") && json !== "{}") Plasmoid.configuration.curveData = json;
    }
    Timer {
        // every 2 minutes (only written when something new was learned)
        interval: 120000
        running: root.allCfgs.some(it => it.style === "curve")
        repeat: true
        onTriggered: root.saveCurves()
    }
    Component.onDestruction: saveCurves()

    function source(i) {
        sourcesRevision; // dependency
        const it = items[i];
        if (!it) return null;
        // compare tile: the main card's source stands for the tile (label, colour …)
        const c = compareCfgs[i];
        if (c) return c.length ? (sourceMap[c[0].id] || null) : null;
        return sourceMap[it.id] || null;
    }
    // compare tile: [{src, slot, tag}] for every card; [] for normal tiles
    function compareSources(i) {
        sourcesRevision;
        const c = compareCfgs[i];
        if (!c) return [];
        const all = c.map(cfg => ({ src: sourceMap[cfg.id] || null, slot: cfg.gpuSlot, tag: cfg.gpuTag }))
                     .filter(e => e.src !== null);
        // leave out cards without any data for this value (bindings re-run when noData changes)
        const withData = all.filter(e => !e.src.noData);
        return withData.length ? withData : all;
    }

    // compare tile for several cards where only one card has data left: it would
    // only repeat that card's own tile, so it is hidden (full view and panel)
    function compareCollapsed(i) {
        const it = items[i];
        return !!(it && it.compare && (compareCfgs[i] || []).length > 1 && compareSources(i).length === 1);
    }

    // reorder tiles (drag & drop in the full view)
    function moveItem(from, to) {
        if (from === to || from < 0 || to < 0 || from >= items.length || to >= items.length) return;
        const before = idsOf(rawItems);
        // remember the original order once, before the first manual move
        if (!Plasmoid.configuration.baseOrder)
            Plasmoid.configuration.baseOrder = JSON.stringify(before);
        undoOrder = before;
        const arr = rawItems.slice();
        const it = arr.splice(from, 1)[0];
        arr.splice(to, 0, it);
        if (!storeItems(JSON.stringify(arr))) return;
    }

    // ---- tile context menu: change or remove a single tile -------------------
    function setTileProp(i, key, value) {
        if (i < 0 || i >= rawItems.length) return;
        const arr = rawItems.slice();
        const it = Object.assign({}, arr[i]);
        it[key] = value;
        arr[i] = it;
        if (!storeItems(JSON.stringify(arr))) return;
    }
    // undoRemove: { items: JSON before, after: JSON after, label } – only valid while
    // nothing else changed the tiles in between
    property var undoRemove: null
    readonly property bool canUndoRemove: undoRemove !== null && undoRemove.after === Plasmoid.configuration.items
    function removeTile(i, label) {
        if (i < 0 || i >= rawItems.length) return;
        const before = Plasmoid.configuration.items;
        const arr = rawItems.slice();
        arr.splice(i, 1);
        if (!storeItems(JSON.stringify(arr))) return;
        undoRemove = { items: before, after: Plasmoid.configuration.items, label: label || "" };
    }
    // open the settings at this tile (ConfigSensors reads editTile)
    function editTile(i) {
        const it = rawItems[i];
        if (!it) return;
        Plasmoid.configuration.editTile = it.id + "@" + Date.now();
        Plasmoid.internalAction("configure").trigger();
    }
    function restoreRemoved() {
        if (!canUndoRemove) return;
        const json = undoRemove.items;
        undoRemove = null;
        if (!storeItems(json)) return;
    }

    // ---- adding tiles in the widget ("Edit tiles" mode) ---------------------
    // section of a tile, as FullView groups them: card address, "~compare" or "~system"
    function tileGroup(it) {
        if (it.compare) return "~compare";
        if (!Hardware.usesGpu(it)) return "~system";
        return it.gpu || (gpu ? gpu.addr : "");
    }
    // what makes two tiles "the same" (label, style and colours don't count)
    function tileKey(it) {
        return [it.source || "sensor", it.sensorId, it.key, it.command, it.ySensorId, it.yKey,
                it.compare ? 1 : 0, it.compare ? "" : tileGroup(it)].join("|");
    }
    function tr(...a) { return i18n(...a); }
    // every tile the hardware detection can offer (like the "System overview" /
    // "All graphics cards" templates with all categories) …
    readonly property var catalog: {
        if (!probe.ready) return [];
        const opts = Hardware.defaultOptions();
        for (const k in opts) opts[k] = true;
        opts.fansEach = true;
        const gpus = probe.gpus.length ? probe.gpus : [gpu];
        return Hardware.build(gpus.length > 1 ? gpus : gpus[0], opts, probe.hw, tr);
    }
    // … minus the tiles that are already in the deck: [{ tile, group }].
    // Same source, or same name in the same section (older tiles may read the
    // same value from another source, e.g. "GPU load" via ksystemstats).
    readonly property var suggestions: {
        const have = {};
        rawItems.forEach(it => {
            have[tileKey(it)] = true;
            have[tileGroup(it) + "#" + it.label] = true;
        });
        return catalog.filter(it => !have[tileKey(it)] && !have[tileGroup(it) + "#" + it.label])
                      .map(it => ({ tile: it, group: tileGroup(it) }));
    }
    // every voltage, temperature and fan of the sensor chips that is not a tile yet
    // ("+" menu, submenu "Mainboard & other sensors")
    readonly property var extraGroups: {
        if (!probe.ready) return [];
        const have = {};
        rawItems.forEach(it => { if (it.sensorId) have[it.sensorId] = true; });
        return Hardware.extraSensors(probe.hw, tr)
            .map(g => ({ title: g.title, items: g.items.filter(e => !have[e.tile.sensorId]) }))
            .filter(g => g.items.length > 0);
    }
    // returns the index of the new tile
    function addTile(tile) {
        const it = Object.assign({}, tile);
        it.id = Defaults.newId();
        const arr = rawItems.slice();
        arr.push(Defaults.normalize(it, arr.length));
        if (!storeItems(JSON.stringify(arr))) return;
        return arr.length - 1;
    }
    // own tile: the settings add it as an unsaved change (Cancel leaves nothing
    // behind) and jump to it; group = section it was asked for (card address)
    function addCustomTile(group) {
        const addr = group && group.charAt(0) !== "~" && (!gpu || group !== gpu.addr) ? group : "";
        Plasmoid.configuration.editTile = "new:" + addr + "@" + Date.now();
        Plasmoid.internalAction("configure").trigger();
    }

    // ---- undo / reset of the tile order ------------------------------------
    // ---- profiles (Profiles.js) ---------------------------------------------------
    readonly property var profiles: Profiles.list(Plasmoid.configuration.profiles)
    readonly property string activeProfile: Profiles.find(profiles, Plasmoid.configuration.activeProfile)
                                            ? Plasmoid.configuration.activeProfile : ""
    readonly property var profileBackup: { Plasmoid.configuration.profileBackup; return Profiles.backup(Plasmoid.configuration); }
    // the current view differs from the loaded profile
    readonly property bool profileChanged: {
        Plasmoid.configuration.items; Plasmoid.configuration.tileStyle; Plasmoid.configuration.tileScale;
        return activeProfile !== "" && !Profiles.sameAs(Plasmoid.configuration, Profiles.find(profiles, activeProfile));
    }
    function loadProfile(name) { undoOrder = null; return Profiles.load(Plasmoid.configuration, name, probe.gpus); }
    function undoProfileChange() { undoOrder = null; Profiles.undo(Plasmoid.configuration); }

    property var undoOrder: null     // order before the last move (this session)

    function idsOf(arr) { return arr.map(it => it.id); }

    // order the reset goes back to: the snapshot from before the first move,
    // otherwise the order the setup wizard / "Layout laden" created (s1, s2, …)
    readonly property var resetTarget: {
        try {
            const a = JSON.parse(Plasmoid.configuration.baseOrder || "[]");
            if (Array.isArray(a) && a.length) return a;
        } catch (e) { }
        const num = id => { const m = /^s(\d+)$/.exec(id); return m ? parseInt(m[1]) : Infinity; };
        return rawItems.map((it, i) => ({ id: it.id, n: num(it.id), i: i }))
                       .sort((a, b) => a.n - b.n || a.i - b.i)
                       .map(o => o.id);
    }
    function sortedBy(ids) {
        const pos = {};
        ids.forEach((id, i) => pos[id] = i);
        // tiles that are not in the list (added later) keep their relative order at the end
        return rawItems.map((it, i) => ({ it: it, k: (it.id in pos) ? pos[it.id] : ids.length + i }))
                       .sort((a, b) => a.k - b.k)
                       .map(o => o.it);
    }
    readonly property bool orderChanged:
        JSON.stringify(idsOf(sortedBy(resetTarget))) !== JSON.stringify(idsOf(rawItems))

    function applyOrder(ids) {
        if (!storeItems(JSON.stringify(sortedBy(ids)))) return;
    }
    function undoMove() {
        if (!undoOrder) return;
        const ids = undoOrder;
        undoOrder = null;
        applyOrder(ids);
    }
    function resetOrder() {
        undoOrder = idsOf(rawItems);   // the reset itself can be undone
        applyOrder(resetTarget);
        Plasmoid.configuration.baseOrder = "";
    }

    // ---- update check (only with the user's consent, see UpdateCheck.js)
    readonly property bool updateAvailable: UpdateCheck.newer(Plasmoid.configuration.updateLatest, UpdateCheck.current)
    readonly property bool updateBanner: updateAvailable && Plasmoid.configuration.updateLatest !== Plasmoid.configuration.updateDismissed
    readonly property bool askUpdates: !Plasmoid.configuration.updateAsked && !needsSetup
    function checkUpdates() {
        Plasmoid.configuration.updateLastCheck = Math.floor(Date.now() / 1000);
        UpdateCheck.fetchLatest(r => {
            if (r.status !== "ok") return;
            Plasmoid.configuration.updateLatest = r.version;
            Plasmoid.configuration.updateUrl = r.url;
        });
    }
    function answerUpdates(yes) {
        Plasmoid.configuration.updateCheck = yes;
        Plasmoid.configuration.updateAsked = true;
        if (yes) checkUpdates();
    }
    function openUpdatePage() {
        Qt.openUrlExternally(Plasmoid.configuration.updateUrl || UpdateCheck.releasesPage);
    }
    Timer {
        // hourly look whether the weekly check is due (survives sleep and long uptimes)
        interval: 3600 * 1000
        repeat: true
        triggeredOnStart: true
        running: Plasmoid.configuration.updateCheck
        onTriggered: {
            if (Date.now() / 1000 - Plasmoid.configuration.updateLastCheck >= UpdateCheck.interval)
                root.checkUpdates();
        }
    }

    // ---- rotation on the desktop: Plasma turns the applet's container (handle
    // "Click and drag to rotate") and saves it in the containment layout
    property Item desktopContainer: null
    function findContainer() {
        for (let p = root.parent; p; p = p.parent)
            if (p.applet !== undefined && p.layout && typeof p.layout.save === "function") return p;
        return null;
    }
    onParentChanged: Qt.callLater(() => root.desktopContainer = root.findContainer())
    readonly property real rotationAngle: desktopContainer ? ((desktopContainer.rotation % 360) + 360) % 360 : 0
    readonly property bool rotated: rotationAngle !== 0
    function resetRotation() {
        if (!desktopContainer) return;
        desktopContainer.rotation = 0;
        desktopContainer.layout.save();
    }

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: root.updateAvailable ? i18n("Hardware Tiles %1 is available – open download page", Plasmoid.configuration.updateLatest) : ""
            icon.name: "update-none"
            visible: root.updateAvailable
            onTriggered: root.openUpdatePage()
        },
        PlasmaCore.Action {
            text: root.canUndoRemove ? i18n("Restore “%1”", root.undoRemove.label) : ""
            icon.name: "edit-undo"
            visible: root.canUndoRemove
            onTriggered: root.restoreRemoved()
        },
        PlasmaCore.Action {
            text: i18n("Undo last move")
            icon.name: "edit-undo"
            visible: root.undoOrder !== null
            onTriggered: root.undoMove()
        },
        PlasmaCore.Action {
            text: i18n("Restore original arrangement")
            icon.name: "edit-reset"
            enabled: root.orderChanged
            onTriggered: root.resetOrder()
        },
        PlasmaCore.Action {
            text: i18n("Straighten widget (rotated by %1°)", Math.round(root.rotationAngle))
            icon.name: "object-rotate-right"
            visible: root.rotated
            onTriggered: root.resetRotation()
        }
    ]

    // background opacity (desktop): 100 % = the normal Plasma frame, below that the
    // widget draws its own background (FullView) – the Plasma frame has no opacity
    readonly property int bgOpacity: Math.max(0, Math.min(100,
        Number(setting("backgroundOpacity"))))
    // how solid tiles and headers get once the background is gone (0…1)
    readonly property real tileBacking: Math.max(0.5, Math.min(1,
        Number(setting("tileOpacity")) / 100))
    Plasmoid.backgroundHints: bgOpacity >= 100 ? (PlasmaCore.Types.DefaultBackground | PlasmaCore.Types.ConfigurableBackground)
                                               : PlasmaCore.Types.NoBackground

    preferredRepresentation: (Plasmoid.formFactor === PlasmaCore.Types.Horizontal
                              || Plasmoid.formFactor === PlasmaCore.Types.Vertical)
                             ? compactRepresentation : fullRepresentation

    // no texts = no tooltip (switched off in the settings)
    toolTipMainText: setting("tooltipsEnabled") ? i18n("Hardware Tiles") : ""
    toolTipSubText: {
        if (!setting("tooltipsEnabled")) return "";
        sourcesRevision;
        const lines = [];
        allCfgs.forEach(c => {
            const s = sourceMap[c.id];
            if (s && s.cfg.style !== "curve") lines.push(s.longLabel + ": " + s.formatted);
        });
        return lines.join("\n");
    }

    compactRepresentation: CompactView { }
    // Below 100 % background opacity Plasma's frame is switched off (it has no
    // opacity of its own). The same frame is then drawn here, faded, and the
    // content keeps the frame's margins – nothing jumps between 100 % and 95 %.
    fullRepresentation: Item {
        id: fullBox
        readonly property bool ownFrame: Plasmoid.formFactor !== PlasmaCore.Types.Horizontal
                                         && Plasmoid.formFactor !== PlasmaCore.Types.Vertical
                                         && root.bgOpacity < 100
        readonly property real padL: ownFrame ? frame.margins.left : 0
        readonly property real padR: ownFrame ? frame.margins.right : 0
        readonly property real padT: ownFrame ? frame.margins.top : 0
        readonly property real padB: ownFrame ? frame.margins.bottom : 0
        Layout.minimumWidth: view.Layout.minimumWidth + padL + padR
        Layout.minimumHeight: view.Layout.minimumHeight + padT + padB
        Layout.preferredWidth: view.Layout.preferredWidth + padL + padR
        Layout.preferredHeight: view.Layout.preferredHeight + padT + padB

        // Plasma's own frame looks lighter than this one at full opacity: KWin blurs
        // and raises the contrast behind it, which a self-drawn frame cannot ask
        // for. Scaled so that 99 % looks about like Plasma's 100 % (Breeze).
        KSvg.FrameSvgItem {
            id: frame
            anchors.fill: parent
            imagePath: "widgets/background"
            visible: fullBox.ownFrame && root.bgOpacity > 0
            opacity: 0.8 * root.bgOpacity / 100
        }
        FullView {
            id: view
            anchors.fill: parent
            anchors.leftMargin: fullBox.padL
            anchors.rightMargin: fullBox.padR
            anchors.topMargin: fullBox.padT
            anchors.bottomMargin: fullBox.padB
        }
    }
}
