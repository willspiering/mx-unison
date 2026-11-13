import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The Easy Switch page: computers to switch the group to, which devices move
// together (channels auto-matched by stored host name, manual mapping behind
// a disclosure), and the selected device's own channels.
Column {
  id: root
  required property var mx
  // The device selected in the settings window, for the single-device card.
  property var device: null
  property bool canWrite: false
  // True while one of this page's dropdown popups owns the keyboard.
  property bool dropdownOpen: false
  spacing: Style.space(16)
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

  component Card: Rectangle {
    id: card
    property string title: ""
    property string description: ""
    default property alias contents: cardContent.data
    width: root.width
    implicitHeight: cardLayout.implicitHeight + Style.space(36)
    color: Qt.alpha(Color.foreground, 0.025)
    border.color: Qt.alpha(Color.foreground, 0.10)
    border.width: 1
    radius: Style.cornerRadius
    data: Column {
      id: cardLayout
      x: Style.space(18)
      y: Style.space(18)
      width: parent.width - Style.space(36)
      spacing: Style.space(14)
      Column {
        width: parent.width
        spacing: Style.space(4)
        visible: card.title !== "" || card.description !== ""
        Text {
          width: parent.width
          visible: card.title !== ""
          text: card.title
          textFormat: Text.PlainText
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
          wrapMode: Text.WordWrap
        }
        Text {
          width: parent.width
          visible: card.description !== ""
          text: card.description
          textFormat: Text.PlainText
          color: root.dim
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }
      }
      Column {
        id: cardContent
        width: parent.width
        spacing: Style.space(12)
      }
    }
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
    text: ""
    iconText: "󰅂"
    iconRotation: open ? 90 : 0
    leftAlign: true
    focusable: true
    foreground: Color.foreground
    fontFamily: Style.font.family
    Behavior on iconRotation { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }
  }

  // ── Computers ──────────────────────────────────────────────────────────
  Card {
    title: strings.t("group.computers")
    description: root.memberIds.length ? strings.t("group.computersHelp") : strings.t("group.empty")

    Repeater {
      model: root.memberIds.length ? root.targets : []
      BorderSurface {
        id: computer
        required property var modelData
        required property int index
        width: parent.width
        implicitHeight: computerRow.implicitHeight + Style.space(20)
        radius: Style.cornerRadius
        color: modelData.here ? Qt.alpha(Color.accent, 0.10) : "transparent"
        borderSpec: Border.controlSpec(modelData.here ? "focus" : "normal", Color.foreground, Color.accent)
        Row {
          id: computerRow
          x: Style.space(12)
          width: parent.width - Style.space(24)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(12)
          Column {
            width: parent.width - switchButton.width - parent.spacing
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)
            Text {
              width: parent.width
              text: computer.modelData.name || strings.t("group.computer").arg(I18n.formatNumber(computer.modelData.target))
              textFormat: Text.PlainText
              color: Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
              elide: Text.ElideRight
            }
            Caption {
              text: root.targetDetail(computer.index)
            }
          }
          Item {
            id: switchButton
            width: Math.max(goButton.implicitWidth, hereText.implicitWidth)
            height: goButton.implicitHeight
            anchors.verticalCenter: parent.verticalCenter
            Text {
              id: hereText
              visible: computer.modelData.here
              anchors.centerIn: parent
              text: strings.t("group.here")
              textFormat: Text.PlainText
              color: Color.accent
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              font.bold: true
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
              opacity: enabled ? 1 : 0.45
              onClicked: root.mx.switchTogether(computer.modelData.target)
            }
          }
        }
      }
    }
  }

  // ── Devices in the group ───────────────────────────────────────────────
  Card {
    title: strings.t("group.devices")
    description: strings.t("group.devicesHelp")

    Repeater {
      model: root.devices
      Column {
        id: member
        required property var modelData
        width: parent.width
        spacing: Style.space(8)
        readonly property string did: String(modelData.id || "")
        readonly property bool included: !!root.draft.members[did]
        readonly property bool reachable: modelData.readonly !== true && modelData.online !== false
        Toggle {
          width: parent.width
          label: String(member.modelData.name || "Logitech")
          description: member.included ? strings.t("group.memberOn")
            : member.reachable ? strings.t("group.memberOff") : strings.t("group.memberOffline")
          checked: member.included
          enabled: member.included || member.reachable
          opacity: enabled ? 1 : 0.55
          foreground: Color.foreground
          accent: Color.accent
          fontFamily: Style.font.family
          titleSize: Style.font.body
          onClicked: root.updateMember(member.did, -1, !member.included)
        }
        // Physical following belongs to a specific keyboard, so it sits under
        // that keyboard instead of depending on which device is selected.
        Toggle {
          readonly property bool on: root.draft.follow && root.draft.keyboard === member.did
          visible: member.included && root.isKeyboard(member.modelData)
          x: Style.space(24)
          width: parent.width - x
          label: strings.t("group.follow")
          description: !on ? strings.t("group.followOff")
            : root.mx.switchRuntime.listening ? strings.t("group.listening")
            : String(root.mx.switchRuntime.error || strings.t("group.starting"))
          checked: on
          foreground: Color.foreground
          accent: Color.accent
          fontFamily: Style.font.family
          titleSize: Style.font.bodySmall
          onClicked: {
            var next = JSON.parse(JSON.stringify(root.draft))
            next.follow = !on
            next.keyboard = next.follow ? member.did : ""
            root.commit(next)
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
        text: strings.t("group.mismatch").arg(root.mismatched.map(root.deviceName).join(", "))
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
      spacing: Style.space(14)
      Caption { text: strings.t("group.customizeHelp") }
      Repeater {
        model: root.memberIds
        Column {
          id: mapping
          required property string modelData
          readonly property var channels: Model.deviceChannels(root.deviceById(modelData))
          readonly property var options: [0, 1, 2].map(function(c) {
            return { value: String(c), label: root.channelLabel(mapping.channels[c], c) }
          })
          width: parent.width
          spacing: Style.space(6)
          Text {
            width: parent.width
            text: root.deviceName(mapping.modelData)
            textFormat: Text.PlainText
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            font.bold: true
            elide: Text.ElideRight
          }
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

  // ── The selected device on its own ─────────────────────────────────────
  Card {
    id: single
    readonly property var setting: Model.settingByNames(root.device, ["change-host", "change_host"])
    readonly property var hosts: root.device && root.device.hosts ? root.device.hosts : []
    readonly property var channels: Model.deviceChannels(root.device)
    visible: !!root.device && root.canWrite
    title: strings.t("device.title").arg(String(root.device && root.device.name || "Logitech"))
    description: single.setting || single.hosts.length ? strings.t("device.help") : strings.t("device.none")

    ButtonGroup {
      visible: !!single.setting
      width: parent.width
      options: [0, 1, 2].map(function(c) {
        var info = single.channels[c] || {}
        return {
          value: String(c),
          label: info.name ? info.name : strings.t("group.channel").arg(I18n.formatNumber(c + 1)),
          tooltip: info.paired === false ? strings.t("device.notPaired") : ""
        }
      })
      value: single.setting ? Model.choiceId(single.setting) : ""
      foreground: Color.foreground
      accent: Color.accent
      fontFamily: Style.font.family
      onChanged: function(value) { if (single.setting) root.mx.setSetting(single.setting.name, value) }
    }

    Disclosure {
      id: rename
      visible: single.hosts.length > 0
      text: strings.t("device.rename")
      onClicked: open = !open
    }

    Column {
      visible: rename.open && single.hosts.length > 0
      width: parent.width
      spacing: Style.space(8)
      Caption { text: strings.t("device.renameHelp") }
      Repeater {
        model: single.hosts
        Row {
          id: hostRow
          required property var modelData
          width: parent.width
          spacing: Style.space(8)
          function submit() {
            root.mx.renameHost(hostRow.modelData.index, hostNameField.text)
            hostNameField.text = ""
          }
          Text {
            id: hostNum
            text: I18n.formatNumber(Number(hostRow.modelData.index) + 1)
            textFormat: Text.PlainText
            color: hostRow.modelData.current ? Color.accent : root.dim
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
            width: Style.space(20)
            anchors.verticalCenter: parent.verticalCenter
          }
          TextField {
            id: hostNameField
            width: parent.width - hostNum.width - hostRenameBtn.implicitWidth - parent.spacing * 2
            // QQC placeholders are not plain-text sinks; escape the device-supplied name.
            placeholderText: Model.hidDisplayName(hostRow.modelData, strings.t("group.channel").arg(I18n.formatNumber(Number(hostRow.modelData.index) + 1)))
            onAccepted: hostRow.submit()
          }
          Button {
            id: hostRenameBtn
            text: strings.t("device.renameAction")
            bordered: true
            focusable: true
            enabled: hostNameField.text.trim() !== ""
            opacity: enabled ? 1 : 0.45
            onClicked: hostRow.submit()
          }
        }
      }
    }
  }
}
