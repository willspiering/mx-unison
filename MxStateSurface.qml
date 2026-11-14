// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import qs.Commons
import qs.Ui

// The one background for every selectable row in the popup and the settings
// window (devices, sidebar entries, section links, button rows, toggle
// rows). It follows Omarchy Button's state order and theme tokens exactly,
// so an active row reads like a selected chip and hover/cursor like a
// hovered button:
//
//   pressed  > focus  > hover/cursor  > selected  > idle
//
// Put it behind a row with anchors.fill and bind the states; use
// `contentColor` / `contentBold` for the row's text so labels change with
// the background the same way a Button's label does.
BorderSurface {
  id: surface
  property bool selected: false
  property bool hot: false
  property bool focused: false
  property bool pressed: false
  property color foreground: Color.foreground
  property color accent: Color.accent

  readonly property color contentColor: selected ? Style.selectedStateColor(foreground, accent) : foreground
  readonly property bool contentBold: selected

  radius: Style.cornerRadius
  color: pressed ? Style.pressedFillFor(foreground, accent)
    : focused ? Style.focusFillFor(foreground, accent)
    : hot ? Style.hoverFillFor(foreground, accent)
    : selected ? Style.selectedFillFor(foreground, accent)
    : "transparent"
  borderSpec: focused ? Border.controlSpec("focus", foreground, accent)
    : hot ? Border.controlSpec("hover-cursor", foreground, accent)
    : selected ? (Border.controlHasWidth("selected") ? Border.controlSpec("selected", foreground, accent) : Border.controlSpec("normal", foreground, accent))
    : Border.none()

  Behavior on color { ColorAnimation { duration: Style.duration(120) } }
}
