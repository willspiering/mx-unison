// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import qs.Commons

// Block-character gauge: ▮▮▮▮▮▮▯▯▯▯ 60%. Read-only; used for battery and
// read progress. A negative value draws nothing (unknown).
Row {
  id: meter
  property real value: -1          // 0..1
  property int cells: 10
  property string suffix: ""
  property bool warn: false
  property real fontSize: Style.font.caption
  readonly property int filled: value < 0 ? 0 : Math.max(0, Math.min(cells, Math.round(value * cells)))
  visible: value >= 0
  spacing: Style.space(6)

  Row {
    anchors.verticalCenter: parent.verticalCenter
    Text {
      text: "▮".repeat(meter.filled)
      textFormat: Text.PlainText
      color: meter.warn ? Color.urgent : Color.accent
      font.family: Style.font.family
      font.pixelSize: meter.fontSize
    }
    Text {
      text: "▯".repeat(meter.cells - meter.filled)
      textFormat: Text.PlainText
      color: Qt.alpha(Color.foreground, 0.25)
      font.family: Style.font.family
      font.pixelSize: meter.fontSize
    }
  }
  Text {
    visible: meter.suffix !== ""
    text: meter.suffix
    textFormat: Text.PlainText
    color: meter.warn ? Color.urgent : Color.foreground
    font.family: Style.font.family
    font.pixelSize: meter.fontSize
    anchors.verticalCenter: parent.verticalCenter
  }
}
