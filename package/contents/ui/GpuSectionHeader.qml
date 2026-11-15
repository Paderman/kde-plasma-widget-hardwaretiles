// SPDX-FileCopyrightText: 2026 Paderman
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore

// Full-width header above the tiles of one graphics card. For a card it also
// shows the PCIe link as a small badge (orange when lanes are missing) and all
// details in a tooltip – this replaces the separate PCIe tile.
Item {
    id: hdr
    property string title
    property string info
    property string addr: ""          // PCI address of the card ("" = no card, e.g. "System")
    property string driver: ""
    property int interval: 1500
    property color accent: Kirigami.Theme.highlightColor
    property real u: Kirigami.Units.gridUnit
    readonly property bool coloured: accent.a > 0
    readonly property color fg: Kirigami.Theme.textColor
    readonly property color warnColor: Kirigami.ColorUtils.brightnessForColor(Kirigami.Theme.backgroundColor) === Kirigami.ColorUtils.Light
                                       ? "#a35a00" : "#ffb020"   // same as Defaults.warnColor

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight + Math.round(u * 0.25)

    Reader {
        id: link
        enabled_: hdr.addr !== ""
        source: "pcie"
        key: hdr.addr
        interval: hdr.interval
    }
    readonly property bool hasLink: addr !== "" && link.valid
    readonly property bool linkWarn: hasLink && link.forcedLevel > 0

    RowLayout {
        id: row
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Math.round(hdr.u * 0.5)

        Rectangle {
            Layout.preferredWidth: Math.round(hdr.u * 0.28)
            Layout.preferredHeight: Math.round(hdr.u * 1.1)
            radius: width / 2
            color: hdr.coloured ? hdr.accent : Qt.rgba(hdr.fg.r, hdr.fg.g, hdr.fg.b, 0.35)
        }
        QQC2.Label {
            text: hdr.title
            font.pixelSize: Math.round(hdr.u * 0.78)
            font.weight: Font.Bold
            font.letterSpacing: 0.4
            color: hdr.coloured ? Qt.lighter(hdr.accent, 1.15) : hdr.fg
        }
        // PCIe link badge
        Rectangle {
            visible: hdr.hasLink
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: badge.implicitWidth + Math.round(hdr.u * 0.6)
            implicitHeight: badge.implicitHeight + Math.round(hdr.u * 0.15)
            radius: height / 2
            readonly property color c: hdr.linkWarn ? hdr.warnColor : hdr.fg
            color: Qt.rgba(c.r, c.g, c.b, hdr.linkWarn ? 0.16 : 0.08)
            border.width: 1
            border.color: Qt.rgba(c.r, c.g, c.b, hdr.linkWarn ? 0.55 : 0.18)
            QQC2.Label {
                id: badge
                anchors.centerIn: parent
                text: link.integrated ? link.formatted : (hdr.linkWarn ? "⚠ " : "") + "PCIe " + link.formatted
                font.pixelSize: Math.round(hdr.u * 0.56)
                font.weight: Font.DemiBold
                font.features: { "tnum": 1 }
                color: hdr.linkWarn ? hdr.warnColor : hdr.fg
                opacity: hdr.linkWarn ? 1 : 0.75
            }
        }
        QQC2.Label {
            Layout.fillWidth: true
            visible: text !== ""
            text: hdr.info
            elide: Text.ElideRight
            font.pixelSize: Math.round(hdr.u * 0.6)
            opacity: 0.55
        }
        // thin rule that fades out towards the right
        Rectangle {
            visible: hdr.info === ""
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Qt.rgba(hdr.fg.r, hdr.fg.g, hdr.fg.b, 0.18) }
                GradientStop { position: 1; color: "transparent" }
            }
        }
    }

    // details of the card (native Plasma tooltip)
    TipArea {
        anchors.fill: parent
        wanted: hdr.addr !== ""
        mainText: link.subtitle || hdr.title
        subText: {
            const lines = [];
            if (link.subtitleInfo) lines.push(link.subtitleInfo);
            lines.push(i18n("PCI address: %1", hdr.addr.replace(/^0000:/, "")) + (hdr.driver ? "  ·  " + i18n("Driver: %1", hdr.driver) : ""));
            if (hdr.hasLink) {
                lines.push("");
                if (link.integrated) {
                    lines.push(link.detail);
                } else {
                    lines.push(i18n("PCIe link: %1", link.formatted));
                    if (link.detail) lines.push(link.detail);
                    const n = link.name.split("\n");
                    if (n.length > 1) lines.push(n[n.length - 1]);
                }
            }
            return lines.join("\n");
        }
        textFormat: Text.PlainText
        icon: "video-display"
    }
}
