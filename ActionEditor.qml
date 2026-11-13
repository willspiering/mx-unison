import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The buttons section of a device page: one row per control the device
// exposes, summarising what it does now. Clicking a row opens its editor
// inline (one at a time): which app the action is for, shortcut steps or
// directional gestures, and the control's hardware remap / Solaar rule
// handling. Payloads match the helper's action-save / action-delete ops.
Column {
  id: editor
  property var service: null
  property var device: null
  property var controls: []
  property var remapSetting: null
  property var divertSetting: null
  // True while one of this section's dropdown popups owns the keyboard.
  property bool dropdownOpen: false
  Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  readonly property string deviceId: device ? String(device.id) : ""
  readonly property color muted: Qt.alpha(Color.foreground, 0.55)
  readonly property var assignments: (service && service.actions || []).filter(function(r) { return device && r.device === deviceId })
  readonly property bool running: !!device && ((service && service.actionRuntime || {}).activeDevices || []).indexOf(deviceId) !== -1
  // Software-capable controls first, then hardware-only ones.
  readonly property var ordered: controls.filter(function(c) { return !!c.divert }).concat(controls.filter(function(c) { return !c.divert }))

  // ── Editor state for the open control ────────────────────────────────
  property string openKey: ""
  property string scope: ""          // "" = All apps
  property bool addingApp: false     // choosing an app for a new override
  property string mode: "shortcut"
  property string steps: ""
  property var directions: ({ up: "", down: "", left: "", right: "" })
  property bool recording: false
  property bool showHardware: false

  spacing: Style.space(2)
  onDeviceIdChanged: close()

  function controlFor(key) {
    for (var i = 0; i < controls.length; i++) if (controls[i].key === key) return controls[i]
    return null
  }
  function bindingFor(key, app) {
    for (var i = 0; i < assignments.length; i++) {
      var r = assignments[i]
      if (r.control === key && String(r.app || "") === String(app || "")) return r
    }
    return null
  }
  // Load the saved action for (control, app) into the editor, or blanks.
  function load(key, app) {
    var row = bindingFor(key, app)
    scope = app || ""
    addingApp = false
    recording = false
    mode = row ? row.mode : "shortcut"
    steps = row ? row.shortcut : ""
    directions = Object.assign({ up: "", down: "", left: "", right: "" }, row ? row.gestures : {})
  }
  function toggle(key) {
    if (openKey === key) { close(); return }
    openKey = key
    showHardware = false
    load(key, "")
  }
  function close() {
    openKey = ""
    recording = false
    addingApp = false
  }
  readonly property var openControl: controlFor(openKey)
  readonly property var openState: Model.controlState(openControl, assignments)
  readonly property var savedRow: bindingFor(openKey, scope)
  readonly property bool dirty: {
    var row = savedRow
    if (!row) return steps.trim() !== ""
    if (row.mode !== mode || String(row.shortcut) !== steps.trim()) return true
    if (mode !== "gesture") return false
    var g = row.gestures || {}
    return ["up", "down", "left", "right"].some(function(d) { return String(g[d] || "") !== String(directions[d] || "").trim() })
  }
  function save() {
    service.saveAction({ device: deviceId, control: openKey, app: scope.trim(), mode: mode, shortcut: steps, gestures: directions })
  }
  function remove() {
    var row = savedRow
    if (!row) return
    service.deleteAction(row)
    if (scope !== "") load(openKey, "")
  }
  function summary(control) {
    var st = Model.controlState(control, assignments)
    var parts = []
    if (st.binding) parts.push(st.binding.mode === "gesture" ? strings.t("actions.gestures") : Model.stepsSummary(st.binding.shortcut))
    if (st.overrides.length) parts.push(strings.t(st.overrides.length === 1 ? "actions.overrides1" : "actions.overrides").arg(I18n.formatNumber(st.overrides.length)))
    if (st.remapped) parts.push(strings.t("actions.remapped").arg(st.remapped))
    if (st.diverted && !st.binding) parts.push(strings.t("actions.rule").arg(st.diverted))
    return parts.length ? parts.join("  ·  ") : strings.t("actions.default")
  }

  // Shortcut capture while recording: the next key chord becomes the step.
  Keys.onPressed: function(event) {
    if (!recording) return
    event.accepted = true
    if (event.key === Qt.Key_Escape) { recording = false; return }
    if ([Qt.Key_Control, Qt.Key_Shift, Qt.Key_Alt, Qt.Key_Meta].indexOf(event.key) >= 0) return
    var special = ({})
    special[Qt.Key_Return] = "Return"; special[Qt.Key_Enter] = "Return"
    special[Qt.Key_Tab] = "Tab"; special[Qt.Key_Backspace] = "BackSpace"
    special[Qt.Key_Delete] = "Delete"; special[Qt.Key_Space] = "space"
    special[Qt.Key_Left] = "Left"; special[Qt.Key_Right] = "Right"
    special[Qt.Key_Up] = "Up"; special[Qt.Key_Down] = "Down"
    special[Qt.Key_Home] = "Home"; special[Qt.Key_End] = "End"
    special[Qt.Key_PageUp] = "Prior"; special[Qt.Key_PageDown] = "Next"
    var key = special[event.key] || ""
    if (!key && event.key >= Qt.Key_F1 && event.key <= Qt.Key_F12) key = "F" + (event.key - Qt.Key_F1 + 1)
    if (!key && ((event.key >= Qt.Key_A && event.key <= Qt.Key_Z) || (event.key >= Qt.Key_0 && event.key <= Qt.Key_9))) key = String.fromCharCode(event.key).toLowerCase()
    if (!key) return
    var mods = []
    if (event.modifiers & Qt.ControlModifier) mods.push("CTRL")
    if (event.modifiers & Qt.AltModifier) mods.push("ALT")
    if (event.modifiers & Qt.ShiftModifier) mods.push("SHIFT")
    if (event.modifiers & Qt.MetaModifier) mods.push("SUPER")
    var chord = mods.concat([key]).join("+")
    // Recording appends, so a sequence can be built one chord at a time.
    steps = steps.trim() === "" ? chord : steps.trim() + "\n" + chord
    recording = false
  }

  component Caption: Text {
    width: parent ? parent.width : implicitWidth
    textFormat: Text.PlainText
    color: editor.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  // A dropdown that stays bound to the device value after a selection.
  component HardwareChoice: MxField {
    id: hw
    property var row: null
    property var setting: null
    visible: !!row
    Item {
      width: parent.width
      height: hwDrop.implicitHeight
      Dropdown {
        id: hwDrop
        function saved() {
          var v = hw.row && hw.row.value
          return v && typeof v === "object" && v.id !== undefined ? String(v.id) : (v === undefined || v === null ? "" : String(v))
        }
        width: parent.width
        showLabel: false
        value: saved()
        options: (hw.row && hw.row.choices || []).map(function(c) { return { value: String(c.id), label: String(c.name) } })
        onChanged: function(next) {
          if (hw.setting && hw.row) editor.service.setSetting(hw.setting.name, next, hw.row.key)
          value = Qt.binding(saved)
        }
        onPopupOpenChanged: editor.dropdownOpen = popupOpen
        Component.onDestruction: if (popupOpen) editor.dropdownOpen = false
      }
      WheelGuard { anchors.fill: parent }
    }
  }

  Text {
    visible: !!((service && service.actionRuntime || {}).error)
    width: parent.width
    bottomPadding: Style.space(8)
    text: "! " + ((service && service.actionRuntime || {}).error || "")
    textFormat: Text.PlainText
    color: Color.urgent
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  Caption {
    visible: editor.controls.length === 0
    text: strings.t("actions.none")
  }

  Repeater {
    model: editor.ordered
    Column {
      id: entry
      required property var modelData
      required property int index
      readonly property bool isOpen: editor.openKey === modelData.key
      readonly property bool hardwareOnly: !modelData.divert
      width: editor.width
      spacing: 0

      // Divider before the hardware-only group.
      Text {
        visible: entry.hardwareOnly && (entry.index === 0 || !!editor.ordered[entry.index - 1].divert)
        width: parent.width
        topPadding: Style.space(14)
        bottomPadding: Style.space(4)
        text: strings.t("actions.hardwareGroup")
        textFormat: Text.PlainText
        color: editor.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.letterSpacing: 1
      }

      // ── The row ───────────────────────────────────────────────────
      Item {
        id: rowItem
        width: parent.width
        implicitHeight: Math.max(Style.spacing.controlHeight, rowLabel.implicitHeight) + Style.space(12)
        activeFocusOnTab: true
        Keys.onReturnPressed: editor.toggle(entry.modelData.key)
        Keys.onEnterPressed: editor.toggle(entry.modelData.key)
        Keys.onSpacePressed: editor.toggle(entry.modelData.key)
        Rectangle {
          anchors.fill: parent
          anchors.leftMargin: -Style.space(8)
          anchors.rightMargin: -Style.space(8)
          radius: Style.cornerRadius
          color: entry.isOpen ? Qt.alpha(Color.accent, 0.08)
            : (rowItem.activeFocus || rowMouse.containsMouse) ? Style.hoverFillFor(Color.foreground, Color.accent) : "transparent"
          Behavior on color { ColorAnimation { duration: Style.duration(100) } }
        }
        Text {
          id: chevron
          anchors.verticalCenter: parent.verticalCenter
          text: "󰅂"
          rotation: entry.isOpen ? 90 : 0
          color: entry.isOpen ? Color.accent : editor.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          Behavior on rotation { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }
        }
        Row {
          id: rowLabel
          x: chevron.width + Style.space(8)
          width: Math.min(Style.space(230), Math.round(parent.width * 0.38)) - x
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(6)
          Text {
            id: rowName
            width: Math.min(implicitWidth, parent.width)
            text: String(entry.modelData.label)
            textFormat: Text.PlainText
            color: entry.isOpen ? Color.accent : Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }
          Text {
            width: Math.max(0, parent.width - rowName.width - parent.spacing)
            clip: true
            text: "·····································································································"
            textFormat: Text.PlainText
            color: Qt.alpha(Color.foreground, 0.18)
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }
        }
        Text {
          x: rowLabel.x + rowLabel.width + Style.space(12)
          width: parent.width - x
          anchors.verticalCenter: parent.verticalCenter
          text: editor.summary(entry.modelData)
          textFormat: Text.PlainText
          color: text === strings.t("actions.default") ? editor.muted : Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }
        MouseArea {
          id: rowMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: { rowItem.forceActiveFocus(); editor.toggle(entry.modelData.key) }
        }
      }

      // ── Its editor ────────────────────────────────────────────────
      Item {
        visible: entry.isOpen
        width: parent.width
        implicitHeight: visible ? body.implicitHeight + Style.space(28) : 0
        // Rail tying the editor to its row.
        Rectangle {
          x: Style.space(4)
          y: Style.space(8)
          width: 1
          height: parent.height - Style.space(16)
          color: Qt.alpha(Color.accent, 0.35)
        }
        Column {
          id: body
          x: Style.space(22)
          y: Style.space(14)
          width: parent.width - x
          spacing: Style.space(14)

          // Which app the action applies to.
          MxField {
            visible: !entry.hardwareOnly
            label: strings.t("actions.for")
            help: editor.openState.binding ? "" : strings.t("actions.forHelp")
            Flow {
              width: parent.width
              spacing: Style.space(6)
              ButtonGroup {
                options: [{ value: "", label: strings.t("actions.allApps") }].concat(editor.openState.overrides.map(function(a) { return { value: a, label: a } }))
                  .concat(editor.scope !== "" && editor.openState.overrides.indexOf(editor.scope) < 0 ? [{ value: editor.scope, label: editor.scope + " *" }] : [])
                value: editor.addingApp ? "\u0000" : editor.scope
                onChanged: function(value) { editor.load(editor.openKey, value) }
              }
              Button {
                visible: !!editor.openState.binding && !editor.addingApp
                text: strings.t("actions.addApp")
                iconText: "󰐕"
                bordered: true
                focusable: true
                onClicked: editor.addingApp = true
              }
            }
          }

          // Picking the app for a new override.
          MxField {
            visible: !entry.hardwareOnly && editor.addingApp
            label: strings.t("actions.app")
            help: strings.t("actions.appHelp")
            Row {
              width: parent.width
              spacing: Style.space(8)
              Item {
                width: (parent.width - parent.spacing) / 2
                height: appDrop.implicitHeight
                Dropdown {
                  id: appDrop
                  width: parent.width
                  showLabel: false
                  value: ""
                  options: [{ value: "", label: strings.t("actions.runningApps") }].concat((editor.service && editor.service.applications || [])
                    .filter(function(a) { return editor.openState.overrides.indexOf(a) < 0 })
                    .map(function(a) { return { value: a, label: a } }))
                  onChanged: function(next) {
                    value = ""
                    if (next !== "") { editor.load(editor.openKey, ""); editor.scope = next; editor.steps = ""; editor.mode = "shortcut" }
                  }
                  onPopupOpenChanged: editor.dropdownOpen = popupOpen
                  Component.onDestruction: if (popupOpen) editor.dropdownOpen = false
                }
                WheelGuard { anchors.fill: parent }
              }
              TextField {
                id: appClass
                width: (parent.width - parent.spacing) / 2
                placeholderText: strings.t("actions.appClass")
                Accessible.name: strings.t("actions.appClass")
                onAccepted: {
                  var name = text.trim()
                  if (name === "") return
                  editor.load(editor.openKey, "")
                  editor.scope = name
                  editor.steps = ""
                  editor.mode = "shortcut"
                  text = ""
                }
              }
            }
          }

          MxField {
            visible: !entry.hardwareOnly && editor.openState.gestures
            label: strings.t("actions.does")
            ButtonGroup {
              options: [{ value: "shortcut", label: strings.t("actions.modeShortcut") }, { value: "gesture", label: strings.t("actions.modeGesture") }]
              value: editor.mode
              onChanged: function(value) { editor.mode = value }
            }
          }

          MxField {
            visible: !entry.hardwareOnly
            label: editor.mode === "gesture" ? strings.t("actions.click") : strings.t("actions.shortcut")
            help: strings.t("actions.stepsHelp")
            stacked: false
            Column {
              width: parent.width
              spacing: Style.space(8)
              TextArea {
                id: stepsArea
                width: parent.width
                implicitHeight: Math.max(Style.space(38), contentHeight + topPadding + bottomPadding)
                text: editor.steps
                onTextChanged: if (activeFocus) editor.steps = text
                placeholderText: strings.t("actions.stepsPlaceholder")
                wrapMode: TextEdit.Wrap
                color: Color.foreground
                placeholderTextColor: editor.muted
                selectionColor: Qt.alpha(Color.accent, 0.35)
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                padding: Style.space(10)
                background: Rectangle {
                  color: Qt.alpha(Color.foreground, 0.035)
                  border.color: stepsArea.activeFocus ? Color.accent : Qt.alpha(Color.foreground, 0.18)
                  radius: Style.cornerRadius
                }
                Accessible.name: strings.t("actions.shortcut")
              }
              Flow {
                width: parent.width
                spacing: Style.space(6)
                Button {
                  text: editor.recording ? strings.t("actions.recording") : strings.t("actions.record")
                  iconText: "󰑊"
                  bordered: true
                  focusable: true
                  selected: editor.recording
                  onClicked: { editor.recording = !editor.recording; if (editor.recording) editor.forceActiveFocus() }
                }
                Repeater {
                  model: [
                    { label: "actions.presetCopy", value: "CTRL+c" }, { label: "actions.presetPaste", value: "CTRL+v" },
                    { label: "actions.presetUndo", value: "CTRL+z" }, { label: "actions.presetBack", value: "ALT+Left" },
                    { label: "actions.presetTab", value: "CTRL+Tab" }
                  ]
                  Button {
                    required property var modelData
                    text: strings.t(modelData.label)
                    tooltipText: modelData.value
                    focusable: true
                    foreground: editor.muted
                    onClicked: editor.steps = modelData.value
                  }
                }
              }
            }
          }

          // Directional gestures as a small cross: up / left · right / down.
          MxField {
            visible: !entry.hardwareOnly && editor.mode === "gesture"
            label: strings.t("actions.gestures")
            help: strings.t("actions.gestureHelp")
            Grid {
              id: pad
              width: parent.width
              columns: 2
              columnSpacing: Style.space(10)
              rowSpacing: Style.space(8)
              Repeater {
                model: [{ d: "up", g: "↑" }, { d: "down", g: "↓" }, { d: "left", g: "←" }, { d: "right", g: "→" }]
                Row {
                  required property var modelData
                  width: (pad.width - pad.columnSpacing) / 2
                  spacing: Style.space(8)
                  Text {
                    id: arrow
                    width: Style.space(16)
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.g
                    textFormat: Text.PlainText
                    color: Color.accent
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                  }
                  TextField {
                    width: parent.width - arrow.width - parent.spacing
                    text: editor.directions[modelData.d] || ""
                    placeholderText: strings.t("actions.noAction")
                    Accessible.name: strings.t("actions.gestureDir").arg(modelData.d)
                    onTextEdited: {
                      var next = Object.assign({}, editor.directions)
                      next[modelData.d] = text
                      editor.directions = next
                    }
                  }
                }
              }
            }
          }

          Row {
            visible: !entry.hardwareOnly
            spacing: Style.space(8)
            Button {
              text: strings.t("actions.save")
              bordered: true
              focusable: true
              enabled: editor.dirty && editor.steps.trim() !== "" && !!editor.service && editor.service.hidppReady
              opacity: enabled ? 1 : 0.4
              onClicked: editor.save()
            }
            Button {
              visible: !!editor.savedRow
              text: editor.scope === "" ? strings.t("actions.remove") : strings.t("actions.removeOverride")
              tooltipText: editor.scope === "" && editor.openState.overrides.length ? strings.t("actions.removeAllHelp") : ""
              bordered: true
              focusable: true
              onClicked: editor.remove()
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: editor.dirty ? strings.t("actions.unsaved") : editor.running ? "● " + strings.t("actions.running") : ""
              textFormat: Text.PlainText
              color: editor.dirty ? Color.foreground : Color.accent
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }

          // Hardware remap and Solaar rule handling for this control.
          Button {
            visible: !entry.hardwareOnly && !!(entry.modelData.remap || entry.modelData.divert)
            text: strings.t("actions.hardware")
            iconText: "󰅂"
            iconRotation: editor.showHardware ? 90 : 0
            leftAlign: true
            focusable: true
            horizontalPadding: Style.space(4)
            foreground: editor.muted
            onClicked: editor.showHardware = !editor.showHardware
            Behavior on iconRotation { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }
          }
          Column {
            visible: entry.hardwareOnly || editor.showHardware
            width: parent.width
            spacing: Style.space(12)
            Caption { text: strings.t("actions.hardwareHelp") }
            HardwareChoice {
              label: strings.t("actions.remap")
              row: entry.modelData.remap
              setting: editor.remapSetting
            }
            HardwareChoice {
              label: strings.t("actions.ruleHandling")
              help: strings.t("actions.ruleHelp")
              row: entry.modelData.divert
              setting: editor.divertSetting
            }
          }
        }
      }
    }
  }
}
