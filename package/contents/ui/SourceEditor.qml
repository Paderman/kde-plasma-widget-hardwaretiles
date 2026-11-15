// SPDX-FileCopyrightText: 2026 Paderman
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.ksysguard.faces as Faces
import "NvidiaKeys.js" as NK

// Picks a value source: ksystemstats sensor, NVIDIA field or shell command.
// Emits edited(field, value) with field in source|sensorId|key|command|unit.
GridLayout {
    id: ed
    columns: 2
    columnSpacing: Kirigami.Units.largeSpacing
    rowSpacing: Kirigami.Units.smallSpacing

    property string title: i18n("Source:")
    property string source: "sensor"
    property string sensorId: ""
    property string key: ""
    property string command: ""
    property string unit: ""
    signal edited(string field, var value)

    readonly property var sources: [
        { value: "sensor",  text: i18n("System sensor (ksystemstats)") },
        { value: "nvidia",  text: i18n("NVIDIA graphics card (nvidia-smi)") },
        { value: "pcie",    text: i18n("PCIe link of the graphics card (kernel)") },
        { value: "igpu",    text: i18n("Intel graphics in the processor (kernel)") },
        { value: "command", text: i18n("Shell command") }
    ]

    QQC2.Label { text: ed.title }
    QQC2.ComboBox {
        wheelEnabled: false   // scrolling the page must not change the value
        Layout.fillWidth: true
        model: ed.sources
        textRole: "text"
        currentIndex: Math.max(0, ed.sources.findIndex(s => s.value === (ed.source || "sensor")))
        onActivated: (i) => ed.edited("source", ed.sources[i].value)
    }

    // ksystemstats
    QQC2.Label { text: i18n("Sensor:"); visible: ed.source === "sensor" || !ed.source }
    Faces.Choices {
        Layout.fillWidth: true
        visible: ed.source === "sensor" || !ed.source
        supportsColors: false
        labelsEditable: false
        maxAllowedSensors: 1
        selected: ed.sensorId ? [ed.sensorId] : []
        onSelectedChanged: {
            const id = (selected && selected.length) ? selected[0] : "";
            if (id !== ed.sensorId) ed.edited("sensorId", id);
        }
    }

    // nvidia
    QQC2.Label { text: i18n("Value:"); visible: ed.source === "nvidia" }
    QQC2.ComboBox {
        wheelEnabled: false   // scrolling the page must not change the value
        Layout.fillWidth: true
        visible: ed.source === "nvidia"
        model: NK.keys.map(k => ({ key: k.key, label: i18n(k.label) }))
        textRole: "label"
        currentIndex: ed.source === "nvidia" ? NK.indexOf(ed.key) : -1
        displayText: currentIndex < 0 ? i18n("Please choose …") : currentText
        onActivated: (i) => ed.edited("key", NK.keys[i].key)
    }

    // Intel graphics in the processor
    QQC2.Label { text: i18n("Value:"); visible: ed.source === "igpu" }
    QQC2.ComboBox {
        wheelEnabled: false   // scrolling the page must not change the value
        Layout.fillWidth: true
        visible: ed.source === "igpu"
        readonly property var keys: [{ key: "load", label: i18n("GPU load") }, { key: "clock", label: i18n("GPU clock") },
                                     { key: "render", label: i18n("3D load") }, { key: "video", label: i18n("Video load") },
                                     { key: "memory", label: i18n("Graphics memory") }]
        model: keys
        textRole: "label"
        currentIndex: ed.source === "igpu" ? keys.findIndex(k => k.key === ed.key) : -1
        displayText: currentIndex < 0 ? i18n("Please choose …") : currentText
        onActivated: (i) => ed.edited("key", keys[i].key)
    }

    // pcie
    QQC2.Label { text: i18n("Device:"); visible: ed.source === "pcie" }
    RowLayout {
        Layout.fillWidth: true
        visible: ed.source === "pcie"
        QQC2.TextField {
            Layout.fillWidth: true
            font.family: "monospace"
            placeholderText: i18n("automatic (first graphics card)")
            text: ed.source === "pcie" ? ed.key : ""
            onTextEdited: ed.edited("key", text.trim())
        }
        Kirigami.ContextualHelpButton {
            toolTipText: i18n("Optionally a PCI address like “02:00.0” (see lspci). Shows the actual link together with the maximum the card and slot support.")
        }
    }

    // shell command
    QQC2.Label { text: i18n("Command:"); visible: ed.source === "command" }
    RowLayout {
        Layout.fillWidth: true
        visible: ed.source === "command"
        QQC2.TextField {
            Layout.fillWidth: true
            font.family: "monospace"
            placeholderText: "cat /run/gddr6/vram"
            text: ed.command
            onTextEdited: ed.edited("command", text)
        }
        QQC2.TextField {
            Layout.preferredWidth: Kirigami.Units.gridUnit * 4
            placeholderText: i18n("Unit")
            text: ed.unit
            onTextEdited: ed.edited("unit", text)
        }
    }
}
