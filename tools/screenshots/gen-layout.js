// SPDX-FileCopyrightText: 2026 Paderman
// SPDX-License-Identifier: GPL-2.0-or-later
//
// node gen-layout.js <package contents dir> <demo.js> <overview|multi> [translations.json]
// (translations.json: {"English": "Translated"} – tile names are stored in the
// language of the setup, so a German screenshot needs German names)
// prints {"items": <tile JSON>, "curveData": <prefilled fan curve JSON>}
const fs = require("fs"), [dir, demo, mode, trFile] = process.argv.slice(2);
const map = trFile ? JSON.parse(fs.readFileSync(trFile, "utf8")) : {};
const tr = (s, ...a) => { let r = map[s] || s; a.forEach((v, i) => { r = r.split("%" + (i + 1)).join(String(v)); }); return r; };
const load = f => fs.readFileSync(f, "utf8").replace(/^\.pragma.*$/m, "").replace(/^\.import.*$/mg, "");
const Defaults = new Function(load(dir + "/ui/Defaults.js") + ";return {normalize, nvmeLabel, stripSensorNo, signature};")();
const H = new Function("Defaults", load(dir + "/ui/Hardware.js") + ";return {parse,build,supportedGpus,pickGpu};")(Defaults);
const D = new Function(load(demo) + ";return {hwDiscover, fanCurve, set multi(v) { multi = v; }};")();
D.multi = mode === "multi";
const hw = H.parse(D.hwDiscover());
const items = mode === "multi"
    ? H.build(H.supportedGpus(hw), { gpuDetails: true, compare: true, cpu: true, ram: true, storage: true, board: false, network: false }, hw, tr)
    : H.build(H.pickGpu(hw, ""), { gpuDetails: true, cpu: true, ram: true, storage: true, board: true, network: true }, hw, tr);
// a learned fan curve as after a few gaming sessions (40–80 °C)
const curve = {};
items.filter(t => t.style === "curve").forEach(t => {
    const pair = [t.source, t.sensorId, t.key, t.command, t.ySource, t.ySensorId, t.yKey, t.yCommand]
        .map(v => v === undefined ? "" : v).join("|");
    const bins = {};
    for (let x = 38; x <= 79; ++x) {
        bins[x] = [Math.round(D.fanCurve(x) * 10) / 10, 30];
    }
    curve[t.id] = { pair: pair, bins: bins };
});
process.stdout.write(JSON.stringify({ items: JSON.stringify(items), curveData: JSON.stringify(curve),
                                      preset: mode === "multi" ? "allgpus" : "system",
                                      hash: Defaults.signature ? Defaults.signature(JSON.stringify(items)) : "" }));
