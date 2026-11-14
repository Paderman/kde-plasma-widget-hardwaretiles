// SPDX-FileCopyrightText: 2026 Paderman
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Shapes

// 270° arc gauge with rounded caps, track and soft glow.
Item {
    id: ring

    property real fraction: 0
    property color color: "#8b7bff"
    property color trackColor: Qt.rgba(0.5, 0.5, 0.5, 0.18)
    property real thickness: Math.max(2, Math.min(width, height) * 0.09)
    property real sweep: 270
    property bool glow: true
    property real glowOpacity: 0.22
    // optional threshold markers: [{pos: 0..1, color: "#..."}]
    property var markers: []

    readonly property real _r: (Math.min(width, height) - thickness) / 2 - (glow ? thickness * 0.4 : 0)
    readonly property real _start: 90 + (360 - sweep) / 2

    property real _shown: isFinite(fraction) ? fraction : 0   // NaN would stick in the animation
    Behavior on _shown { NumberAnimation { duration: 700; easing.type: Easing.OutCubic } }
    Behavior on color { ColorAnimation { duration: 400 } }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        // track
        ShapePath {
            fillColor: "transparent"
            strokeColor: ring.trackColor
            strokeWidth: ring.thickness
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: ring.width / 2; centerY: ring.height / 2
                radiusX: ring._r; radiusY: ring._r
                startAngle: ring._start
                sweepAngle: ring.sweep
            }
        }
        // glow (wide, faint)
        ShapePath {
            fillColor: "transparent"
            strokeColor: ring.glow && ring._shown > 0.005 ? Qt.rgba(ring.color.r, ring.color.g, ring.color.b, ring.glowOpacity) : "transparent"
            strokeWidth: ring.thickness * 2.1
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: ring.width / 2; centerY: ring.height / 2
                radiusX: ring._r; radiusY: ring._r
                startAngle: ring._start
                sweepAngle: Math.max(0.01, ring.sweep * ring._shown)
            }
        }
        // value
        ShapePath {
            fillColor: "transparent"
            strokeColor: ring._shown > 0.005 ? ring.color : "transparent"
            strokeWidth: ring.thickness
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: ring.width / 2; centerY: ring.height / 2
                radiusX: ring._r; radiusY: ring._r
                startAngle: ring._start
                sweepAngle: Math.max(0.01, ring.sweep * ring._shown)
            }
        }
    }

    // threshold ticks on the outside of the ring
    Repeater {
        model: ring.markers
        delegate: Rectangle {
            required property var modelData
            readonly property real ang: (ring._start + ring.sweep * modelData.pos) * Math.PI / 180
            readonly property real rr: ring._r + ring.thickness * 0.95
            width: Math.max(1.5, ring.thickness * 0.28)
            height: ring.thickness * 0.7
            radius: width / 2
            color: modelData.color
            opacity: 0.85
            x: ring.width / 2 + Math.cos(ang) * rr - width / 2
            y: ring.height / 2 + Math.sin(ang) * rr - height / 2
            rotation: (ring._start + ring.sweep * modelData.pos) + 90
        }
    }
}
