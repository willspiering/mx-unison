import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// One device's own Easy-Switch channels, for its device page: jump this
// device alone to another channel, and rename the channels it stores.
// Moving the whole desk lives on the Desk page (SwitchGroup.qml).
Column {
  id: root
  required property var mx
  property var device: null
  signal openDesk()
  spacing: Style.space(12)
  Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  readonly property var setting: Model.settingByNames(device, ["change-host", "change_host"])
  readonly property var hosts: device && device.hosts ? device.hosts : []
  readonly property var channels: Model.deviceChannels(device)
  readonly property bool grouped: !!(device && mx.switchConfig && mx.switchConfig.members && mx.switchConfig.members[String(device.id)])
  readonly property bool available: !!setting || hosts.length > 0

  function channelName(c) {
    var info = channels[c] || {}
    return info.name ? info.name : strings.t("group.channel").arg(I18n.formatNumber(c + 1))
  }

  Text {
    visible: !root.available
    width: parent.width
    text: strings.t("device.none")
    textFormat: Text.PlainText
    color: Qt.alpha(Color.foreground, 0.55)
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  MxField {
    visible: !!root.setting
    label: strings.t("device.channel")
    help: root.grouped ? strings.t("device.groupedHelp") : strings.t("device.help")
    ButtonGroup {
      width: parent.width
      options: [0, 1, 2].map(function(c) {
        var info = root.channels[c] || {}
        return {
          value: String(c),
          label: I18n.formatNumber(c + 1) + " " + root.channelName(c),
          tooltip: info.paired === false ? strings.t("device.notPaired") : ""
        }
      })
      value: root.setting ? Model.choiceId(root.setting) : ""
      foreground: Color.foreground
      accent: Color.accent
      fontFamily: Style.font.family
      onChanged: function(value) { if (root.setting) root.mx.setSetting(root.setting.name, value) }
    }
  }

  Button {
    visible: root.grouped
    text: strings.t("device.openDesk")
    iconText: "󰍹"
    bordered: true
    focusable: true
    onClicked: root.openDesk()
  }

  Button {
    id: rename
    property bool open: false
    visible: root.hosts.length > 0
    text: strings.t("device.rename")
    iconText: "󰅂"
    iconRotation: open ? 90 : 0
    leftAlign: true
    focusable: true
    horizontalPadding: Style.space(4)
    onClicked: open = !open
    Behavior on iconRotation { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }
  }

  Column {
    visible: rename.open && root.hosts.length > 0
    width: parent.width
    spacing: Style.space(10)
    Text {
      width: parent.width
      text: strings.t("device.renameHelp")
      textFormat: Text.PlainText
      color: Qt.alpha(Color.foreground, 0.55)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }
    Repeater {
      model: root.hosts
      MxField {
        id: hostRow
        required property var modelData
        readonly property int channel: Number(modelData.index)
        function submit() {
          root.mx.renameHost(hostRow.channel, hostNameField.text)
          hostNameField.text = ""
        }
        label: strings.t("group.channel").arg(I18n.formatNumber(channel + 1)) + (modelData.current ? " ●" : "")
        Row {
          width: parent.width
          spacing: Style.space(8)
          TextField {
            id: hostNameField
            width: parent.width - hostRenameBtn.implicitWidth - parent.spacing
            // QQC placeholders are not plain-text sinks; escape the device-supplied name.
            placeholderText: Model.hidDisplayName(hostRow.modelData, strings.t("group.channel").arg(I18n.formatNumber(hostRow.channel + 1)))
            onAccepted: hostRow.submit()
          }
          Button {
            id: hostRenameBtn
            text: strings.t("device.renameAction")
            bordered: true
            focusable: true
            enabled: hostNameField.text.trim() !== ""
            opacity: enabled ? 1 : 0.4
            onClicked: hostRow.submit()
          }
        }
      }
    }
  }
}
