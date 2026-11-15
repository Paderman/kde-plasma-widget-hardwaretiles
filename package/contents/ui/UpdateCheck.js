.pragma library

// SPDX-FileCopyrightText: 2026 Paderman
// SPDX-License-Identifier: GPL-2.0-or-later

// Update check against the GitHub releases of the project. Runs only when the user
// agreed (automatic, weekly) or clicks "Check now". The request goes to
// api.github.com and carries no data besides what every web request has (IP address,
// user agent) – no ID, no statistics.

// keep in sync with metadata.json (install.sh and make-package.sh check this)
var current = "1.1.2";
var api = "https://api.github.com/repos/Paderman/kde-plasma-widget-hardwaretiles/releases/latest";
var releasesPage = "https://github.com/Paderman/kde-plasma-widget-hardwaretiles/releases";
var interval = 7 * 24 * 3600;   // automatic check: once a week (seconds)

function parts(v) {
    return String(v || "").replace(/^v/i, "").split(/[.\-+]/).slice(0, 3).map(function (x) { return parseInt(x) || 0; });
}

// true if version a is newer than version b
function newer(a, b) {
    var x = parts(a), y = parts(b);
    for (var i = 0; i < 3; ++i) {
        if ((x[i] || 0) !== (y[i] || 0)) return (x[i] || 0) > (y[i] || 0);
    }
    return false;
}

// cb({ status: "ok" | "none" | "error", version, url, error })
//   none = no release published yet
function fetchLatest(cb) {
    var xhr = new XMLHttpRequest();
    xhr.onreadystatechange = function () {
        if (xhr.readyState !== XMLHttpRequest.DONE) return;
        if (xhr.status === 200) {
            try {
                var r = JSON.parse(xhr.responseText);
                cb({ status: "ok", version: String(r.tag_name || "").replace(/^v/i, ""), url: r.html_url || releasesPage });
            } catch (e) {
                cb({ status: "error", error: String(e) });
            }
        } else if (xhr.status === 404) {
            cb({ status: "none" });
        } else {
            cb({ status: "error", error: xhr.status ? "HTTP " + xhr.status : "offline" });
        }
    };
    xhr.open("GET", api);
    xhr.setRequestHeader("Accept", "application/vnd.github+json");
    xhr.send();
}
