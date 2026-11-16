// SPDX-FileCopyrightText: 2026 Paderman
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import "Hyphen.js" as Hyphen

RowLayout {
    id: header
    property var tile
    spacing: Math.round(tile.u * 0.3)
    // "Edit tiles": the × button sits in the top right corner – long names
    // ("GEHÄUSE-TEMPERATUR") wrap before it instead of running under it.
    // false where the header shares its row with values (fan curve: that row keeps the space)
    property bool keepCloseFree: true
    Layout.rightMargin: keepCloseFree && tile.arranging === true ? Math.round(tile.u * 1.2) : 0

    readonly property real dotSize: Math.round(tile.u * 0.4)
    readonly property real fullSize: Math.round(tile.u * 0.62)
    readonly property string text: !tile.ready ? "" : (tile.headerText || tile.src.label)
    // with break points in long compound words ("Arbeits-|speicher")
    // (only if the name then still fits on two lines, otherwise it gets a smaller font as before)
    readonly property string hyphenated: Hyphen.hyphenate(text)
    readonly property string shownText: hyphenated !== text && probe.lineCount > 2 ? text : hyphenated

    // invisible test copy in full size: how many lines the hyphenated name needs
    QQC2.Label {
        id: probe
        visible: false
        Layout.preferredWidth: 0
        Layout.preferredHeight: 0
        width: header.textWidth
        text: header.hyphenated
        wrapMode: Text.WordWrap
        font: longest.font
    }
    // width the name may use (not label.width – that would depend on the font size)
    readonly property real textWidth: Math.max(0, width - dotSize - spacing)

    // height of the lines after the first (0 for a one-line name)
    readonly property real extraHeight: label.lineCount > 1 ? Math.max(0, label.contentHeight - label.lineH) : 0

    // longest piece that cannot be broken (hyphens and soft hyphens may break;
    // a piece before a soft hyphen gets its "-" when it wraps)
    TextMetrics {
        id: longest
        font.pixelSize: header.fullSize
        font.weight: Font.DemiBold
        font.letterSpacing: 0.6
        font.capitalization: Font.AllUppercase
        text: header.shownText.split(/\s+/).map(w => w.replace(/-/g, "-\n").replace(/\u00AD/g, "-\n")).join("\n").split("\n")
                  .reduce((a, b) => b.length > a.length ? b : a, "")
    }

    Rectangle {
        // aligned to the first line, so it stays in place when the name wraps
        Layout.alignment: Qt.AlignTop
        Layout.topMargin: Math.max(0, Math.round((label.lineH - height) / 2))
        Layout.preferredWidth: header.dotSize
        Layout.preferredHeight: Layout.preferredWidth
        radius: width / 2
        color: header.tile.accent
        Behavior on color { ColorAnimation { duration: 400 } }
    }
    QQC2.Label {
        id: label
        // long names ("Gehäuselüfter vorne") wrap at word boundaries in full size;
        // only a single word that is too wide makes this header a little smaller
        readonly property real lineH: lineCount > 0 ? contentHeight / lineCount : font.pixelSize * 1.2
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        text: header.shownText
        wrapMode: Text.WordWrap
        maximumLineCount: 2
        elide: Text.ElideRight
        font.pixelSize: header.textWidth > 0 && longest.advanceWidth > header.textWidth
                        ? Math.max(Math.round(header.tile.u * 0.45), Math.floor(header.fullSize * header.textWidth / longest.advanceWidth * 0.97))
                        : header.fullSize
        font.weight: Font.DemiBold
        font.letterSpacing: 0.6
        font.capitalization: Font.AllUppercase
        opacity: header.tile.lightTheme ? 0.8 : 0.65
    }
}
