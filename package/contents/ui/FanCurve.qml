// SPDX-FileCopyrightText: 2026 Paderman
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import "Defaults.js" as Defaults

// Fan curve: x = temperature (main source), y = fan (yReader).
// Draws the learned curve (mean fan per °C), a fading trail of recent samples,
// the live operating point and an optional reference curve.
ColumnLayout {
    id: fc
    property var tile
    readonly property var src: tile.ready ? tile.src : null
    spacing: Kirigami.Units.smallSpacing

    RowLayout {
        Layout.fillWidth: true
        // "Edit tiles": the values must not run under the × button either
        Layout.rightMargin: fc.tile.arranging === true ? Math.round(fc.tile.u * 1.2) : 0
        TileHeader { tile: fc.tile; Layout.fillWidth: true; keepCloseFree: false }
        // live values: "48 %  @ 51 °C"
        QQC2.Label {
            text: fc.src && fc.src.yReader.valid ? fc.src.yReader.formatted : "–"
            font.pixelSize: Math.round(fc.tile.u * 1.05)
            font.weight: Font.Bold
            font.features: { "tnum": 1 }
        }
        QQC2.Label {
            text: fc.src && fc.src.valid ? "@ " + fc.src.formatted : ""
            font.pixelSize: Math.round(fc.tile.u * 0.62)
            font.features: { "tnum": 1 }
            color: fc.src && fc.src.level > 0 ? fc.tile.accent : fc.tile.fg
            opacity: fc.src && fc.src.level > 0 ? 1 : 0.6
        }
    }

    Canvas {
        id: canvas
        Layout.fillWidth: true
        Layout.fillHeight: true
        renderStrategy: Canvas.Cooperative

        readonly property real labelPx: Math.max(8, Math.round(fc.tile.u * 0.5))
        readonly property real padL: labelPx * 3.2
        readonly property real padB: labelPx * 1.7
        readonly property real padT: labelPx * 0.6
        readonly property real padR: labelPx * 0.6

        property int rev: fc.src ? fc.src.curveRevision : 0
        onRevChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Connections {
            target: fc.tile
            function onAccentChanged() { canvas.requestPaint(); }
        }

        function rgba(c, a) { return Qt.rgba(c.r, c.g, c.b, a); }

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const s = fc.src;
            if (!s) return;
            const W = width, H = height;
            const xmin = s.minimum, xmax = s.maximum > s.minimum ? s.maximum : s.minimum + 1;
            // the last x label ("90°") is centred on the right edge of the plot –
            // leave room for its right half so it is not cut off
            ctx.font = labelPx + "px sans-serif";
            const padRight = Math.max(padR, ctx.measureText(Math.round(xmax) + "°").width / 2 + labelPx * 0.3);
            const x0 = padL, y0 = padT, pw = Math.max(10, W - padL - padRight), ph = Math.max(10, H - padT - padB);
            const ymin = 0, ymax = s.yMax > 0 ? s.yMax : 100;
            const X = v => x0 + (Math.max(xmin, Math.min(xmax, v)) - xmin) / (xmax - xmin) * pw;
            const Y = v => y0 + ph - (Math.max(ymin, Math.min(ymax, v)) - ymin) / (ymax - ymin) * ph;
            const fg = fc.tile.fg, ac = fc.tile.accent;

            // threshold zones
            const lt = fc.tile.lightTheme;
            if (s.warn > xmin) { ctx.fillStyle = rgba(Qt.color(Defaults.warnColor(lt)), 0.07); ctx.fillRect(X(s.warn), y0, x0 + pw - X(s.warn), ph); }
            if (s.crit > xmin) { ctx.fillStyle = rgba(Qt.color(Defaults.critColor(lt)), 0.10); ctx.fillRect(X(s.crit), y0, x0 + pw - X(s.crit), ph); }

            // grid + labels
            ctx.font = labelPx + "px sans-serif";
            ctx.lineWidth = 1;
            const span = xmax - xmin;
            const step = span <= 30 ? 5 : span <= 80 ? 10 : 20;
            ctx.textAlign = "center"; ctx.textBaseline = "top";
            for (let v = Math.ceil(xmin / step) * step; v <= xmax + 0.001; v += step) {
                const xx = Math.round(X(v)) + 0.5;
                ctx.strokeStyle = rgba(fg, lt ? 0.1 : 0.07);
                ctx.beginPath(); ctx.moveTo(xx, y0); ctx.lineTo(xx, y0 + ph); ctx.stroke();
                ctx.fillStyle = rgba(fg, lt ? 0.65 : 0.5);
                ctx.fillText(v + "°", xx, y0 + ph + labelPx * 0.4);
            }
            ctx.textAlign = "right"; ctx.textBaseline = "middle";
            const yUnit = s.yReader.isNvidia ? (s.yReader.effUnit || "") : (s.yReader.isSensor ? s.yReader.sensorUnit : s.yReader.effUnit);
            for (let i = 0; i <= 4; ++i) {
                const v = ymin + (ymax - ymin) * i / 4;
                const yy = Math.round(Y(v)) + 0.5;
                ctx.strokeStyle = rgba(fg, i === 0 ? 0.15 : 0.07);
                ctx.beginPath(); ctx.moveTo(x0, yy); ctx.lineTo(x0 + pw, yy); ctx.stroke();
                ctx.fillStyle = rgba(fg, lt ? 0.65 : 0.5);
                const t = Math.round(v) + (i === 4 && yUnit ? " " + yUnit : "");
                ctx.fillText(t, x0 - labelPx * 0.4, yy);
            }

            // reference curve (dashed)
            const ref = Defaults.parseCurve(s.cfg.refCurve);
            if (ref.length >= 2) {
                ctx.strokeStyle = rgba(fg, 0.4);
                ctx.lineWidth = Math.max(1, labelPx * 0.14);
                ctx.setLineDash([4, 4]);
                ctx.beginPath();
                ref.forEach((p, i) => i ? ctx.lineTo(X(p.x), Y(p.y)) : ctx.moveTo(X(p.x), Y(p.y)));
                ctx.stroke();
                ctx.setLineDash([]);
            }

            // learned curve: mean per °C, lightly smoothed over neighbours
            const keys = Object.keys(s.bins).map(Number).sort((a, b) => a - b);
            if (keys.length >= 2) {
                const pts = keys.map((k, i) => {
                    let sum = 0, w = 0;
                    for (let j = Math.max(0, i - 1); j <= Math.min(keys.length - 1, i + 1); ++j) {
                        const wt = j === i ? 2 : 1;
                        sum += s.bins[keys[j]].y * wt; w += wt;
                    }
                    return { x: k, y: sum / w };
                });
                const grad = ctx.createLinearGradient(0, y0, 0, y0 + ph);
                grad.addColorStop(0, rgba(ac, 0.30));
                grad.addColorStop(1, rgba(ac, 0.0));
                ctx.beginPath();
                ctx.moveTo(X(pts[0].x), Y(0));
                pts.forEach(p => ctx.lineTo(X(p.x), Y(p.y)));
                ctx.lineTo(X(pts[pts.length - 1].x), Y(0));
                ctx.closePath();
                ctx.fillStyle = grad;
                ctx.fill();
                ctx.strokeStyle = ac;
                ctx.lineWidth = Math.max(1.5, labelPx * 0.22);
                ctx.lineJoin = "round"; ctx.lineCap = "round";
                ctx.beginPath();
                pts.forEach((p, i) => i ? ctx.lineTo(X(p.x), Y(p.y)) : ctx.moveTo(X(p.x), Y(p.y)));
                ctx.stroke();
            }

            // every learned temperature as a dot (also visible with a single one)
            ctx.fillStyle = rgba(ac, 0.75);
            keys.forEach(k => {
                ctx.beginPath(); ctx.arc(X(k), Y(s.bins[k].y), Math.max(1.5, labelPx * 0.2), 0, Math.PI * 2); ctx.fill();
            });

            // trail of recent samples
            const tr = s.trail;
            const r = Math.max(1.5, labelPx * 0.2);
            for (let i = 0; i < tr.length; ++i) {
                const a = 0.08 + 0.5 * (i / Math.max(1, tr.length - 1));
                ctx.fillStyle = rgba(ac, a);
                ctx.beginPath(); ctx.arc(X(tr[i].x), Y(tr[i].y), r, 0, Math.PI * 2); ctx.fill();
            }

            // live operating point
            if (s.valid && s.yReader.valid) {
                const px = X(s.value), py = Y(s.yValue);
                const col = Qt.color(s.color);
                ctx.strokeStyle = rgba(fg, 0.18);
                ctx.setLineDash([3, 3]);
                ctx.beginPath(); ctx.moveTo(px, py); ctx.lineTo(px, y0 + ph); ctx.moveTo(px, py); ctx.lineTo(x0, py); ctx.stroke();
                ctx.setLineDash([]);
                ctx.fillStyle = rgba(col, 0.22);
                ctx.beginPath(); ctx.arc(px, py, r * 4, 0, Math.PI * 2); ctx.fill();
                ctx.fillStyle = col;
                ctx.beginPath(); ctx.arc(px, py, r * 2, 0, Math.PI * 2); ctx.fill();
                ctx.strokeStyle = rgba(fg, 0.9);
                ctx.lineWidth = 1.5;
                ctx.stroke();
            }
        }

        // the curve only grows with the temperatures the card really had
        readonly property var span: {
            rev;
            if (!fc.src) return null;
            const k = Object.keys(fc.src.bins).map(Number);
            return k.length ? { lo: Math.min(...k), hi: Math.max(...k) } : null;
        }
        QQC2.Label {
            x: canvas.padL + canvas.labelPx * 0.4
            y: canvas.padT + canvas.labelPx * 0.3
            width: Math.max(0, parent.width - x - canvas.padR - canvas.labelPx * 0.4)
            visible: fc.src && fc.src.trail.length >= 3 && canvas.span !== null && canvas.span.hi - canvas.span.lo < 8
            wrapMode: Text.WordWrap
            opacity: 0.5
            font.pixelSize: canvas.labelPx
            text: canvas.span === null ? ""
                  : (canvas.span.hi === canvas.span.lo ? i18n("So far only measured at %1 °C.", canvas.span.lo)
                                                       : i18n("So far only %1–%2 °C measured.", canvas.span.lo, canvas.span.hi))
                    + " " + i18n("The curve grows as the graphics card gets warmer, e.g. while gaming.")
        }
        QQC2.Label {
            // centred over the plot area and wrapped there (narrow tile: no overflow)
            x: canvas.padL
            width: Math.max(0, parent.width - canvas.padL - canvas.padR)
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            visible: fc.src && fc.src.trail.length < 3
            text: fc.src && (!fc.src.valid || !fc.src.yReader.valid) ? i18n("No data from the sensors") : i18n("Collecting data points …")
            opacity: 0.5
            font.pixelSize: canvas.labelPx * 1.2
        }
    }
}
