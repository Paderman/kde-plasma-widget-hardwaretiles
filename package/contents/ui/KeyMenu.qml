// SPDX-FileCopyrightText: 2026 Paderman
// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import QtQuick.Controls as QQC2

// A menu that works well with the keyboard.
//
// 1. Breeze lets the list inside the menu handle the arrow keys itself – that
//    list also stops on separators and greyed-out headings, where no highlight
//    shows, so a key press seems to do nothing. Qt's own menu handling skips them.
// 2. While the arrow keys are used, a mouse pointer resting on the menu must not
//    take the highlight: when a submenu window opens, Plasma reports the pointer
//    to this menu again, the entry under it got highlighted and the submenu
//    closed at once. The entries follow the mouse again as soon as it really moves.
QQC2.Menu {
    id: menu
    // true while the highlight was moved without the mouse moving
    property bool keyNav: false
    // where the mouse stood when the keyboard took over; a small nudge does not
    // count – only a move as far as the system's drag start (Qt.styleHints)
    property point lastMouse: Qt.point(-1, -1)
    property double lastMove: 0

    function setItemHover(on) {
        for (let i = 0; i < count; ++i) {
            const it = itemAt(i);
            if (it && it.hoverEnabled !== undefined) it.hoverEnabled = on;
        }
    }
    onKeyNavChanged: setItemHover(!keyNav)
    // a new highlight without a recent mouse movement came from the keyboard –
    // checked after the event, so the mouse watcher has seen the same movement
    function checkKeyNav() { if (!keyNav && Date.now() - lastMove > 250) keyNav = true; }
    onCurrentIndexChanged: Qt.callLater(checkKeyNav)
    onAboutToShow: { keyNav = false; lastMouse = Qt.point(-1, -1); lastMove = 0; }

    property HoverHandler mouseWatch: null
    Component.onCompleted: {
        if (contentItem && contentItem.keyNavigationEnabled !== undefined)
            contentItem.keyNavigationEnabled = false;
        if (contentItem) {
            mouseWatch = Qt.createQmlObject('import QtQuick; HoverHandler { }', contentItem, "KeyMenuMouse");
            mouseWatch.pointChanged.connect(() => {
                if (!mouseWatch.hovered) return;
                const p = mouseWatch.point.scenePosition;
                if (lastMouse.x < 0 || !keyNav) {
                    // following the mouse: just remember where it is
                    if (lastMouse.x >= 0 && (p.x !== lastMouse.x || p.y !== lastMouse.y)) lastMove = Date.now();
                    lastMouse = Qt.point(p.x, p.y);
                    return;
                }
                // keyboard mode: the resting point stays until the mouse really leaves it
                if (Math.hypot(p.x - lastMouse.x, p.y - lastMouse.y) > Qt.styleHints.startDragDistance) {
                    lastMouse = Qt.point(p.x, p.y);
                    lastMove = Date.now();
                    keyNav = false;
                }
            });
        }
    }
}
