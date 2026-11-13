// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import qs.Commons

// Placed over a control that would otherwise take mouse-wheel input (sliders,
// combo boxes). The wheel scrolls the surrounding Flickable instead, so a
// setting never changes just because the pointer passed over it while
// scrolling. Clicks, drags and hover still reach the control underneath.
MouseArea {
  id: guard
  property Flickable target: null

  acceptedButtons: Qt.NoButton
  hoverEnabled: false

  function flickable() {
    if (guard.target) return guard.target
    var p = guard.parent
    while (p) {
      if (p.contentY !== undefined && typeof p.flick === "function") return p
      p = p.parent
    }
    return null
  }

  onWheel: function(wheel) {
    wheel.accepted = true
    var f = guard.flickable()
    if (!f || f.contentHeight <= f.height) return
    var dy = wheel.pixelDelta.y !== 0 ? wheel.pixelDelta.y : wheel.angleDelta.y / 120 * Style.space(60)
    var top = f.originY
    var bottom = f.originY + f.contentHeight - f.height
    f.contentY = Math.max(top, Math.min(bottom, f.contentY - dy))
  }
}
