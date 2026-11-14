.pragma library

// SPDX-FileCopyrightText: 2026 Paderman
// SPDX-License-Identifier: GPL-2.0-or-later

// Break points for long German compound words in tile names: a soft hyphen
// (U+00AD) is put between the parts ("Arbeits|speicher"). It stays invisible
// until the name has to wrap there – then "ARBEITS-" / "SPEICHER" is shown
// instead of the whole name getting a smaller font.

var SHY = "­";

// word endings that are parts of a compound (longest first is not needed:
// the longest matching ending is picked)
var PARTS = [
    "speicher", "stufe", "lüfter", "träger", "kurve", "temperatur", "verbrauch",
    "kodierung", "dekodierung", "bremse", "takt", "last", "auslastung", "leistung",
    "spannung", "drehzahl", "geschwindigkeit", "karte", "platte", "laufwerk",
    "vergleich", "aktivität", "chip", "prozessor", "netzwerk", "datei", "system"
];

var MIN_REST = 3;   // the part in front must have at least this many letters

function splitWord(w) {
    var lw = w.toLowerCase();
    var best = "";
    for (var i = 0; i < PARTS.length; ++i) {
        var p = PARTS[i];
        if (p.length > best.length && lw.length - p.length >= MIN_REST && lw.slice(-p.length) === p)
            best = p;
    }
    if (!best) return w;
    var cut = w.length - best.length;
    return splitWord(w.slice(0, cut)) + SHY + w.slice(cut);
}

// "Gehäuselüfter vorne" -> "Gehäuse­lüfter vorne"
function hyphenate(text) {
    return String(text || "").replace(/[A-Za-zÄÖÜäöüß]{8,}/g, splitWord);
}
