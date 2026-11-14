// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import qs.Commons
import qs.Ui

// One setting row, terminal-style:
//
//   sensitivity ··········  [control]            1600 dpi
//     help text, shown inline under the label
//
// Put any control inside as a child; it is laid out in the right-hand slot
// and should bind `width: parent.width`. With `switchable: true` the row is
// a toggle instead: the whole row is the click target (and Space/Enter with
// keyboard focus), and an Omarchy ToggleSwitch shows the state.
FocusScope {
  id: field
  property string label: ""
  property string help: ""
  // Short readout right of the control (e.g. "1600 dpi"); empty hides it.
  property string value: ""
  property bool switchable: false
  property bool checked: false
  property bool busy: false
  // Panel-cursor highlight for popups that drive their own keyboard cursor.
  property bool hasCursor: false
  // Stack the control under the label instead of beside it (wide controls).
  property bool stacked: false
  // Inner padding on every row, highlighted or not, so the hover/cursor
  // wash never touches the text and plain rows line up with toggle rows.
  readonly property real padX: Style.space(10)
  readonly property real padY: Style.space(6)
  readonly property real innerWidth: Math.max(0, width - padX * 2)
  readonly property real labelWidth: stacked ? innerWidth : Math.min(Style.space(230), Math.round(innerWidth * 0.38))
  default property alias control: slot.data
  signal toggled()
  signal hovered(bool isHovered)

  width: parent ? parent.width : implicitWidth
  // Top row: label (with leader) beside the control. Help runs full width
  // underneath, so long explanations never squeeze the label column.
  readonly property real rowHeight: stacked
    ? labelRow.implicitHeight + Style.space(8) + slot.childrenRect.height
    : Math.max(labelRow.implicitHeight, slot.childrenRect.height, switchBox.visible ? switchBox.height : 0, Style.spacing.controlHeight)
  implicitHeight: padY * 2 + rowHeight + (helpText.visible ? Style.space(4) + helpText.implicitHeight : 0)
  activeFocusOnTab: switchable
  opacity: enabled ? 1 : 0.45

  Keys.onSpacePressed: if (switchable && !busy) field.toggled()
  Keys.onReturnPressed: if (switchable && !busy) field.toggled()
  Keys.onEnterPressed: if (switchable && !busy) field.toggled()

  // Hover/focus wash for toggle rows, so the whole row reads as one control.
  Rectangle {
    visible: field.switchable || field.hasCursor
    anchors.fill: parent
    radius: Style.cornerRadius
    color: field.activeFocus || field.hasCursor || rowMouse.containsMouse ? Style.hoverFillFor(Color.foreground, Color.accent) : "transparent"
    Behavior on color { ColorAnimation { duration: Style.duration(100) } }
  }

  Row {
    id: labelRow
    x: field.padX
    width: field.switchable ? field.innerWidth - switchBox.width - Style.space(16) : field.labelWidth
    y: field.padY + (field.stacked ? 0 : Math.max(0, (field.rowHeight - implicitHeight) / 2))
    spacing: Style.space(6)
    Text {
      id: labelText
      width: Math.min(implicitWidth, parent.width)
      text: field.label
      textFormat: Text.PlainText
      color: Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }
    // Dotted leader from the label to the control.
    Text {
      visible: !field.stacked
      width: Math.max(0, parent.width - labelText.width - parent.spacing)
      clip: true
      text: "·····································································································"
      textFormat: Text.PlainText
      color: Qt.alpha(Color.foreground, 0.18)
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }
  }

  Text {
    id: helpText
    visible: field.help !== ""
    x: field.padX
    y: field.padY + field.rowHeight + Style.space(4)
    width: field.switchable ? labelRow.width : field.innerWidth
    text: field.help
    textFormat: Text.PlainText
    color: Qt.alpha(Color.foreground, 0.55)
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  Item {
    id: slot
    visible: !field.switchable
    x: field.padX + (field.stacked ? 0 : field.labelWidth + Style.space(12))
    y: field.padY + (field.stacked ? labelRow.implicitHeight + Style.space(8) : Math.max(0, (field.rowHeight - childrenRect.height) / 2))
    width: field.width - field.padX - x - (valueText.visible ? valueText.width + Style.space(12) : 0)
    height: childrenRect.height
  }

  Text {
    id: valueText
    visible: field.value !== "" && !field.switchable
    width: Math.max(implicitWidth, Style.space(72))
    anchors.right: parent.right
    anchors.rightMargin: field.padX
    y: slot.y + Math.max(0, (slot.height - height) / 2)
    horizontalAlignment: Text.AlignRight
    text: field.value
    textFormat: Text.PlainText
    color: Color.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }

  Item {
    id: switchBox
    visible: field.switchable
    anchors.right: parent.right
    anchors.rightMargin: field.padX
    y: field.padY + Math.max(0, (field.rowHeight - height) / 2)
    width: track.width
    height: track.height
    ToggleSwitch {
      id: track
      checked: field.checked
      busy: field.busy
      interactive: false
      foreground: Color.foreground
      accent: Color.accent
    }
  }

  MouseArea {
    id: rowMouse
    visible: field.switchable
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: {
      field.forceActiveFocus()
      if (!field.busy) field.toggled()
    }
  }

  HoverHandler {
    onHoveredChanged: field.hovered(hovered)
  }
}
