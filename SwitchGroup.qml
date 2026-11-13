import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

Column {
  id: root
  required property var mx
  spacing: Style.space(12)
  Translations { id: strings; directory: Qt.resolvedUrl("i18n") }
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
      if (value) next.members[did] = [0, 1, 2]
      else {
        delete next.members[did]
        if (next.keyboard === did) { next.keyboard = ""; next.follow = false }
      }
    } else {
      // Swapping preserves a one-to-one target/channel mapping.
      var old = next.members[did][channelIndex]
      var other = next.members[did].indexOf(value)
      next.members[did][other] = old
      next.members[did][channelIndex] = value
    }
    commit(next)
  }
  Text {
    text: strings.t("group.title")
    textFormat: Text.PlainText
    color: Color.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.heading
    font.bold: true
  }
  Text {
    width: parent.width
    text: strings.t("group.description")
    textFormat: Text.PlainText
    wrapMode: Text.WordWrap
    color: Qt.alpha(Color.foreground, 0.68)
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }
  Repeater {
    model: root.mx.displayDevices || []
    Column {
      id: member
      required property var modelData
      width: root.width
      spacing: Style.space(8)
      readonly property string did: String(modelData.id || "")
      readonly property bool included: !!root.draft.members[did]
      CheckBox {
        width: parent.width
        text: String(member.modelData.name || "Logitech").replace(/[<>]/g, "")
        checked: member.included
        enabled: member.modelData.readonly !== true && member.modelData.online !== false
        onClicked: root.updateMember(member.did, -1, checked)
      }
      Row {
        visible: member.included
        spacing: Style.space(8)
        Repeater {
          model: 3
          Column {
            required property int index
            spacing: Style.space(4)
            Text {
              text: strings.t("group.target").arg(I18n.formatNumber(index + 1))
              textFormat: Text.PlainText
              color: Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
            ComboBox {
              model: [1, 2, 3]
              wheelEnabled: false
              currentIndex: member.included ? root.draft.members[member.did][index] : 0
              onActivated: root.updateMember(member.did, index, currentIndex)
            }
          }
        }
      }
    }
  }
  Row {
    spacing: Style.space(8)
    Repeater {
      model: 3
      Button {
        required property int index
        text: strings.t("group.switch").arg(I18n.formatNumber(index + 1))
        bordered: true
        focusable: true
        enabled: Object.keys(root.mx.switchConfig.members || {}).length > 0 && root.mx.installed
        onClicked: root.mx.switchTogether(index + 1)
      }
    }
  }
  CheckBox {
    width: parent.width
    text: strings.t("group.follow")
    checked: root.draft.follow
    enabled: !!root.mx.selectedDevice && root.mx.selectedDevice.kind === "keyboard" && !!root.draft.members[String(root.mx.selectedDevice.id)]
    onClicked: {
      var next = JSON.parse(JSON.stringify(root.draft))
      next.follow = checked
      next.keyboard = checked ? String(root.mx.selectedDevice.id) : ""
      root.commit(next)
    }
  }
  Text {
    width: parent.width
    text: root.mx.switchRuntime.listening ? strings.t("group.listening") : String(root.mx.switchRuntime.error || strings.t("group.followHelp"))
    textFormat: Text.PlainText
    wrapMode: Text.WordWrap
    color: Qt.alpha(Color.foreground, 0.68)
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }
}
