import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: root
  Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  property var shell: null
  // Injected by shells with plugin-service support: the same shared Service
  // instance the bar widgets use, so selection and snapshots stay in sync.
  property var service: null
  property bool closingFromHost: false
  property bool dropdownOpen: false
  // "desk": devices overview and switching the whole group.
  // "device": everything for the selected device, as one page of sections.
  property string page: "desk"
  property bool showMore: false
  // Section to scroll to once the device page has laid out.
  property string pendingJump: ""
  readonly property bool wideLayout: window.width >= Style.space(820)
  // Sections of the device page, in order, limited to what the device has.
  readonly property var deviceSections: {
    var out = []
    if (!device) return out
    if (!canWrite) return [{ key: "status", label: strings.t("section.status") }]
    if (dpiSetting || Model.isMouse(device)) out.push({ key: "pointer", label: strings.t("section.pointer") })
    if (smartSetting || smartThresholdSetting || invertSetting || hiresSetting || Model.isMouse(device)) out.push({ key: "scroll", label: strings.t("section.scroll") })
    if (thumbInvertSetting || thumbModeSetting) out.push({ key: "thumb", label: strings.t("section.thumb") })
    if (fnSetting || backlightSetting || platformSetting || lockSetting) out.push({ key: "keyboard", label: strings.t("section.keys") })
    out.push({ key: "buttons", label: strings.t(Model.isKeyboard(device) ? "section.actions" : "section.buttons") })
    out.push({ key: "channels", label: strings.t("section.channels") })
    out.push({ key: "profiles", label: strings.t("section.profiles") })
    if (extraSettings.length) out.push({ key: "more", label: strings.t("section.more") })
    return out
  }
  onPageChanged: flick.contentY = 0

  function showDesk() {
    page = "desk"
  }
  function showDevice(id) {
    if (id !== undefined && id !== null && mx) mx.selectDevice(String(id))
    if (page !== "device") page = "device"
    else flick.contentY = 0
  }
  function sectionItem(key) {
    var kids = column.children
    for (var i = 0; i < kids.length; i++)
      if (kids[i].anchorKey === key && kids[i].visible) return kids[i]
    return null
  }
  function jumpTo(key) {
    if (key === "more") showMore = true
    var item = sectionItem(key)
    if (!item) return
    var target = Math.max(0, Math.min(item.y - Style.space(20), flick.contentHeight - flick.height))
    jumpAnim.stop()
    if (Style.reduceMotion) { flick.contentY = target; return }
    jumpAnim.to = target
    jumpAnim.start()
  }
  // The section at the top of the viewport, for the sidebar highlight.
  readonly property string activeSection: {
    var y = flick.contentY + Style.space(48)
    var current = deviceSections.length ? deviceSections[0].key : ""
    if (flick.contentHeight - flick.height - flick.contentY < 2 && deviceSections.length) {
      // At the bottom: the last visible section is the one being read.
      for (var j = deviceSections.length - 1; j >= 0; j--)
        if (sectionItem(deviceSections[j].key)) return deviceSections[j].key
    }
    for (var i = 0; i < deviceSections.length; i++) {
      var item = sectionItem(deviceSections[i].key)
      if (item && item.y <= y) current = deviceSections[i].key
    }
    return current
  }

  function resolveService() {
    if (service || !shell) return
    if (typeof shell.ensureService === "function")
      service = shell.ensureService("local.mx-unison") || null
    if (!service && typeof shell.serviceFor === "function")
      service = shell.serviceFor("local.mx-unison")
  }

  function open(payloadJson) {
    closingFromHost = false
    resolveService()
    window.visible = true
    if (mx) {
      mx.ensureDaemon()
      mx.refresh()
      if (typeof mx.refreshApplications === "function") mx.refreshApplications()
      if (payloadJson) {
        try {
          var parsed = JSON.parse(String(payloadJson))
          // Legacy section keys from older callers map onto the new pages.
          var legacy = { device: "pointer", buttons: "buttons", profiles: "profiles", advanced: "more" }
          if (parsed && parsed.device) { mx.selectDevice(parsed.device); page = "device" }
          if (parsed && parsed.section === "hosts") page = "desk"
          else if (parsed && parsed.section) {
            page = "device"
            pendingJump = legacy[parsed.section] || String(parsed.section)
            // Already laid out (window reopened on the same page): jump now.
            Qt.callLater(function() {
              if (root.pendingJump !== "" && root.sectionItem(root.pendingJump)) {
                var key = root.pendingJump
                root.pendingJump = ""
                root.jumpTo(key)
              }
            })
          }
        } catch (e) { /* ignore */ }
      }
    }
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function close() {
    closingFromHost = true
    window.visible = false
    closingFromHost = false
  }

  function requestClose() {
    if (shell && typeof shell.hide === "function") shell.hide("local.mx-unison")
    else window.visible = false
  }

  readonly property color foreground: Color.foreground
  readonly property color background: Color.background
  readonly property color accent: Color.accent
  readonly property color urgent: Color.urgent
  readonly property color dim: Qt.alpha(foreground, 0.68)
  readonly property string fontFamily: Style.font.family
  readonly property var fakeBar: QtObject {
    readonly property color foreground: root.foreground
    readonly property color background: root.background
    readonly property color urgent: root.urgent
    readonly property string fontFamily: root.fontFamily
    readonly property string position: "top"
    readonly property bool vertical: false
    readonly property int barSize: 26
  }
  property var bar: fakeBar

  // Fallback for shells without plugin services. Stays passive: it reads
  // status.json and starts the helper when the window actually opens.
  Service {
    id: localMx
    passive: true
  }

  readonly property var mx: root.service || localMx

  readonly property var device: mx.selectedDevice
  readonly property bool canWrite: mx.hidppReady
  readonly property var dpiSetting: Model.settingByNames(device, ["dpi", "dpi-extended", "dpi_extended"])
  readonly property var smartSetting: Model.settingByNames(device, ["scroll-ratchet", "smartshift"])
  readonly property var smartThresholdSetting: Model.settingByNames(device, ["smart-shift", "smartshift"])
  readonly property var invertSetting: Model.settingByNames(device, ["hires-smooth-invert", "scroll-invert"])
  readonly property var hiresSetting: Model.settingByNames(device, ["hires-smooth-resolution", "hires-scroll-mode"])
  readonly property var thumbInvertSetting: Model.settingByNames(device, ["thumb-scroll-invert"])
  readonly property var thumbModeSetting: Model.settingByNames(device, ["thumb-scroll-mode"])
  readonly property var hostSetting: Model.settingByNames(device, ["change-host", "change_host"])
  readonly property var remapSetting: Model.settingByNames(device, ["reprogrammable-keys"])
  readonly property var divertSetting: Model.settingByNames(device, ["divert-keys"])
  readonly property var fnSetting: Model.settingByNames(device, ["fn-swap", "fn_swap"])
  readonly property var backlightSetting: Model.settingByNames(device, ["backlight", "backlight_level", "backlight-level"])
  readonly property var platformSetting: Model.settingByNames(device, ["multiplatform"])
  readonly property var lockSetting: Model.settingByNames(device, ["disable-keyboard-keys"])
  readonly property var extraSettings: Model.remainingSettings(device, usedSettingNames())
  readonly property var assignmentControls: Model.assignmentControls(remapSetting, divertSetting)
  readonly property var smartState: Model.smartShiftState(smartSetting)
  readonly property var deviceProfiles: {
    var list = mx.profiles || []
    var kind = device && device.kind ? String(device.kind) : ""
    var out = []
    for (var i = 0; i < list.length; i++) {
      var row = list[i]
      if (!row) continue
      if (kind && row.kind && String(row.kind) !== kind) continue
      out.push(row)
    }
    return out
  }

  function usedSettingNames() {
    var names = []
    function add(setting) { if (setting && setting.name) names.push(setting.name) }
    add(dpiSetting)
    add(smartSetting)
    // smartshift can be a range that also supplies the on/off control.
    if (smartThresholdSetting && smartThresholdSetting.kind === "range") add(smartThresholdSetting)
    if (invertSetting && invertSetting.kind === "toggle") add(invertSetting)
    if (hiresSetting && hiresSetting.kind === "toggle") add(hiresSetting)
    if (thumbInvertSetting && thumbInvertSetting.kind === "toggle") add(thumbInvertSetting)
    if (thumbModeSetting && thumbModeSetting.kind === "toggle") add(thumbModeSetting)
    add(hostSetting); add(remapSetting); add(divertSetting)
    if (fnSetting && fnSetting.kind === "toggle") add(fnSetting)
    if (backlightSetting && (backlightSetting.kind === "range" || backlightSetting.kind === "choice")) add(backlightSetting)
    if (platformSetting && platformSetting.kind === "choice") add(platformSetting)
    add(lockSetting)
    return names
  }

  // Device-supplied names, for plain-text sinks only (no escaping needed).
  function plainName(item, fallback) {
    if (item && item.name) return String(item.name)
    return fallback !== undefined && fallback !== null ? String(fallback) : ""
  }

  // Why the selected device (or the desk) has nothing to show yet.
  function statusMessage() {
    if (!mx.installed) return "Install Solaar to configure your devices: omarchy pkg add solaar"
    if (mx.connecting) return "Connecting to your devices…"
    if (!device) return "No Logitech devices are connected to this computer right now. If they are switched to another computer, switch them back here."
    if (device.online === false) return "This device is offline. Wake it or reconnect it; its settings appear when it answers."
    if (!mx.accessible) return "Waiting for device access. After installing Solaar, reconnect your device so its access rules apply."
    return "Reading settings from the device" + (mx.progressLabel ? (" · " + mx.progressLabel) : "") + ". Bluetooth devices can take a few seconds."
  }

  function currentChannelText() {
    var channels = Model.deviceChannels(device)
    for (var i = 0; i < channels.length; i++)
      if (channels[i].current) return "channel " + (i + 1) + (channels[i].name ? " · " + channels[i].name : "")
    return ""
  }

  function deviceSummary(item) {
    if (!item) return ""
    var parts = [Model.isKeyboard(item) ? "keyboard" : Model.isMouse(item) ? "mouse" : "device"]
    parts.push(item.online === false ? "offline" : Model.connectionLabel(item).toLowerCase())
    var members = mx.switchConfig && mx.switchConfig.members ? mx.switchConfig.members : {}
    if (members[String(item.id)]) parts.push("in group")
    return parts.join("  ·  ")
  }

  function writeSetting(setting, value, key) {
    if (!mx || !setting) return
    mx.setSetting(setting.name, value, key)
  }

  function writeToggle(setting) {
    if (!setting) return
    writeSetting(setting, Model.nextToggleValue(setting))
  }

  function rowValue(row) {
    var current = row && row.value
    if (current && typeof current === "object" && current.id !== undefined) return String(current.id)
    return current === undefined || current === null ? "" : String(current)
  }

  function rowOptions(row) {
    var choices = row && row.choices ? row.choices : []
    var list = []
    for (var i = 0; i < choices.length; i++) {
      var item = choices[i]
      list.push({
        value: item && item.id !== undefined ? String(item.id) : String(item && item.name || item),
        label: item && item.name ? String(item.name) : String(item)
      })
    }
    return list
  }

  FloatingWindow {
    id: window
    title: "MX Unison"
    color: root.background
    implicitWidth: 1040
    implicitHeight: 800
    minimumSize: Qt.size(560, 520)
    maximumSize: Qt.size(1400, 1200)

    onVisibleChanged: {
      if (!visible && !root.closingFromHost && root.shell && typeof root.shell.hide === "function")
        root.shell.hide("local.mx-unison")
    }

    NumberAnimation {
      id: jumpAnim
      target: flick
      property: "contentY"
      duration: Style.duration(220)
      easing.type: Easing.OutCubic
    }

    FocusScope {
      anchors.fill: parent
      focus: true

      FocusScope {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.onPressed: function(event) {
          if (root.dropdownOpen) return
          if (event.key === Qt.Key_Escape) {
            root.requestClose()
            event.accepted = true
          } else if (event.key === Qt.Key_R && (event.modifiers & Qt.ControlModifier)) {
            mx.refresh(true)
            event.accepted = true
          }
        }

        // ── Sidebar: Desk, then each device ────────────────────────────
        Rectangle {
          id: sidebar
          visible: root.wideLayout
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          width: visible ? Style.space(250) : 0
          color: Qt.alpha(root.foreground, 0.02)
          Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Qt.alpha(root.foreground, 0.08) }

          Flickable {
            anchors.fill: parent
            anchors.margins: Style.space(18)
            anchors.bottomMargin: sidebarFooter.height + Style.space(24)
            contentHeight: sideColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
              id: sideColumn
              width: parent.width
              spacing: Style.space(4)

              Text {
                text: "MX UNISON"
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                font.letterSpacing: 2
              }
              Text {
                text: !mx.installed ? strings.t("nav.solaarMissing")
                  : mx.connecting ? strings.t("nav.connecting")
                  : mx.hasHidppSnapshot ? "● " + strings.t("nav.live") : "○ " + strings.t("nav.reading")
                textFormat: Text.PlainText
                color: mx.hasHidppSnapshot && mx.installed ? root.accent : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                bottomPadding: Style.space(18)
              }

              NavItem {
                glyph: "◆"
                label: strings.t("nav.desk")
                detail: Object.keys(mx.switchConfig.members || {}).length ? strings.t("nav.deskGroup") : strings.t("nav.deskSetup")
                selected: root.page === "desk"
                onActivated: root.showDesk()
              }

              Text {
                text: strings.t("nav.devices").toUpperCase()
                textFormat: Text.PlainText
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.letterSpacing: 1.5
                topPadding: Style.space(18)
                bottomPadding: Style.space(6)
              }

              Repeater {
                model: mx.displayDevices || []
                Column {
                  id: navDevice
                  required property var modelData
                  readonly property bool current: root.page === "device" && root.device && String(root.device.id) === String(modelData.id)
                  width: parent.width
                  spacing: Style.space(2)
                  NavItem {
                    glyph: Model.kindIcon(navDevice.modelData)
                    label: root.plainName(navDevice.modelData, "Logitech device")
                    detail: navDevice.modelData.online === false ? "offline" : Model.connectionLabel(navDevice.modelData).toLowerCase()
                    battery: Model.batteryPercent(navDevice.modelData)
                    batteryLow: Model.batteryLow(navDevice.modelData)
                    dimmed: navDevice.modelData.online === false
                    selected: navDevice.current
                    onActivated: root.showDevice(navDevice.modelData.id)
                  }
                  Repeater {
                    model: navDevice.current ? root.deviceSections : []
                    Button {
                      required property var modelData
                      width: parent.width
                      leftAlign: true
                      horizontalPadding: Style.space(34)
                      verticalPadding: Style.space(3)
                      text: modelData.label
                      fontSize: Style.font.caption
                      foreground: root.activeSection === modelData.key ? root.accent : root.dim
                      focusable: true
                      onClicked: root.jumpTo(modelData.key)
                    }
                  }
                }
              }

              Text {
                visible: (mx.displayDevices || []).length === 0
                width: parent.width
                text: strings.t("nav.noDevices")
                textFormat: Text.PlainText
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                leftPadding: Style.space(10)
              }
            }
          }

          Column {
            id: sidebarFooter
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: Style.space(18)
            spacing: Style.space(6)
            Button {
              width: parent.width
              text: strings.t("nav.refresh")
              iconText: "󰑐"
              iconSpinning: mx.connecting
              leftAlign: true
              bordered: true
              focusable: true
              tooltipText: strings.t("nav.refreshHelp")
              onClicked: mx.refresh(true)
            }
          }
        }

        // ── Page header ────────────────────────────────────────────────
        Column {
          id: header
          anchors.top: parent.top
          anchors.left: sidebar.right
          anchors.right: parent.right
          anchors.leftMargin: Style.space(36)
          anchors.rightMargin: Style.space(36)
          anchors.topMargin: Style.space(28)
          spacing: Style.space(10)

          // Narrow windows have no sidebar: pick a page here instead.
          Flow {
            visible: !root.wideLayout
            width: parent.width
            spacing: Style.space(6)
            Button {
              text: "◆ " + strings.t("nav.desk")
              selected: root.page === "desk"
              bordered: true
              focusable: true
              onClicked: root.showDesk()
            }
            Repeater {
              model: mx.displayDevices || []
              Button {
                required property var modelData
                text: root.plainName(modelData, "Device")
                iconText: Model.kindIcon(modelData)
                selected: root.page === "device" && root.device && String(root.device.id) === String(modelData.id)
                bordered: true
                focusable: true
                onClicked: root.showDevice(modelData.id)
              }
            }
          }

          Text {
            width: parent.width
            text: root.page === "desk" ? strings.t("nav.desk").toUpperCase() : (device ? root.plainName(device, "Logitech device").toUpperCase() : "NO DEVICE")
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle * 1.35
            font.bold: true
            font.letterSpacing: 1
          }

          Row {
            width: parent.width
            spacing: Style.space(14)
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: root.page === "desk"
                ? strings.t((mx.displayDevices || []).length === 1 ? "desk.deviceCount1" : "desk.deviceCount").arg(I18n.formatNumber((mx.displayDevices || []).length))
                : (device ? [Model.connectionLabel(device).toLowerCase(), root.currentChannelText()].filter(function(v) { return !!v }).join("  ·  ") : strings.t("desk.getStarted"))
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            MxMeter {
              anchors.verticalCenter: parent.verticalCenter
              visible: root.page === "device" && value >= 0
              value: Model.batteryPercent(device) / 100
              suffix: Model.batteryPercent(device) + "%"
              warn: Model.batteryLow(device)
            }
          }

          // Last action or error, one line.
          Text {
            visible: mx.actionStatus !== "" || mx.lastError !== ""
            width: parent.width
            text: "› " + (mx.actionStatus !== "" ? mx.actionStatus : mx.lastError)
            textFormat: Text.PlainText
            color: mx.lastError !== "" && mx.actionStatus === "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Rectangle { width: parent.width; height: 1; color: Qt.alpha(root.foreground, 0.10) }
        }

        // ── Page body ──────────────────────────────────────────────────
        Flickable {
          id: flick
          anchors.top: header.bottom
          anchors.bottom: parent.bottom
          anchors.left: sidebar.right
          anchors.right: parent.right
          anchors.leftMargin: Style.space(36)
          anchors.rightMargin: Style.space(24)
          anchors.topMargin: Style.space(4)
          contentWidth: width
          contentHeight: column.implicitHeight + Style.space(24)
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick
          onMovementStarted: jumpAnim.stop()
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
          onContentHeightChanged: {
            if (root.pendingJump !== "" && root.page === "device" && root.sectionItem(root.pendingJump)) {
              var key = root.pendingJump
              root.pendingJump = ""
              Qt.callLater(function() { root.jumpTo(key) })
            }
          }

          Column {
            id: column
            width: flick.width - Style.space(12)
            topPadding: Style.space(20)
            spacing: Style.space(40)

            // ── Desk ───────────────────────────────────────────────────
            MxSection {
              visible: root.page === "desk"
              title: strings.t("nav.devices")
              hint: (mx.displayDevices || []).length ? strings.t("desk.pickDevice") : ""
              Text {
                visible: (mx.displayDevices || []).length === 0
                width: parent.width
                text: root.statusMessage()
                textFormat: Text.PlainText
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                wrapMode: Text.WordWrap
              }
              Repeater {
                model: mx.displayDevices || []
                DeviceRow {
                  required property var modelData
                  item: modelData
                  onActivated: root.showDevice(modelData.id)
                }
              }
            }

            SwitchGroup {
              visible: root.page === "desk"
              width: parent.width
              mx: root.mx
              onDropdownOpenChanged: root.dropdownOpen = dropdownOpen
            }

            // ── Device: not ready yet ──────────────────────────────────
            MxSection {
              anchorKey: "status"
              visible: root.page === "device" && !root.canWrite
              title: strings.t("page.status")
              Text {
                width: parent.width
                text: root.statusMessage()
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                wrapMode: Text.WordWrap
              }
              MxMeter {
                visible: root.device && root.device.online !== false && mx.installed && mx.accessible && !mx.connecting
                value: mx.readPercent / 100
                cells: 24
                suffix: mx.readPercent + "%"
                fontSize: Style.font.body
              }
            }

            // ── Device: pointer ────────────────────────────────────────
            MxSection {
              anchorKey: "pointer"
              visible: root.page === "device" && root.canWrite && (!!dpiSetting || Model.isMouse(device))
              title: strings.t("page.pointer")
              SettingSlider {
                visible: !!dpiSetting
                label: strings.t("field.sensitivity")
                help: Model.helpForSetting(dpiSetting, "How far the pointer travels. 8K is 8000 DPI.")
                setting: dpiSetting
                formatValue: function(v) { return Math.round(v) + " dpi" }
              }
              MxField {
                visible: !!dpiSetting && Model.dpiPresets(dpiSetting).length > 0
                label: strings.t("field.presets")
                ButtonGroup {
                  width: parent.width
                  options: dpiSetting ? Model.dpiPresets(dpiSetting) : []
                  value: dpiSetting ? String(Math.round(Model.numericValue(dpiSetting, 0))) : ""
                  foreground: root.foreground
                  accent: root.accent
                  fontFamily: root.fontFamily
                  onChanged: function(value) { if (dpiSetting) root.writeSetting(dpiSetting, Number(value)) }
                }
              }
              MxField {
                visible: Model.isMouse(device)
                switchable: true
                label: "macOS-style acceleration"
                help: mx.pointerAccelerated && mx.pointerRuntime && mx.pointerRuntime.error
                  ? String(mx.pointerRuntime.error) : Model.pointerAccelHelp()
                checked: mx.pointerAccelerated
                onToggled: mx.setPointerAcceleration(mx.pointerAccelerated ? "system" : "mac")
              }
            }

            // ── Device: scroll ─────────────────────────────────────────
            MxSection {
              anchorKey: "scroll"
              visible: root.page === "device" && root.canWrite && !!(smartSetting || smartThresholdSetting || invertSetting || hiresSetting || Model.isMouse(device))
              title: strings.t("page.scroll")
              SettingToggle {
                visible: !!smartSetting
                label: "SmartShift"
                setting: smartSetting
                fallbackHelp: "Ratchet at slow speeds, free-spin when you scroll quickly."
                checked: root.smartState.on
              }
              SettingSlider {
                visible: !!(smartThresholdSetting && smartThresholdSetting.kind === "range")
                label: strings.t("field.shiftThreshold")
                help: Model.helpForSetting(smartThresholdSetting, "How fast you must scroll before the wheel leaves ratchet mode.")
                setting: smartThresholdSetting
              }
              SettingToggle {
                visible: !!invertSetting
                label: strings.t("field.invert")
                setting: invertSetting
                fallbackHelp: "Reverse the vertical wheel."
              }
              SettingToggle {
                visible: !!hiresSetting && hiresSetting.kind === "toggle"
                label: strings.t("field.hires")
                setting: hiresSetting
                fallbackHelp: "Finer wheel steps."
              }
              MxField {
                visible: Model.isMouse(device)
                label: strings.t("scroll.title").toLowerCase()
                help: mx.scrollError || strings.t("scroll.help")
                value: I18n.formatNumber(scrollSlider.liveValue, 2) + "×"
                Row {
                  width: parent.width
                  spacing: Style.space(12)
                  Item {
                    width: parent.width - resetScroll.implicitWidth - parent.spacing
                    height: scrollSlider.implicitHeight
                    anchors.verticalCenter: parent.verticalCenter
                    PanelSlider {
                      id: scrollSlider
                      anchors.left: parent.left
                      anchors.right: parent.right
                      bar: root.bar
                      minimum: 0.25
                      maximum: 4
                      step: 0.25
                      value: root.device ? Number(mx.scroll[String(root.device.id)] || 1) : 1
                      onReleased: function(next) { mx.setScrollSpeed(next) }
                    }
                    WheelGuard { anchors.fill: parent; target: flick }
                  }
                  Button {
                    id: resetScroll
                    anchors.verticalCenter: parent.verticalCenter
                    text: strings.t("scroll.default")
                    bordered: true
                    focusable: true
                    tooltipText: strings.t("scroll.reset")
                    onClicked: mx.setScrollSpeed(null)
                  }
                }
              }
            }

            // ── Device: thumb wheel ────────────────────────────────────
            MxSection {
              anchorKey: "thumb"
              visible: root.page === "device" && root.canWrite && !!(thumbInvertSetting || thumbModeSetting)
              title: strings.t("page.thumb")
              SettingToggle {
                visible: !!thumbInvertSetting
                label: strings.t("field.invert")
                setting: thumbInvertSetting
                fallbackHelp: "Reverse the thumb wheel."
              }
              SettingToggle {
                visible: !!thumbModeSetting && thumbModeSetting.kind === "toggle"
                label: "HID++ thumb wheel"
                setting: thumbModeSetting
                fallbackHelp: "Send thumb-wheel motion as HID++ for Solaar rules."
              }
            }

            // ── Device: keyboard ───────────────────────────────────────
            MxSection {
              anchorKey: "keyboard"
              visible: root.page === "device" && root.canWrite && !!(fnSetting || backlightSetting || platformSetting || lockSetting)
              title: strings.t("page.keys")
              SettingToggle {
                visible: !!fnSetting && fnSetting.kind === "toggle"
                label: fnSetting ? String(fnSetting.label).toLowerCase() : "fn swap"
                setting: fnSetting
                fallbackHelp: "Function keys send media actions by default."
              }
              SettingSlider {
                visible: !!backlightSetting && backlightSetting.kind === "range"
                label: backlightSetting ? String(backlightSetting.label).toLowerCase() : "backlight"
                help: Model.helpForSetting(backlightSetting, "Keyboard backlight brightness.")
                setting: backlightSetting
              }
              SettingChoice {
                visible: !!backlightSetting && backlightSetting.kind === "choice"
                setting: backlightSetting
              }
              SettingChoice {
                visible: !!platformSetting && platformSetting.kind === "choice"
                setting: platformSetting
              }
              Repeater {
                model: lockSetting && lockSetting.keys ? lockSetting.keys : []
                MxField {
                  required property var modelData
                  switchable: true
                  label: "disable " + (modelData && modelData.label ? modelData.label : "key")
                  checked: !!(modelData && modelData.value)
                  onToggled: if (root.lockSetting) root.writeSetting(root.lockSetting, !(modelData && modelData.value), modelData.key)
                }
              }
            }

            // ── Device: buttons & actions ──────────────────────────────
            MxSection {
              anchorKey: "buttons"
              visible: root.page === "device" && root.canWrite
              title: Model.isKeyboard(device) ? strings.t("page.actions") : strings.t("page.buttons")
              hint: strings.t("actions.help")
              ActionEditor {
                width: parent.width
                service: root.mx
                device: root.device
                controls: root.assignmentControls
                remapSetting: root.remapSetting
                divertSetting: root.divertSetting
                onDropdownOpenChanged: root.dropdownOpen = dropdownOpen
              }
            }

            // ── Device: its own Easy-Switch channels ───────────────────
            MxSection {
              anchorKey: "channels"
              visible: root.page === "device" && root.canWrite
              title: strings.t("page.channels")
              DeviceChannels {
                width: parent.width
                mx: root.mx
                device: root.device
                onOpenDesk: root.showDesk()
              }
            }

            // ── Device: profiles ───────────────────────────────────────
            MxSection {
              anchorKey: "profiles"
              visible: root.page === "device" && root.canWrite
              title: strings.t("page.profiles")
              hint: "Save this device’s current settings and apply them later. Profiles stay on this computer, include the pointer acceleration choice, and exclude the Easy-Switch channel."
              Repeater {
                model: root.deviceProfiles
                MxField {
                  id: profileRow
                  required property var modelData
                  label: root.plainName(modelData, "Profile")
                  help: Model.profileAccelerated(modelData) ? strings.t("field.profileAccel") : ""
                  Row {
                    width: parent.width
                    layoutDirection: Qt.RightToLeft
                    spacing: Style.space(8)
                    Button {
                      text: "Delete"
                      bordered: true
                      focusable: true
                      onClicked: mx.deleteProfile(profileRow.modelData.name)
                    }
                    Button {
                      text: "Apply"
                      bordered: true
                      focusable: true
                      onClicked: mx.applyProfile(profileRow.modelData.name)
                    }
                  }
                }
              }
              MxField {
                label: strings.t(root.deviceProfiles.length ? "field.newProfile" : "field.firstProfile")
                Row {
                  width: parent.width
                  spacing: Style.space(8)
                  TextField {
                    id: profileField
                    width: parent.width - saveBtn.implicitWidth - parent.spacing
                    placeholderText: "Name, e.g. Work"
                    onAccepted: { mx.saveProfile(text); text = "" }
                  }
                  Button {
                    id: saveBtn
                    text: "Save"
                    bordered: true
                    focusable: true
                    enabled: profileField.text.trim() !== ""
                    opacity: enabled ? 1 : 0.4
                    onClicked: { mx.saveProfile(profileField.text); profileField.text = "" }
                  }
                }
              }
            }

            // ── Device: everything else, collapsed ─────────────────────
            MxSection {
              anchorKey: "more"
              visible: root.page === "device" && root.canWrite && extraSettings.length > 0
              title: strings.t("page.more")
              hint: strings.t("page.moreHelp")
              Disclosure {
                text: root.showMore ? strings.t("page.moreHide") : strings.t(extraSettings.length === 1 ? "page.moreShow1" : "page.moreShow").arg(I18n.formatNumber(extraSettings.length))
                open: root.showMore
                onClicked: root.showMore = !root.showMore
              }
              Repeater {
                model: root.showMore ? extraSettings : []
                ExtraBlock {
                  required property var modelData
                  width: parent.width
                  setting: modelData
                }
              }
            }
          }
        }
      }
    }
  }

  // Sidebar entry: glyph, name, one dim detail line, optional battery.
  component NavItem: Item {
    id: nav
    property string glyph: ""
    property string label: ""
    property string detail: ""
    property int battery: -1
    property bool batteryLow: false
    property bool selected: false
    property bool dimmed: false
    signal activated()
    width: parent ? parent.width : implicitWidth
    implicitHeight: navText.implicitHeight + Style.space(14)
    activeFocusOnTab: true
    Keys.onReturnPressed: nav.activated()
    Keys.onEnterPressed: nav.activated()
    Keys.onSpacePressed: nav.activated()
    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: nav.selected ? Qt.alpha(root.accent, 0.12)
        : (nav.activeFocus || navMouse.containsMouse) ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"
      Behavior on color { ColorAnimation { duration: Style.duration(100) } }
      Rectangle {
        visible: nav.selected
        width: 2
        height: parent.height - Style.space(12)
        anchors.verticalCenter: parent.verticalCenter
        color: root.accent
      }
    }
    Text {
      id: navGlyph
      x: Style.space(10)
      y: Style.space(7)
      width: Style.space(18)
      text: nav.glyph
      textFormat: Text.PlainText
      color: nav.selected ? root.accent : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }
    Column {
      id: navText
      x: navGlyph.x + navGlyph.width + Style.space(6)
      y: Style.space(7)
      width: nav.width - x - Style.space(8)
      spacing: Style.space(1)
      opacity: nav.dimmed ? 0.55 : 1
      Text {
        width: parent.width
        text: nav.label
        textFormat: Text.PlainText
        color: nav.selected ? root.accent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: nav.selected
        elide: Text.ElideRight
      }
      Row {
        spacing: Style.space(8)
        Text {
          text: nav.detail
          textFormat: Text.PlainText
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
        MxMeter {
          value: nav.battery / 100
          cells: 5
          suffix: nav.battery + "%"
          warn: nav.batteryLow
        }
      }
    }
    MouseArea {
      id: navMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: nav.activated()
    }
  }

  // Desk page device line: the way into a device's settings.
  component DeviceRow: Item {
    id: deviceRow
    property var item: null
    signal activated()
    readonly property int battery: Model.batteryPercent(item)
    width: parent ? parent.width : implicitWidth
    implicitHeight: Style.space(46)
    activeFocusOnTab: true
    Keys.onReturnPressed: deviceRow.activated()
    Keys.onEnterPressed: deviceRow.activated()
    Keys.onSpacePressed: deviceRow.activated()
    Rectangle {
      anchors.fill: parent
      anchors.leftMargin: -Style.space(8)
      anchors.rightMargin: -Style.space(8)
      radius: Style.cornerRadius
      color: deviceRow.activeFocus || rowMouse.containsMouse ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"
      Behavior on color { ColorAnimation { duration: Style.duration(100) } }
    }
    Row {
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width
      spacing: Style.space(12)
      opacity: deviceRow.item && deviceRow.item.online === false ? 0.55 : 1
      Text {
        width: Style.space(20)
        anchors.verticalCenter: parent.verticalCenter
        text: Model.kindIcon(deviceRow.item)
        textFormat: Text.PlainText
        color: root.accent
        font.family: root.fontFamily
        font.pixelSize: Style.font.subtitle
      }
      Column {
        width: parent.width - Style.space(20) - meterBox.width - chevron.width - parent.spacing * 3
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)
        Text {
          width: parent.width
          text: root.plainName(deviceRow.item, "Logitech device")
          textFormat: Text.PlainText
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
          elide: Text.ElideRight
        }
        Text {
          width: parent.width
          text: root.deviceSummary(deviceRow.item)
          textFormat: Text.PlainText
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
      Item {
        id: meterBox
        width: Style.space(150)
        height: parent.height
        MxMeter {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          value: deviceRow.battery / 100
          suffix: deviceRow.battery + "%"
          warn: Model.batteryLow(deviceRow.item)
        }
      }
      Text {
        id: chevron
        anchors.verticalCenter: parent.verticalCenter
        text: "›"
        textFormat: Text.PlainText
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.subtitle
      }
    }
    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: deviceRow.activated()
    }
  }

  component Disclosure: Button {
    property bool open: false
    iconText: "󰅂"
    iconRotation: open ? 90 : 0
    leftAlign: true
    focusable: true
    horizontalPadding: Style.space(4)
    Behavior on iconRotation { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }
  }

  // A device toggle setting as a whole-row switch with inline help.
  component SettingToggle: MxField {
    property var setting: null
    property string fallbackHelp: ""
    switchable: true
    help: Model.helpForSetting(setting, fallbackHelp)
    checked: setting ? Model.boolValue(setting) : false
    onToggled: root.writeToggle(setting)
  }

  // A device range setting. Writes once, on release; the page wheel never
  // reaches the slider.
  component SettingSlider: MxField {
    id: sliderField
    property var setting: null
    property var formatValue: null
    property var settingKey: undefined
    readonly property var bounds: Model.sliderBounds(setting)
    function displayFor(v) {
      return sliderField.formatValue ? sliderField.formatValue(v) : String(Math.round(v))
    }
    value: displayFor(Model.snapToChoices(setting, blockSlider.liveValue))
    Item {
      width: parent.width
      height: blockSlider.implicitHeight
      PanelSlider {
        id: blockSlider
        anchors.left: parent.left
        anchors.right: parent.right
        bar: root.bar
        minimum: sliderField.bounds.min
        maximum: sliderField.bounds.max
        step: sliderField.bounds.step
        integer: true
        value: sliderField.setting ? Model.numericValue(sliderField.setting, sliderField.bounds.min) : sliderField.bounds.min
        onReleased: function(next) {
          if (sliderField.setting) root.writeSetting(sliderField.setting, Model.snapToChoices(sliderField.setting, next), sliderField.settingKey)
        }
      }
      WheelGuard { anchors.fill: parent; target: flick }
    }
  }

  // A device choice setting as a dropdown that stays bound to the device.
  component SettingChoice: MxField {
    id: choiceField
    property var setting: null
    label: setting ? String(setting.label || setting.name).toLowerCase() : ""
    help: Model.helpForSetting(setting, "")
    Item {
      width: parent.width
      height: choiceDrop.implicitHeight
      Dropdown {
        id: choiceDrop
        function saved() { return choiceField.setting ? Model.choiceId(choiceField.setting) : "" }
        width: parent.width
        showLabel: false
        value: saved()
        options: choiceField.setting ? Model.choiceOptions(choiceField.setting) : []
        foreground: root.foreground
        fontFamily: root.fontFamily
        onChanged: function(next) {
          if (choiceField.setting) root.writeSetting(choiceField.setting, next)
          value = Qt.binding(saved)
        }
        onPopupOpenChanged: root.dropdownOpen = popupOpen
        Component.onDestruction: if (popupOpen) root.dropdownOpen = false
      }
      WheelGuard { anchors.fill: parent; target: flick }
    }
  }

  component MapRow: Item {
    id: mapRow
    property var row: ({})
    property var setting: null
    property string label: row && row.label ? row.label : "Button"
    implicitHeight: mapDrop.implicitHeight
    Dropdown {
      id: mapDrop
      function saved() { return root.rowValue(mapRow.row) }
      width: parent.width
      label: mapRow.label
      value: saved()
      options: root.rowOptions(mapRow.row)
      foreground: root.foreground
      fontFamily: root.fontFamily
      onChanged: function(next) {
        if (mapRow.setting) root.writeSetting(mapRow.setting, next, mapRow.row.key)
        value = Qt.binding(saved)
      }
      onPopupOpenChanged: root.dropdownOpen = popupOpen
      Component.onDestruction: if (popupOpen) root.dropdownOpen = false
    }
    WheelGuard { anchors.fill: parent; target: flick }
  }

  component ExtraBlock: Column {
    id: extraBlock
    property var setting: null
    readonly property string kind: setting ? String(setting.kind) : ""
    readonly property string title: setting ? String(setting.label || setting.name).toLowerCase() : ""
    spacing: Style.space(10)
    SettingToggle {
      visible: extraBlock.kind === "toggle"
      label: extraBlock.title
      setting: extraBlock.kind === "toggle" ? extraBlock.setting : null
    }
    SettingSlider {
      visible: extraBlock.kind === "range"
      label: extraBlock.title
      help: Model.helpForSetting(extraBlock.setting, "")
      setting: extraBlock.kind === "range" ? extraBlock.setting : null
    }
    SettingChoice {
      visible: extraBlock.kind === "choice"
      setting: extraBlock.kind === "choice" ? extraBlock.setting : null
    }
    MxField {
      visible: extraBlock.kind === "map_choice" || extraBlock.kind === "multiple_toggle"
      stacked: true
      label: extraBlock.title
      help: Model.helpForSetting(extraBlock.setting, "")
      Column {
        width: parent.width
        spacing: Style.space(10)
        Repeater {
          model: extraBlock.kind === "map_choice" || extraBlock.kind === "multiple_toggle" ? Model.keyRows(extraBlock.setting) : []
          Column {
            required property var modelData
            width: parent.width
            MapRow {
              visible: modelData.kind === "choice"
              width: parent.width
              row: modelData
              setting: extraBlock.setting
            }
            MxField {
              visible: modelData.kind === "toggle"
              switchable: true
              label: modelData.label || modelData.key
              checked: !!modelData.value
              onToggled: root.writeSetting(extraBlock.setting, !modelData.value, modelData.key)
            }
            SettingSlider {
              visible: modelData.kind === "range"
              label: modelData.label || modelData.key
              setting: modelData.kind === "range" ? Object.assign({}, modelData, { name: extraBlock.setting.name }) : null
              settingKey: modelData.key
            }
          }
        }
      }
    }
  }
}
