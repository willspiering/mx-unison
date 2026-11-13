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
  // Stack the control under the label instead of beside it (wide controls).
  property bool stacked: false
  readonly property real labelWidth: stacked ? width : Math.min(Style.space(230), Math.round(width * 0.38))
  default property alias control: slot.data
  signal toggled()

  width: parent ? parent.width : implicitWidth
  // Top row: label (with leader) beside the control. Help runs full width
  // underneath, so long explanations never squeeze the label column.
  readonly property real rowHeight: stacked
    ? labelRow.implicitHeight + Style.space(8) + slot.childrenRect.height
    : Math.max(labelRow.implicitHeight, slot.childrenRect.height, switchBox.visible ? switchBox.height : 0, Style.spacing.controlHeight)
  implicitHeight: rowHeight + (helpText.visible ? Style.space(4) + helpText.implicitHeight : 0)
  activeFocusOnTab: switchable
  opacity: enabled ? 1 : 0.45

  Keys.onSpacePressed: if (switchable && !busy) field.toggled()
  Keys.onReturnPressed: if (switchable && !busy) field.toggled()
  Keys.onEnterPressed: if (switchable && !busy) field.toggled()

  // Hover/focus wash for toggle rows, so the whole row reads as one control.
  Rectangle {
    visible: field.switchable
    anchors.fill: parent
    anchors.leftMargin: -Style.space(8)
    anchors.rightMargin: -Style.space(8)
    anchors.topMargin: -Style.space(4)
    anchors.bottomMargin: -Style.space(4)
    radius: Style.cornerRadius
    color: field.activeFocus || rowMouse.containsMouse ? Style.hoverFillFor(Color.foreground, Color.accent) : "transparent"
    Behavior on color { ColorAnimation { duration: Style.duration(100) } }
  }

  Row {
    id: labelRow
    width: field.switchable ? field.width - switchBox.width - Style.space(16) : field.labelWidth
    y: field.stacked ? 0 : Math.max(0, (field.rowHeight - implicitHeight) / 2)
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
    y: field.rowHeight + Style.space(4)
    width: field.switchable ? labelRow.width : field.width
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
    x: field.stacked ? 0 : field.labelWidth + Style.space(12)
    y: field.stacked ? labelRow.implicitHeight + Style.space(8) : Math.max(0, (field.rowHeight - childrenRect.height) / 2)
    width: field.width - x - (valueText.visible ? valueText.width + Style.space(12) : 0)
    height: childrenRect.height
  }

  Text {
    id: valueText
    visible: field.value !== "" && !field.switchable
    width: Math.max(implicitWidth, Style.space(72))
    anchors.right: parent.right
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
    y: Math.max(0, (field.rowHeight - height) / 2)
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
}
