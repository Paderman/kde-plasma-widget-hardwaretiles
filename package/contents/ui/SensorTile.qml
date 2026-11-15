// SPDX-FileCopyrightText: 2026 Paderman
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.quickcharts as Charts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import "Explain.js" as Explain
import "Defaults.js" as Defaults

// A single card. `src` is a SensorSource.
Rectangle {
    id: card

    property var src: null
    property string style: "ring"
    property string tileStyle: "glass"
    // background opacity of the widget (0…1). The less of it there is, the more
    // solid the tile's own backing gets – text keeps its contrast on any wallpaper
    property real fillFactor: 1
    // how solid the backing gets at 0 % background (setting "tile opacity")
    property real backing: 0.85
    property real scale_: 1.0
    // drag & drop state (set by FullView)
    property bool dragging: false
    // graphics card marker (several GPUs without sections); transparent = none
    property color gpuColor: "transparent"
    // compare tile: [{src, slot, tag}] – one source per graphics card
    property var srcs: []
    readonly property bool comparing: srcs.length > 1 && style !== "curve"
    // narrow PCIe tile: short title (the section header already names the card)
    // in a GPU section the header already names the card
    property bool inSection: false
    readonly property bool compactPcie: ready && src.reader.isPcie && style === "value" && (inSection || width < u * 11)
    readonly property string headerText: compactPcie ? "PCIe" : ""
    opacity: dragging ? 0.35 : 1
    Behavior on opacity { NumberAnimation { duration: 150 } }

    // ring size: every ring tile reports the size it could have (ringNatural);
    // FullView sets ringLimit to the smallest, so all rings are the same size –
    // a name on two lines ("VRAM-Temperatur") no longer makes one ring smaller
    property real ringNatural: 0
    property real ringLimit: 0
    // same for the name: extra height of a two-line name (ringExtra), the
    // largest of all rings (ringExtraMax) – rings are placed as if every name
    // were that high, so they stay level
    property real ringExtra: 0
    property real ringExtraMax: 0
    readonly property bool ready: src !== null && src !== undefined
    readonly property color fg: Kirigami.Theme.textColor
    readonly property bool lightTheme: Kirigami.ColorUtils.brightnessForColor(Kirigami.Theme.backgroundColor) === Kirigami.ColorUtils.Light
    readonly property color accent: ready ? src.color : Kirigami.Theme.highlightColor
    readonly property real u: Kirigami.Units.gridUnit * scale_

    radius: Math.round(u * 0.75)
    clip: true

    // dark themes: a faint light film over the background; light themes: bright,
    // nearly opaque cards – a light film over a grey (translucent) background
    // would only look muddy
    readonly property color bg: Kirigami.Theme.backgroundColor
    // light: filled = nearly opaque, glass = clearly see-through, outline = only a
    // faint brightening so the grey background does not shine through untouched
    color: lightTheme ? Qt.rgba(bg.r, bg.g, bg.b, tileStyle === "solid" ? 0.95 : tileStyle === "outline" ? 0.3 : 0.4)
         : tileStyle === "outline" ? "transparent"
         : tileStyle === "solid" ? Qt.rgba(fg.r, fg.g, fg.b, 0.07)
         : Qt.rgba(fg.r, fg.g, fg.b, 0.045)
    border.width: tileStyle === "solid" && !lightTheme ? 0 : 1
    border.color: tileStyle === "outline" ? Qt.rgba(accent.r, accent.g, accent.b, 0.45)
                                          : Qt.rgba(fg.r, fg.g, fg.b, lightTheme ? 0.13 : 0.09)
    Behavior on border.color { ColorAnimation { duration: 400 } }

    // backing in the theme colour below the tile's fill (negative z = behind the
    // tile's own colour): stands in for the widget background that was faded out
    Rectangle {
        anchors.fill: parent
        z: -1
        radius: card.radius
        visible: card.fillFactor < 1
        color: Qt.rgba(card.bg.r, card.bg.g, card.bg.b, (1 - card.fillFactor) * card.backing)
    }

    // stripe on the left edge in the colour of the tile's graphics card
    Rectangle {
        visible: card.gpuColor.a > 0
        z: 2
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.topMargin: card.radius
        anchors.bottomMargin: card.radius
        width: Math.max(2, Math.round(card.u * 0.18))
        radius: width / 2
        color: card.gpuColor
    }

    // soft accent wash in the corner – reacts to warn/crit colour
    Rectangle {
        visible: card.tileStyle !== "outline"
        anchors.fill: parent
        radius: card.radius
        opacity: card.ready && card.src.level > 0 ? (card.lightTheme ? 0.12 : 0.22) : (card.lightTheme ? 0.05 : 0.10)
        Behavior on opacity { NumberAnimation { duration: 400 } }
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: card.accent }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }

    // pulsing ring when critical
    Rectangle {
        anchors.fill: parent
        radius: card.radius
        color: "transparent"
        border.width: 2
        border.color: Defaults.critColor(card.lightTheme)
        visible: card.ready && card.src.level === 2
        SequentialAnimation on opacity {
            running: card.ready && card.src.level === 2
            loops: Animation.Infinite
            NumberAnimation { from: 0.15; to: 0.9; duration: 900; easing.type: Easing.InOutSine }
            NumberAnimation { from: 0.9; to: 0.15; duration: 900; easing.type: Easing.InOutSine }
        }
    }

    // native Plasma tooltip: its own window, never clipped by the widget
    // true while the tile's context menu is open – the tooltip would cover it
    property bool menuOpen: false
    // "Edit tiles" mode: no tooltips while editing
    property bool arranging: false
    onMenuOpenChanged: if (menuOpen) tip.hideImmediately()

    TipArea {
        id: tip
        anchors.fill: parent
        z: 100
        wanted: card.ready && !card.dragging && !card.menuOpen && !card.arranging
        mainText: card.ready ? card.src.label : ""
        subText: {
            if (!card.ready) return "";
            const lines = [];
            const about = Explain.about(card.src.cfg, (...a) => i18n(...a));
            if (card.comparing) {
                card.srcs.forEach(e => lines.push(e.tag + ": " + e.src.formatted + (e.src.totalText ? " / " + e.src.totalText : "")));
                if (about) lines.push("", about);
                return lines.join("\n");
            }
            if (card.src.fullName && card.src.fullName !== card.src.label) lines.push(card.src.fullName);
            if (card.src.cfg.style === "curve") {
                if (card.src.valid && card.src.yReader.valid)
                    lines.push(i18n("Fan %1 at %2", card.src.yReader.formatted, card.src.formatted));
            } else {
                lines.push(card.src.formatted + (card.src.totalText ? " / " + card.src.totalText
                                                                   + "  (" + card.src.percentOf(card.src.value) + " %)" : ""));
                if (card.src.swapText) lines.push(card.src.swapText);
            }
            if (card.src.detailText) lines.push(card.src.detailText);
            if (card.src.reader.clientsText) lines.push(card.src.reader.clientsText);
            if (card.src.reader.fansText) lines.push(card.src.reader.fansText);
            if (card.src.reader.fanStopped)
                lines.push(i18n("Fan stop: the card has switched its fans off because it is cool enough. That is intended."));
            // plain-language part: what it measures, what the value means, thresholds
            const explain = [];
            if (about) explain.push(about);
            const nowText = card.src.valid ? Explain.now(card.src.cfg, card.src.formatted, card.src.value, (...a) => i18n(...a)) : "";
            if (nowText) explain.push(i18n("Now: %1", nowText));
            const th = card.thresholdText;
            if (th) explain.push(th);
            if (explain.length) lines.push("", explain.join("\n"));
            return lines.join("\n");
        }
        textFormat: Text.PlainText
        icon: "utilities-system-monitor"
    }

    // "Normal – Warnung ab 75 °C, kritisch ab 85 °C" (only for numeric tiles with thresholds)
    readonly property string thresholdText: {
        if (!ready || src.isText || !src.valid || src.cfg.style === "curve") return "";
        const w = src.warn, c = src.crit, lw = src.lowWarn, lc = src.lowCrit;
        const f = v => src.reader.format(v) + (src.relThresholds ? " (" + src.percentOf(v) + " %)" : "");
        const high = w > 0 || c > 0;
        if (!high && !src.hasLow) return "";
        if (src.low && src.level === 2) return i18n("Critical – below the threshold of %1.", f(lc));
        if (src.low && src.level === 1) return i18n("Low – below the warning threshold of %1.", f(lw));
        if (src.hasLow && high && src.level === 0)
            return i18n("In the normal range between %1 and %2.", f(lw > 0 ? lw : lc), f(w > 0 ? w : c));
        if (src.hasLow && src.level === 0) {
            if (lw > 0 && lc > 0) return i18n("In the normal range · warning below %1, critical below %2.", f(lw), f(lc));
            return lw > 0 ? i18n("In the normal range · warning below %1.", f(lw)) : i18n("In the normal range · critical below %1.", f(lc));
        }
        if (src.level === 2) return i18n("Critical – above the threshold of %1.", f(c));
        if (src.level === 1) return i18n("Elevated – above the warning threshold of %1.", f(w));
        if (w > 0 && c > 0) return i18n("In the normal range · warning from %1, critical from %2.", f(w), f(c));
        return w > 0 ? i18n("In the normal range · warning from %1.", f(w)) : i18n("In the normal range · critical from %1.", f(c));
    }

    readonly property var thresholdMarkers: {
        if (!ready) return [];
        const m = [];
        const span = Math.max(1e-9, src.maximum - src.minimum);
        if (src.warn > src.minimum && src.warn < src.maximum) m.push({ pos: (src.warn - src.minimum) / span, color: Defaults.warnColor(card.lightTheme) });
        if (src.crit > src.minimum && src.crit < src.maximum) m.push({ pos: (src.crit - src.minimum) / span, color: Defaults.critColor(card.lightTheme) });
        if (src.lowWarn > src.minimum && src.lowWarn < src.maximum) m.push({ pos: (src.lowWarn - src.minimum) / span, color: Defaults.warnColor(card.lightTheme) });
        if (src.lowCrit > src.minimum && src.lowCrit < src.maximum) m.push({ pos: (src.lowCrit - src.minimum) / span, color: Defaults.critColor(card.lightTheme) });
        return m;
    }

    implicitWidth: u * 8
    implicitHeight: style === "ring" ? u * 7.4
                  : style === "curve" ? u * 9.5
                  : style === "graph" ? u * 7.4
                  : style === "bar" ? (comparing ? Math.max(u * 5.0, u * (2.8 + srcs.length * 1.75))
                                                 : Math.max(u * 5.0, loader.item ? loader.item.implicitHeight + pad * 2 : 0))
                  : comparing ? Math.max(u * 5.0, u * (2.6 + srcs.length * 1.3))
                  : Math.max(u * 5.0, loader.item ? loader.item.implicitHeight + pad * 2 : 0)
    readonly property real pad: Math.round(u * 0.7)

    Loader {
        id: loader
        anchors.fill: parent
        anchors.margins: card.pad
        sourceComponent: card.comparing ? compareStyle
                       : card.style === "curve" ? curveStyle
                       : card.style === "bar" ? barStyle
                       : card.style === "graph" ? graphStyle
                       : card.style === "value" ? valueStyle
                       : ringStyle
    }

    // ------------------------------------------------------------------ ring
    Component {
        id: ringStyle
        ColumnLayout {
            spacing: Kirigami.Units.smallSpacing
            TileHeader {
                id: ringHeader
                tile: card
                Layout.fillWidth: true
                onExtraHeightChanged: card.ringExtra = extraHeight
                Component.onCompleted: card.ringExtra = extraHeight
            }
            Item {
                id: ringArea
                Layout.fillWidth: true
                Layout.fillHeight: true
                readonly property real natural: Math.max(0, Math.min(width, height * 1.1))
                onNaturalChanged: card.ringNatural = natural
                Component.onCompleted: card.ringNatural = natural
                Component.onDestruction: card.ringNatural = 0
                RingGauge {
                    id: gauge
                    anchors.horizontalCenter: parent.horizontalCenter
                    // placed as if the name were as high as the highest ring name, so rings stay level
                    y: {
                        const e = ringHeader.extraHeight, emax = Math.max(e, card.ringExtraMax);
                        return emax - e + (ringArea.height + e - emax - height) / 2;
                    }
                    width: card.ringLimit > 0 ? Math.min(ringArea.natural, card.ringLimit) : ringArea.natural
                    height: width
                    fraction: card.ready ? card.src.fraction : 0
                    color: card.accent
                    trackColor: Qt.rgba(card.fg.r, card.fg.g, card.fg.b, card.lightTheme ? 0.09 : 0.10)
                    glowOpacity: card.lightTheme ? 0.12 : 0.22
                    markers: card.thresholdMarkers
                }
                TileValue {
                    tile: card
                    anchors.centerIn: gauge
                    anchors.verticalCenterOffset: gauge.height * 0.03
                    big: Math.round(Math.max(card.u * 0.8, gauge.height * 0.25))
                    maxWidth: gauge.width * 0.62
                }
            }
        }
    }

    // ------------------------------------------------------------------- bar
    Component {
        id: barStyle
        ColumnLayout {
            id: barCol
            spacing: Math.round(card.u * 0.3)
            TileHeader { tile: card; Layout.fillWidth: true }
            Item { Layout.fillHeight: true }
            RowLayout {
                Layout.fillWidth: true
                TileValue {
                    id: barValue
                    tile: card
                    big: Math.round(card.u * 1.35)
                    maxWidth: barCol.width
                }
                Item { Layout.fillWidth: true }
                QQC2.Label {
                    Layout.alignment: Qt.AlignBottom
                    // only if it fits next to the value – narrow tiles would cut it off ("100 9")
                    visible: card.ready && card.src.valid && !card.src.isText && card.src.totalText === ""
                         && card.src.unitText !== "%"
                         && barValue.implicitWidth + implicitWidth + card.u * 0.5 <= barCol.width
                    text: card.ready ? Math.round(card.src.fraction * 100) + " %" : ""
                    font.pixelSize: Math.round(card.u * 0.6)
                    font.features: { "tnum": 1 }
                    opacity: card.lightTheme ? 0.65 : 0.45
                }
            }
            Item {
                id: barBox
                Layout.fillWidth: true
                Layout.preferredHeight: Math.round(card.u * 0.5)
                property real shown: card.ready && isFinite(card.src.fraction) ? card.src.fraction : 0
                Behavior on shown { NumberAnimation { duration: 700; easing.type: Easing.OutCubic } }

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: Qt.rgba(card.fg.r, card.fg.g, card.fg.b, 0.10)
                }
                // glow
                Rectangle {
                    x: -height * 0.17; y: -height * 0.17
                    height: parent.height * 1.34
                    width: barBox.shown > 0.005 ? Math.max(height, parent.width * barBox.shown + height * 0.34) : 0
                    radius: height / 2
                    color: card.accent
                    opacity: card.lightTheme ? 0.1 : 0.2
                }
                Rectangle {
                    height: parent.height
                    width: barBox.shown > 0.005 ? Math.max(height, parent.width * barBox.shown) : 0
                    radius: height / 2
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: Qt.lighter(card.accent, card.lightTheme ? 1.25 : 1.4) }
                        GradientStop { position: 1.0; color: card.accent }
                    }
                }
                Repeater {
                    model: card.thresholdMarkers
                    delegate: Rectangle {
                        required property var modelData
                        width: 2; radius: 1
                        height: barBox.height + 6
                        y: -3
                        x: barBox.width * modelData.pos - 1
                        color: modelData.color
                        opacity: 0.9
                    }
                }
            }
        }
    }

    // ----------------------------------------------------------------- graph
    Component {
        id: graphStyle
        ColumnLayout {
            id: graphCol
            spacing: Kirigami.Units.smallSpacing
            TileHeader { tile: card; Layout.fillWidth: true }
            TileValue {
                tile: card
                big: Math.round(card.u * 1.35)
                maxWidth: graphCol.width
            }
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                // baseline grid
                Repeater {
                    model: 3
                    Rectangle {
                        required property int index
                        width: parent.width; height: 1
                        y: Math.round(parent.height * (index + 1) / 4)
                        color: Qt.rgba(card.fg.r, card.fg.g, card.fg.b, 0.06)
                    }
                }
                Charts.LineChart {
                    anchors.fill: parent
                    interpolate: true
                    lineWidth: Math.max(1.5, card.u * 0.11)
                    fillOpacity: 0.3
                    direction: Charts.XYChart.ZeroAtEnd
                    yRange {
                        from: card.ready ? card.src.minimum : 0
                        to: card.ready ? card.src.maximum : 100
                        automatic: false
                    }
                    colorSource: Charts.SingleValueSource { value: card.accent }
                    valueSources: card.ready ? [card.src.history] : []
                }
            }
        }
    }

    // --------------------------------------------------------------- compare
    Component {
        id: compareStyle
        CompareView { tile: card }
    }

    // ----------------------------------------------------------------- curve
    Component {
        id: curveStyle
        FanCurve { tile: card }
    }

    // ----------------------------------------------------------------- value
    Component {
        id: valueStyle
        ColumnLayout {
            id: valueCol
            spacing: 0
            // narrow PCIe tile: only "Gen 3 ×8" – card name and slot details are in the tooltip
            readonly property bool compact: card.compactPcie
            TileHeader { tile: card; Layout.fillWidth: true }
            // device name (e.g. graphics card of the PCIe tile)
            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: Math.round(card.u * 0.25)
                visible: card.ready && card.src.subtitleText !== "" && !valueCol.compact
                spacing: 0
                QQC2.Label {
                    Layout.fillWidth: true
                    text: card.ready ? card.src.subtitleText : ""
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    font.pixelSize: Math.round(card.u * 0.78)
                    font.weight: Font.DemiBold
                    opacity: 0.9
                }
                QQC2.Label {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: card.ready ? card.src.subtitleInfo : ""
                    elide: Text.ElideRight
                    font.pixelSize: Math.round(card.u * 0.55)
                    opacity: 0.5
                }
            }
            Item { Layout.fillHeight: true }
            TileValue {
                tile: card
                big: Math.round(card.u * (card.ready && card.src.detailText && !valueCol.compact ? 1.45 : 1.7))
                maxWidth: valueCol.width
            }
            QQC2.Label {
                Layout.fillWidth: true
                Layout.topMargin: Math.round(card.u * 0.15)
                visible: text !== "" && !valueCol.compact
                text: card.ready ? card.src.detailText : ""
                wrapMode: Text.WordWrap
                maximumLineCount: 3
                elide: Text.ElideRight
                font.pixelSize: Math.max(8, Math.round(card.u * 0.55))
                lineHeight: 1.1
                color: card.ready && card.src.level > 0 ? card.accent : card.fg
                opacity: card.ready && card.src.level > 0 ? 0.95 : 0.55
            }
            Item { Layout.fillHeight: true }
        }
    }
}
