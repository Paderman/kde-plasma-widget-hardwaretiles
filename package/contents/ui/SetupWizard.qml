// SPDX-FileCopyrightText: 2026 Paderman
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import "Hardware.js" as Hardware

// First-run setup: 1) choose the graphics card(s)  2) choose what else to show.
Item {
    id: wiz

    property var probe                      // HardwareProbe
    property bool canCancel: false
    property string preselect: ""           // PCI address
    signal finished(var gpuAddrs, var opts)      // PCI addresses, hardware order
    signal cancelled()

    property int step: 0
    property var chosen: []                 // PCI addresses
    property bool touched: false            // user changed the selection
    property var opts: Hardware.defaultOptions()

    readonly property var gpus: probe ? probe.gpus : []
    readonly property var chosenGpus: gpus.filter(g => chosen.indexOf(g.addr) >= 0)
    readonly property var chosenGpu: chosenGpus.length ? chosenGpus[0] : null
    readonly property bool multi: chosenGpus.length > 1
    readonly property int tileCount: Hardware.build(multi ? chosenGpus : chosenGpu, opts, probe ? probe.hw : null, (...a) => i18n(...a)).length

    function toggle(addr) {
        touched = true;
        const c = chosen.slice();
        const i = c.indexOf(addr);
        if (i >= 0) c.splice(i, 1); else c.push(addr);
        chosen = c;
    }
    readonly property real u: Kirigami.Units.gridUnit
    readonly property color fg: Kirigami.Theme.textColor
    readonly property color hl: Kirigami.Theme.highlightColor

    onGpusChanged: if (!touched && !chosen.length && gpus.length) chosen = [Hardware.pickGpu(probe.hw, preselect).addr]

    function setOpt(k, v) { const o = Object.assign({}, opts); o[k] = v; opts = o; }

    // ------------------------------------------------------------------ card
    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width - u * 1.5, u * 30)
        height: Math.min(parent.height - u * 1.5, content.implicitHeight + u * 3)
        radius: u * 0.9
        color: Qt.rgba(fg.r, fg.g, fg.b, 0.045)
        border.width: 1
        border.color: Qt.rgba(fg.r, fg.g, fg.b, 0.10)

        // soft accent wash
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            opacity: 0.12
            gradient: Gradient {
                GradientStop { position: 0; color: wiz.chosenGpu ? Hardware.vendorColors[wiz.chosenGpu.vendor] : wiz.hl }
                GradientStop { position: 0.6; color: "transparent" }
            }
        }

        QQC2.ScrollView {
            anchors.fill: parent
            anchors.margins: u * 1.5
            contentWidth: availableWidth
            QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

            ColumnLayout {
                id: content
                width: parent.width
                spacing: u * 0.8

                // ---- header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: u * 0.6
                    Kirigami.Icon {
                        source: "utilities-system-monitor"
                        Layout.preferredWidth: u * 1.8
                        Layout.preferredHeight: u * 1.8
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        QQC2.Label {
                            text: i18n("Set up Hardware Tiles")
                            font.pixelSize: u * 1.15
                            font.weight: Font.Bold
                        }
                        QQC2.Label {
                            text: i18n("Step %1 of 2", wiz.step + 1)
                            opacity: 0.6
                        }
                    }
                    // step dots
                    Row {
                        spacing: u * 0.3
                        Repeater {
                            model: 2
                            Rectangle {
                                required property int index
                                width: index === wiz.step ? u * 1.2 : u * 0.45
                                height: u * 0.45
                                radius: height / 2
                                color: index <= wiz.step ? wiz.hl : Qt.rgba(wiz.fg.r, wiz.fg.g, wiz.fg.b, 0.25)
                                Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                            }
                        }
                    }
                }

                // ================================================= step 1: GPU
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: wiz.step === 0
                    spacing: u * 0.5

                    QQC2.Label {
                        Layout.fillWidth: true
                        text: wiz.gpus.length > 1 ? i18n("Which graphics cards should the widget show?")
                                                  : i18n("Which graphics card should the widget show?")
                        font.pixelSize: u * 0.95
                        font.weight: Font.DemiBold
                        wrapMode: Text.WordWrap
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        text: wiz.gpus.length > 1
                              ? i18n("You can choose several cards – each then gets its own colour-coded section.")
                              : i18n("All tile values will then refer to this card.")
                        wrapMode: Text.WordWrap
                        opacity: 0.65
                    }

                    // loading
                    RowLayout {
                        visible: !wiz.probe || !wiz.probe.ready
                        QQC2.BusyIndicator { running: parent.visible; Layout.preferredHeight: u * 2 }
                        QQC2.Label { text: i18n("Searching for graphics cards …"); opacity: 0.7 }
                    }
                    // nothing found
                    Kirigami.InlineMessage {
                        Layout.fillWidth: true
                        visible: wiz.probe && wiz.probe.ready && wiz.gpus.length === 0
                        type: Kirigami.MessageType.Warning
                        text: i18n("No supported graphics card found. You can still continue and show CPU, RAM & co.")
                    }

                    Repeater {
                        model: wiz.gpus
                        delegate: Rectangle {
                            id: gpuCard
                            required property var modelData
                            readonly property bool selected: wiz.chosen.indexOf(modelData.addr) >= 0
                            readonly property color vc: Hardware.vendorColors[modelData.vendor]
                            Layout.fillWidth: true
                            implicitHeight: gpuRow.implicitHeight + u * 1.2
                            radius: u * 0.6
                            color: selected ? Qt.rgba(wiz.hl.r, wiz.hl.g, wiz.hl.b, 0.14)
                                            : Qt.rgba(wiz.fg.r, wiz.fg.g, wiz.fg.b, hover.hovered ? 0.07 : 0.04)
                            border.width: selected ? 2 : 1
                            border.color: selected ? wiz.hl : Qt.rgba(wiz.fg.r, wiz.fg.g, wiz.fg.b, 0.10)
                            Behavior on color { ColorAnimation { duration: 150 } }

                            HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: wiz.toggle(gpuCard.modelData.addr) }

                            RowLayout {
                                id: gpuRow
                                anchors.fill: parent
                                anchors.margins: u * 0.6
                                spacing: u * 0.7

                                // vendor badge
                                Rectangle {
                                    Layout.preferredWidth: u * 3.4
                                    Layout.preferredHeight: u * 2.2
                                    radius: u * 0.45
                                    color: Qt.rgba(gpuCard.vc.r, gpuCard.vc.g, gpuCard.vc.b, 0.18)
                                    border.color: Qt.rgba(gpuCard.vc.r, gpuCard.vc.g, gpuCard.vc.b, 0.6)
                                    QQC2.Label {
                                        anchors.centerIn: parent
                                        text: gpuCard.modelData.vendor === "other" ? "GPU" : gpuCard.modelData.vendor.toUpperCase()
                                        font.weight: Font.Bold
                                        font.pixelSize: u * 0.62
                                        color: Qt.lighter(gpuCard.vc, 1.25)
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    QQC2.Label {
                                        Layout.fillWidth: true
                                        text: gpuCard.modelData.name
                                        font.weight: Font.DemiBold
                                        font.pixelSize: u * 0.9
                                        wrapMode: Text.WordWrap
                                    }
                                    QQC2.Label {
                                        Layout.fillWidth: true
                                        visible: text !== ""
                                        text: gpuCard.modelData.info
                                        opacity: 0.7
                                    }
                                    QQC2.Label {
                                        Layout.fillWidth: true
                                        text: i18n("PCI %1 · driver %2", gpuCard.modelData.addr.replace(/^0000:/, ""), gpuCard.modelData.driver)
                                        font: Kirigami.Theme.smallFont
                                        opacity: 0.5
                                    }
                                }
                                // check indicator
                                Rectangle {
                                    Layout.preferredWidth: u * 1.1
                                    Layout.preferredHeight: u * 1.1
                                    radius: u * 0.28
                                    color: gpuCard.selected ? wiz.hl : "transparent"
                                    border.width: 2
                                    border.color: gpuCard.selected ? wiz.hl : Qt.rgba(wiz.fg.r, wiz.fg.g, wiz.fg.b, 0.35)
                                    Kirigami.Icon {
                                        anchors.centerIn: parent
                                        width: parent.width * 0.8; height: width
                                        source: "checkmark"
                                        color: Kirigami.Theme.highlightedTextColor
                                        isMask: true
                                        visible: gpuCard.selected
                                    }
                                }
                            }
                        }
                    }

                    QQC2.Label {
                        Layout.fillWidth: true
                        visible: wiz.chosenGpus.some(g => g.vendor === "nvidia") && wiz.probe && !wiz.probe.hw.gddr6
                        wrapMode: Text.WordWrap
                        font: Kirigami.Theme.smallFont
                        opacity: 0.65
                        text: i18n("Note: the VRAM temperature of NVIDIA cards needs the gddr6 service (instructions: folder “gddr6-service” in the Hardware Tiles directory). Without it this tile is left out.")
                    }
                }

                // ============================================== step 2: extras
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: wiz.step === 1
                    spacing: u * 0.45

                    QQC2.Label {
                        Layout.fillWidth: true
                        text: i18n("What should be shown besides the graphics card?")
                        font.pixelSize: u * 0.95
                        font.weight: Font.DemiBold
                        wrapMode: Text.WordWrap
                    }

                    component OptionRow: Rectangle {
                        id: row
                        property string title
                        property string hint
                        property string iconName
                        property bool checked
                        property bool locked: false
                        signal toggled(bool on)
                        Layout.fillWidth: true
                        implicitHeight: optRow.implicitHeight + Kirigami.Units.gridUnit * 0.8
                        radius: Kirigami.Units.gridUnit * 0.5
                        readonly property color fg: Kirigami.Theme.textColor
                        readonly property color hl: Kirigami.Theme.highlightColor
                        color: checked ? Qt.rgba(hl.r, hl.g, hl.b, 0.10) : Qt.rgba(fg.r, fg.g, fg.b, 0.04)
                        border.width: 1
                        border.color: checked ? Qt.rgba(hl.r, hl.g, hl.b, 0.5) : Qt.rgba(fg.r, fg.g, fg.b, 0.08)
                        Behavior on color { ColorAnimation { duration: 150 } }
                        TapHandler { enabled: !row.locked; onTapped: row.toggled(!row.checked) }
                        RowLayout {
                            id: optRow
                            anchors.fill: parent
                            anchors.margins: Kirigami.Units.gridUnit * 0.4
                            anchors.leftMargin: Kirigami.Units.gridUnit * 0.6
                            spacing: Kirigami.Units.gridUnit * 0.6
                            Kirigami.Icon {
                                source: row.iconName
                                Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                                Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                                opacity: row.checked ? 1 : 0.55
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                QQC2.Label { text: row.title; font.weight: Font.DemiBold; Layout.fillWidth: true; elide: Text.ElideRight }
                                QQC2.Label { text: row.hint; opacity: 0.6; font: Kirigami.Theme.smallFont; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                            }
                            QQC2.Switch {
                                checked: row.checked
                                enabled: !row.locked
                                onToggled: row.toggled(checked)
                            }
                        }
                    }

                    OptionRow {
                        title: wiz.multi ? i18n("%1 graphics cards – basic values", wiz.chosenGpus.length)
                             : wiz.chosenGpu ? i18n("Graphics card – basic values") : i18n("No graphics card")
                        hint: wiz.multi ? wiz.chosenGpus.map(g => Hardware.gpuTag(g)).join(" + ") + " · " + i18n("one section per card with temperatures, load, power, VRAM, PCIe")
                            : wiz.chosenGpu ? wiz.chosenGpu.name + " · " + i18n("Temperatures, load, power, VRAM, PCIe") : i18n("Only the selected areas are shown")
                        iconName: "video-display"
                        checked: !!wiz.chosenGpu
                        locked: true
                    }
                    Repeater {
                        model: Hardware.categories
                        delegate: OptionRow {
                            required property var modelData
                            visible: (modelData.key !== "gpuDetails" || !!wiz.chosenGpu) && (!modelData.multiOnly || wiz.multi)
                            title: modelData.key === "gpuDetails" && wiz.multi ? i18n("Graphics cards – details (for each card)") : i18n(modelData.label)
                            hint: i18n(modelData.hint)
                            iconName: modelData.icon
                            checked: !!wiz.opts[modelData.key]
                            onToggled: (on) => wiz.setOpt(modelData.key, on)
                        }
                    }
                    // no mainboard fans found: explain why and offer to set up the sensor support
                    SensorSetup {
                        Layout.fillWidth: true
                        probe: wiz.probe
                        visible: !!wiz.opts.board && shown
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        Layout.topMargin: u * 0.3
                        text: i18np("Results in %1 tile – you can change the arrangement and details at any time later.",
                                    "Results in %1 tiles – you can change the arrangement and details at any time later.", wiz.tileCount)
                        wrapMode: Text.WordWrap
                        opacity: 0.6
                    }
                }

                // ---- buttons
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: u * 0.4
                    QQC2.Button {
                        visible: wiz.canCancel && wiz.step === 0
                        text: i18n("Cancel")
                        icon.name: "dialog-cancel"
                        onClicked: wiz.cancelled()
                    }
                    QQC2.Button {
                        visible: wiz.step > 0
                        text: i18n("Back")
                        icon.name: "go-previous"
                        onClicked: wiz.step--
                    }
                    Item { Layout.fillWidth: true }
                    QQC2.Button {
                        visible: wiz.step === 0
                        enabled: wiz.probe && wiz.probe.ready
                        text: i18n("Next")
                        icon.name: "go-next"
                        highlighted: true
                        onClicked: wiz.step = 1
                    }
                    QQC2.Button {
                        visible: wiz.step === 1
                        text: i18n("Finish")
                        icon.name: "dialog-ok-apply"
                        highlighted: true
                        onClicked: wiz.finished(wiz.chosenGpus.map(g => g.addr), wiz.opts)
                    }
                }
            }
        }
    }
}
