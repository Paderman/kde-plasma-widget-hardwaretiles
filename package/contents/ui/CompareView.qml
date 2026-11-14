// SPDX-FileCopyrightText: 2026 Paderman
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.quickcharts as Charts
import "Hardware.js" as Hardware

// Content of a compare tile: the same value for several graphics cards,
// each in the colour of its card. tile.srcs = [{src, slot, tag}]
ColumnLayout {
    id: cv
    property var tile
    readonly property var srcs: tile.srcs
    readonly property real u: tile.u
    readonly property color fg: tile.fg
    readonly property bool lightTheme: tile.lightTheme
    spacing: Kirigami.Units.smallSpacing

    // narrow tiles: drop the words all card names share ("RTX 3080" / "RTX 3060 Ti" -> "3080" / "3060 Ti")
    readonly property bool narrow: width < u * 11
    readonly property var shortTags: {
        const words = srcs.map(e => (e.tag || "").split(" "));
        let k = 0;
        while (words.length > 1 && words.every(w => w.length > k + 1 && w[k] === words[0][k])) k++;
        return words.map(w => w.slice(k).join(" "));
    }
    function tagOf(e, i) { return narrow && shortTags[i] ? shortTags[i] : e.tag; }

    // colour of a card; warn/crit colours win
    function colorOf(e) {
        return e.src && e.src.level > 0 ? e.src.color : Hardware.gpuColor(e.slot, cv.lightTheme);
    }

    TileHeader { tile: cv.tile; Layout.fillWidth: true }

    Loader {
        Layout.fillWidth: true
        Layout.fillHeight: true
        sourceComponent: cv.tile.style === "graph" ? graphC
                       : cv.tile.style === "bar" ? barC
                       : cv.tile.style === "value" ? valueC
                       : ringC
    }

    // one legend line: ● RTX 3080   62 °C
    component Legend: RowLayout {
        id: lg
        property var entry
        property string tag: entry ? entry.tag : ""
        property int size: Math.round(cv.u * 0.62)
        property bool showTag: true
        spacing: Math.round(cv.u * 0.3)
        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: Math.round(lg.size * 0.6)
            Layout.preferredHeight: Layout.preferredWidth
            radius: width / 2
            color: cv.colorOf(lg.entry)
        }
        QQC2.Label {
            visible: lg.showTag
            Layout.fillWidth: true
            text: lg.tag
            elide: Text.ElideRight
            font.pixelSize: lg.size
            opacity: 0.7
        }
        QQC2.Label {
            text: lg.entry.src ? lg.entry.src.formatted : "–"
            font.pixelSize: Math.round(lg.size * 1.15)
            font.weight: Font.DemiBold
            font.features: { "tnum": 1 }
            color: lg.entry.src && lg.entry.src.level > 0 ? lg.entry.src.color : cv.fg
        }
    }

    // ------------------------------------------------------------------ ring
    // concentric arcs, outermost = first card; values in the middle
    Component {
        id: ringC
        Item {
            id: ringBox
            readonly property real base: Math.min(width, height * 1.1)
            readonly property real thick: Math.max(3, base * 0.075)
            readonly property real step: thick * 1.45
            Repeater {
                model: cv.srcs
                delegate: RingGauge {
                    required property var modelData
                    required property int index
                    anchors.centerIn: parent
                    width: ringBox.base - index * 2 * ringBox.step
                    height: width
                    thickness: ringBox.thick
                    glow: false
                    fraction: modelData.src ? modelData.src.fraction : 0
                    color: cv.colorOf(modelData)
                    trackColor: Qt.rgba(cv.fg.r, cv.fg.g, cv.fg.b, 0.08)
                }
            }
            Column {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: ringBox.base * 0.03
                spacing: 0
                Repeater {
                    model: cv.srcs
                    delegate: QQC2.Label {
                        required property var modelData
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: modelData.src ? modelData.src.formatted : "–"
                        font.pixelSize: Math.max(8, Math.round(Math.min(ringBox.base * 0.15,
                                        (ringBox.base - cv.srcs.length * 2 * ringBox.step) * 0.75 / Math.max(1, cv.srcs.length))))
                        font.weight: Font.Bold
                        font.features: { "tnum": 1 }
                        color: cv.colorOf(modelData)
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------------- bar
    // one row per card: tag + value, bar below
    Component {
        id: barC
        ColumnLayout {
            spacing: Math.round(cv.u * 0.35)
            Item { Layout.fillHeight: true }
            Repeater {
                model: cv.srcs
                delegate: ColumnLayout {
                    id: row
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    spacing: Math.round(cv.u * 0.15)
                    Legend { entry: row.modelData; tag: cv.tagOf(row.modelData, row.index); Layout.fillWidth: true }
                    Item {
                        id: bb
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.round(cv.u * 0.38)
                        property real shown: row.modelData.src && isFinite(row.modelData.src.fraction) ? row.modelData.src.fraction : 0
                        Behavior on shown { NumberAnimation { duration: 700; easing.type: Easing.OutCubic } }
                        Rectangle {
                            anchors.fill: parent
                            radius: height / 2
                            color: Qt.rgba(cv.fg.r, cv.fg.g, cv.fg.b, 0.10)
                        }
                        Rectangle {
                            height: parent.height
                            width: bb.shown > 0.005 ? Math.max(height, parent.width * bb.shown) : 0
                            radius: height / 2
                            color: cv.colorOf(row.modelData)
                        }
                    }
                }
            }
            Item { Layout.fillHeight: true }
        }
    }

    // ----------------------------------------------------------------- graph
    // one line per card on a shared axis
    Component {
        id: graphC
        ColumnLayout {
            spacing: Kirigami.Units.smallSpacing
            Flow {
                Layout.fillWidth: true
                spacing: Math.round(cv.u * 0.8)
                Repeater {
                    model: cv.srcs
                    delegate: Legend {
                        required property var modelData
                        entry: modelData
                    }
                }
            }
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Repeater {
                    model: 3
                    Rectangle {
                        required property int index
                        width: parent.width; height: 1
                        y: Math.round(parent.height * (index + 1) / 4)
                        color: Qt.rgba(cv.fg.r, cv.fg.g, cv.fg.b, 0.06)
                    }
                }
                Charts.LineChart {
                    anchors.fill: parent
                    interpolate: true
                    lineWidth: Math.max(1.5, cv.u * 0.1)
                    fillOpacity: 0.12
                    direction: Charts.XYChart.ZeroAtEnd
                    yRange {
                        from: Math.min.apply(null, cv.srcs.map(e => e.src ? e.src.minimum : 0).concat([0]))
                        to: Math.max.apply(null, cv.srcs.map(e => e.src ? e.src.maximum : 0).concat([1]))
                        automatic: false
                    }
                    colorSource: Charts.ArraySource { array: cv.srcs.map(e => Hardware.gpuColor(e.slot, cv.lightTheme)) }
                    valueSources: cv.srcs.map(e => e.src.history)
                }
            }
        }
    }

    // ----------------------------------------------------------------- value
    Component {
        id: valueC
        ColumnLayout {
            spacing: Math.round(cv.u * 0.25)
            Item { Layout.fillHeight: true }
            Repeater {
                model: cv.srcs
                delegate: Legend {
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    entry: modelData
                    tag: cv.tagOf(modelData, index)
                    size: Math.round(cv.u * 0.75)
                }
            }
            Item { Layout.fillHeight: true }
        }
    }
}
