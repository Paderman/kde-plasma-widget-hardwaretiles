// SPDX-FileCopyrightText: 2026 Paderman
// SPDX-License-Identifier: GPL-2.0-or-later

// prints the default tile layout for the demo package (all cards + compare + system)
const fs = require("fs"), dir = process.argv[2], { execSync } = require("child_process");
const load = f => fs.readFileSync(dir + "/ui/" + f, "utf8").replace(/^\.pragma.*$/m, "").replace(/^\.import.*$/mg, "");
const Defaults = new Function(load("Defaults.js") + ";return {normalize};")();
const H = new Function("Defaults", load("Hardware.js") + ";return {parse,build,supportedGpus};")(Defaults);
const hw = H.parse(execSync("sh '" + dir + "/code/hw-discover.sh'").toString());
process.stdout.write(JSON.stringify(H.build(H.supportedGpus(hw), { gpuDetails: false, compare: true, cpu: true, ram: true }, hw)));
