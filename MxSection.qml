// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import qs.Commons

// A titled block of the settings window, drawn terminal-style:
//
//   POINTER ──────────────────────────────
//     optional one-line explanation
//     <fields>
//
// Sections replace boxed cards: the rule and the spacing between sections
// separate content without stacking frames inside frames.
Column {
  id: section
  property string title: ""
  // Identifies the section for sidebar jump links.
  property string anchorKey: ""
  property string hint: ""
  // Right-aligned text on the title rule, e.g. a live status.
  property string status: ""
  property color statusColor: Qt.alpha(Color.foreground, 0.55)
  default property alias contents: body.data

  width: parent ? parent.width : implicitWidth
  spacing: Style.space(12)

  Item {
    width: parent.width
    implicitHeight: heading.implicitHeight
    Text {
      id: heading
      text: section.title.toUpperCase()
      textFormat: Text.PlainText
      color: Color.accent
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1.5
      anchors.verticalCenter: parent.verticalCenter
    }
    Rectangle {
      anchors.left: heading.right
      anchors.leftMargin: Style.space(10)
      anchors.right: statusText.visible ? statusText.left : parent.right
      anchors.rightMargin: statusText.visible ? Style.space(10) : 0
      anchors.verticalCenter: parent.verticalCenter
      height: 1
      color: Qt.alpha(Color.foreground, 0.14)
    }
    Text {
      id: statusText
      visible: section.status !== ""
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: section.status
      textFormat: Text.PlainText
      color: section.statusColor
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }

  Text {
    visible: section.hint !== ""
    width: parent.width
    text: section.hint
    textFormat: Text.PlainText
    color: Qt.alpha(Color.foreground, 0.55)
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  Column {
    id: body
    width: parent.width
    spacing: Style.space(10)
  }
}
