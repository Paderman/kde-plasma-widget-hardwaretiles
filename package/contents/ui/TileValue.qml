// SPDX-FileCopyrightText: 2026 Paderman
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2

// Big number + small unit (+ optional "/ total"), shrinks to fit `maxWidth`.
RowLayout {
    id: val
    property var tile
    property int big: Math.round(tile.u * 1.6)
    property real maxWidth: 1e9
    property bool showTotal: true

    // idle fan stop of a graphics card: a word instead of "0 RPM" / "0 %"
    readonly property bool fanStop: tile.ready && tile.src.valid && !!tile.src.reader && tile.src.reader.fanStopped
    readonly property bool isText: tile.ready && (tile.src.isText || fanStop)
    readonly property string num: !tile.ready ? "–" : fanStop ? i18n("Fan stop") : tile.src.numberText
    readonly property string unit: tile.ready && !fanStop ? tile.src.unitText : ""
    readonly property string total: showTotal && tile.ready && tile.src.totalText ? "/ " + tile.src.totalText : ""
    // texts ("Power-Limit, Temperatur") are set a bit smaller than numbers
    readonly property int base: isText && num.length > 4 ? Math.round(big * 0.62) : big

    TextMetrics { id: mNum; font.pixelSize: val.base; font.weight: Font.Bold; text: val.num }
    TextMetrics { id: mUnit; font.pixelSize: Math.round(val.base * 0.48); font.weight: Font.Medium; text: val.unit }
    TextMetrics { id: mTot; font.pixelSize: Math.round(val.base * 0.42); text: val.total }
    readonly property real natural: mNum.advanceWidth
                                   + (unit ? mUnit.advanceWidth + base * 0.1 : 0)
                                   + (total ? mTot.advanceWidth + base * 0.15 : 0)
    readonly property int size: Math.max(8, Math.floor(natural > maxWidth && maxWidth > 0 ? base * maxWidth / natural : base))

    spacing: Math.round(size * 0.1)

    QQC2.Label {
        Layout.alignment: Qt.AlignBaseline
        text: val.num
        font.pixelSize: val.size
        font.weight: Font.Bold
        font.features: { "tnum": 1 }
        color: val.tile.ready && val.tile.src.level > 0 ? val.tile.accent : val.tile.fg
        Behavior on color { ColorAnimation { duration: 400 } }
    }
    QQC2.Label {
        Layout.alignment: Qt.AlignBaseline
        visible: text !== ""
        text: val.unit
        font.pixelSize: Math.max(7, Math.round(val.size * 0.48))
        font.weight: Font.Medium
        opacity: val.tile.lightTheme ? 0.72 : 0.6
    }
    QQC2.Label {
        Layout.alignment: Qt.AlignBaseline
        Layout.leftMargin: Math.round(val.size * 0.05)
        visible: text !== ""
        text: val.total
        font.pixelSize: Math.max(7, Math.round(val.size * 0.42))
        opacity: val.tile.lightTheme ? 0.62 : 0.45
    }
}
