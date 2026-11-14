// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import qs.Commons

// Indents plain content (chip rows, buttons, captions) by the same gutter
// MxField rows pad their text with, so everything in a section lines up and
// hover/selection washes always have room around their content. Children
// should size against `parent.width` as usual.
Item {
  id: inset
  readonly property real gutter: Style.space(10)
  default property alias content: inner.data
  width: parent ? parent.width : implicitWidth
  implicitHeight: inner.childrenRect.height + inner.y * 2
  Column {
    id: inner
    x: inset.gutter
    y: Style.space(4)
    width: inset.width - inset.gutter * 2
    spacing: Style.space(8)
  }
}
