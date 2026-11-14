// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import qs.Commons
import qs.Ui

// Pick-one row of Omarchy chip Buttons that wraps instead of overflowing.
// Same API as qs.Ui ButtonGroup (options, value, cursorIndex, changed,
// hovered). Long labels (host names stored on devices) are capped at the
// available width and elided by Button, so a chip can never leave its
// container.
Flow {
  id: chips
  property var options: []
  property string value: ""
  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property real fontSize: Style.font.body
  // Panel-cursor highlight (-1 for none), as in ButtonGroup.
  property int cursorIndex: -1
  signal changed(string value)
  signal hovered(int index, bool isHovered)

  width: parent ? parent.width : implicitWidth
  spacing: Style.spacing.md

  function optionValue(o) { return (o && typeof o === "object") ? String(o.value) : String(o) }
  function optionLabel(o) { return (o && typeof o === "object" && o.label !== undefined) ? String(o.label) : String(o) }
  function optionTooltip(o) { return (o && typeof o === "object" && o.tooltip) ? String(o.tooltip) : "" }

  Repeater {
    model: chips.options
    Button {
      required property var modelData
      required property int index
      width: Math.min(implicitWidth, chips.width)
      text: chips.optionLabel(modelData)
      tooltipText: chips.optionTooltip(modelData)
      selected: chips.optionValue(modelData) === chips.value
      hasCursor: chips.cursorIndex === index
      bordered: true
      focusable: true
      foreground: chips.foreground
      accent: chips.accent
      fontFamily: chips.fontFamily
      fontSize: chips.fontSize
      onClicked: chips.changed(chips.optionValue(modelData))
      onHovered: function(h) { chips.hovered(index, h) }
    }
  }
}
