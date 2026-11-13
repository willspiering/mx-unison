import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The desk-wide part of Easy Switch: computers to switch the whole group to,
// and which devices move together (channels auto-matched by stored host
// name, manual mapping behind a disclosure). A single device's own channels
// live on its device page (DeviceChannels.qml).
Column {
  id: root
  required property var mx
  // True while one of this page's dropdown popups owns the keyboard.
  property bool dropdownOpen: false
  spacing: Style.space(36)
  Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  readonly property color dim: Qt.alpha(Color.foreground, 0.68)

  // Every edit is saved immediately. Edits keep the configuration valid
  // (channel changes swap, removing the follow keyboard turns follow off),
  // so there is no draft state to save or revert.
  property var draft: ({version: 1, keyboard: "", follow: false, members: {}})
  function reset() {
    draft = JSON.parse(JSON.stringify(mx.switchConfig))
  }
  function commit(next) {
    draft = next
    mx.saveSwitchConfig(next)
  }
  Component.onCompleted: reset()
  Connections {
    target: root.mx
    function onSwitchConfigChanged() { root.reset() }
  }
  function updateMember(did, channelIndex, value) {
    var next = JSON.parse(JSON.stringify(draft))
    if (channelIndex < 0) {
      // A joining device gets the channels whose stored names match the
      // computers the rest of the group already uses.
      if (value) next.members[did] = Model.matchChannels(next, devices, did)
      else {
        delete next.members[did]
        if (next.keyboard === did) { next.keyboard = ""; next.follow = false }
      }
    } else {
      // Swapping preserves a one-to-one target/channel mapping.
      var old = next.members[did][channelIndex]
      var other = next.members[did].indexOf(value)
      if (other < 0 || other === channelIndex) return
      next.members[did][other] = old
      next.members[did][channelIndex] = value
    }
    commit(next)
  }

  readonly property var devices: mx.displayDevices || []
  readonly property var memberIds: Object.keys(draft.members || {})
  readonly property var targets: Model.deskTargets(draft, devices)
  // The member whose names define the computers: the keyboard if there is
  // one, otherwise the first member (the same order deskTargets uses).
  readonly property string referenceId: {
    var ids = memberIds.slice().sort()
    if (draft.keyboard && draft.members[draft.keyboard]) return draft.keyboard
    return ids.length ? ids[0] : ""
  }
  function deviceById(did) {
    for (var i = 0; i < devices.length; i++) if (devices[i] && String(devices[i].id) === did) return devices[i]
    return null
  }
  function deviceName(did) {
    var dev = deviceById(did)
    return dev && dev.name ? String(dev.name) : strings.t("group.unknownDevice")
  }
  function isKeyboard(dev) {
    return String(dev && dev.kind || "").toLowerCase() === "keyboard"
  }
  function sameMapping(a, b) {
    return !!a && !!b && a[0] === b[0] && a[1] === b[1] && a[2] === b[2]
  }
  // Members whose stored channel names point at a different mapping.
  readonly property var mismatched: {
    var out = []
    for (var i = 0; i < memberIds.length; i++) {
      var did = memberIds[i]
      if (did === referenceId || !deviceById(did)) continue
      if (!sameMapping(Model.matchChannels(draft, devices, did), draft.members[did])) out.push(did)
    }
    return out
  }
  function matchAll() {
    var next = JSON.parse(JSON.stringify(draft))
    for (var i = 0; i < mismatched.length; i++)
      next.members[mismatched[i]] = Model.matchChannels(next, devices, mismatched[i])
    commit(next)
  }
  function channelLabel(info, index) {
    var n = I18n.formatNumber(index + 1)
    return info && info.name ? strings.t("group.channelNamed").arg(n).arg(info.name)
      : strings.t("group.channel").arg(n)
  }
  // One line per computer: which channel each member uses for it.
  function targetDetail(t) {
    var parts = []
    for (var i = 0; i < memberIds.length; i++) {
      var did = memberIds[i]
      var dev = deviceById(did)
      var channel = draft.members[did][t]
      var info = dev ? Model.deviceChannels(dev)[channel] : {}
      var text = strings.t("group.onChannel").arg(deviceName(did)).arg(I18n.formatNumber(channel + 1))
      if (info.paired === false) text += " " + strings.t("group.notPaired")
      parts.push(text)
    }
    return parts.join("  ·  ")
  }

  component Caption: Text {
    width: parent ? parent.width : implicitWidth
    textFormat: Text.PlainText
    color: root.dim
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  component Disclosure: Button {
    property bool open: false
    iconText: "󰅂"
    iconRotation: open ? 90 : 0
    leftAlign: true
    focusable: true
    horizontalPadding: Style.space(4)
    foreground: Color.foreground
    fontFamily: Style.font.family
    Behavior on iconRotation { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }
  }

  // ── Computers ──────────────────────────────────────────────────────────
  MxSection {
    title: strings.t("group.computers")
    hint: root.memberIds.length ? strings.t("group.computersHelp") : strings.t("group.empty")

    Repeater {
      model: root.memberIds.length ? root.targets : []
      Item {
        id: computer
        required property var modelData
        required property int index
        width: parent.width
        implicitHeight: Math.max(computerText.implicitHeight, action.height) + Style.space(8)
        Text {
          id: marker
          x: 0
          y: Style.space(4)
          text: computer.modelData.here ? "●" : "○"
          textFormat: Text.PlainText
          color: computer.modelData.here ? Color.accent : root.dim
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }
        Column {
          id: computerText
          x: marker.width + Style.space(10)
          y: Style.space(4)
          width: parent.width - x - action.width - Style.space(12)
          spacing: Style.space(2)
          Text {
            width: parent.width
            text: computer.modelData.name || strings.t("group.computer").arg(I18n.formatNumber(computer.modelData.target))
            textFormat: Text.PlainText
            color: computer.modelData.here ? Color.accent : Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
            elide: Text.ElideRight
          }
          Caption { text: root.targetDetail(computer.index) }
        }
        Item {
          id: action
          anchors.right: parent.right
          y: Style.space(4)
          width: Math.max(goButton.implicitWidth, hereText.implicitWidth)
          height: goButton.implicitHeight
          Text {
            id: hereText
            visible: computer.modelData.here
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: strings.t("group.here")
            textFormat: Text.PlainText
            color: Color.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
          Button {
            id: goButton
            visible: !computer.modelData.here
            anchors.fill: parent
            text: strings.t("group.switchTo")
            tooltipText: computer.modelData.available ? "" : strings.t("group.unavailable")
            bordered: true
            focusable: true
            enabled: computer.modelData.available && root.mx.installed
            opacity: enabled ? 1 : 0.4
            onClicked: root.mx.switchTogether(computer.modelData.target)
          }
        }
      }
    }
  }

  // ── Devices in the group ───────────────────────────────────────────────
  MxSection {
    title: strings.t("group.devices")
    hint: strings.t("group.devicesHelp")
    status: root.memberIds.length ? strings.t("group.count").arg(I18n.formatNumber(root.memberIds.length)) : ""

    Repeater {
      model: root.devices
      Column {
        id: member
        required property var modelData
        width: parent.width
        spacing: Style.space(10)
        readonly property string did: String(modelData.id || "")
        readonly property bool included: !!root.draft.members[did]
        readonly property bool reachable: modelData.readonly !== true && modelData.online !== false
        MxField {
          switchable: true
          label: String(member.modelData.name || "Logitech")
          help: member.included ? strings.t("group.memberOn")
            : member.reachable ? strings.t("group.memberOff") : strings.t("group.memberOffline")
          checked: member.included
          enabled: member.included || member.reachable
          onToggled: root.updateMember(member.did, -1, !member.included)
        }
        // Physical following belongs to a specific keyboard, so it sits under
        // that keyboard instead of depending on which device is selected.
        Item {
          visible: member.included && root.isKeyboard(member.modelData)
          width: parent.width
          implicitHeight: follow.implicitHeight
          Text {
            id: branch
            text: "└"
            textFormat: Text.PlainText
            color: Qt.alpha(Color.foreground, 0.3)
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }
          MxField {
            id: follow
            readonly property bool on: root.draft.follow && root.draft.keyboard === member.did
            x: Style.space(24)
            width: parent.width - x
            switchable: true
            label: strings.t("group.follow")
            help: !on ? strings.t("group.followOff")
              : root.mx.switchRuntime.listening ? strings.t("group.listening")
              : String(root.mx.switchRuntime.error || strings.t("group.starting"))
            checked: on
            onToggled: {
              var next = JSON.parse(JSON.stringify(root.draft))
              next.follow = !on
              next.keyboard = next.follow ? member.did : ""
              root.commit(next)
            }
          }
        }
      }
    }

    Caption {
      visible: root.devices.length === 0
      text: strings.t("group.noDevices")
    }

    // Names on the devices disagree with the saved mapping.
    Column {
      visible: root.mismatched.length > 0
      width: parent.width
      spacing: Style.space(6)
      Caption {
        text: "! " + strings.t("group.mismatch").arg(root.mismatched.map(root.deviceName).join(", "))
        color: Color.foreground
      }
      Button {
        text: strings.t("group.matchNames")
        bordered: true
        focusable: true
        onClicked: root.matchAll()
      }
    }

    Disclosure {
      id: customize
      visible: root.memberIds.length > 0
      text: strings.t("group.customize")
      onClicked: open = !open
    }

    Column {
      visible: customize.open && root.memberIds.length > 0
      width: parent.width
      spacing: Style.space(16)
      Caption { text: strings.t("group.customizeHelp") }
      Repeater {
        model: root.memberIds
        MxField {
          id: mapping
          required property string modelData
          readonly property var channels: Model.deviceChannels(root.deviceById(modelData))
          readonly property var options: [0, 1, 2].map(function(c) {
            return { value: String(c), label: root.channelLabel(mapping.channels[c], c) }
          })
          stacked: true
          label: root.deviceName(modelData)
          Row {
            id: cells
            width: parent.width
            spacing: Style.space(8)
            Repeater {
              model: root.targets
              Item {
                id: cell
                required property var modelData
                required property int index
                width: (cells.width - cells.spacing * 2) / 3
                implicitHeight: picker.implicitHeight
                height: implicitHeight
                Dropdown {
                  id: picker
                  width: parent.width
                  label: cell.modelData.name || strings.t("group.computer").arg(I18n.formatNumber(cell.modelData.target))
                  function saved() { return String((root.draft.members[mapping.modelData] || [0, 1, 2])[cell.index]) }
                  value: saved()
                  options: mapping.options
                  foreground: Color.foreground
                  fontFamily: Style.font.family
                  onChanged: function(next) {
                    root.updateMember(mapping.modelData, cell.index, Number(next))
                    // Dropdown assigns value on selection; rebind it to the config.
                    value = Qt.binding(saved)
                  }
                  onPopupOpenChanged: root.dropdownOpen = popupOpen
                  Component.onDestruction: if (popupOpen) root.dropdownOpen = false
                }
                WheelGuard { anchors.fill: parent }
              }
            }
          }
        }
      }
    }
  }
}
