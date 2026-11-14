import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar popup: glance and act. Devices and battery, switch the whole desk,
// and a couple of everyday settings. Everything else lives in the settings
// window, so this popup never needs scrolling and has no sliders.
Panel {
  id: root
  moduleName: "local.mx-unison"
  ipcTarget: "local.mx-unison"
  manageIpc: false

  Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  property var anchorItem: null
  property var hostWidget: null
  property var mx: null

  readonly property var barIdentity: hostWidget || root
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color accent: Color.accent
  readonly property color surface: Color.popups.background
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var device: mx ? mx.selectedDevice : null
  readonly property bool canWrite: !!(mx && mx.hidppReady)
  readonly property var devices: mx && mx.displayDevices ? mx.displayDevices : []
  readonly property bool isKeyboard: Model.isKeyboard(device)

  readonly property var dpiSetting: Model.settingByNames(device, ["dpi", "dpi-extended", "dpi_extended"])
  readonly property var dpiOptions: dpiSetting ? Model.dpiPresets(dpiSetting) : []
  readonly property string dpiValue: dpiSetting ? String(Math.round(Model.numericValue(dpiSetting, 0))) : ""
  readonly property var smartSetting: Model.settingByNames(device, ["scroll-ratchet", "smartshift"])
  readonly property var smartState: Model.smartShiftState(smartSetting)
  readonly property var fnSetting: Model.settingByNames(device, ["fn-swap", "fn_swap"])
  readonly property var backlightSetting: Model.settingByNames(device, ["backlight", "backlight_level", "backlight-level"])
  readonly property var backlightOptions: backlightSetting && backlightSetting.kind === "choice" ? Model.choiceOptions(backlightSetting) : []
  readonly property var hostSetting: Model.settingByNames(device, ["change-host", "change_host"])
  // Channel chips named from the device's stored host names (raw text:
  // every sink here is plain text, so escaping would show entities).
  readonly property var hostOptions: {
    if (!hostSetting) return []
    var channels = Model.deviceChannels(device)
    return [0, 1, 2].map(function(c) {
      var info = channels[c] || {}
      return { value: String(c), label: info.name ? info.name : String(c + 1), tooltip: info.paired === false ? "Not paired" : "" }
    })
  }

  // Switching the whole desk is the main daily action once a group exists.
  readonly property var deskTargets: mx ? Model.deskTargets(mx.switchConfig, devices) : []
  readonly property var deskOptions: deskTargets.filter(function(t) { return t.available }).map(function(t) {
    return { value: String(t.target), label: t.name || ("Computer " + t.target) }
  })
  readonly property string deskHere: {
    for (var i = 0; i < deskTargets.length; i++) if (deskTargets[i].here) return String(deskTargets[i].target)
    return ""
  }
  readonly property bool showDesk: !!(mx && mx.installed && deskOptions.length > 1)
  // Without a group, fall back to moving just the selected device.
  readonly property bool showHosts: !showDesk && canWrite && !!hostSetting && hostOptions.length > 1

  // Everyday settings for the selected device, in display order.
  readonly property var quickItems: {
    if (!canWrite) return []
    var items = []
    if (isKeyboard) {
      if (fnSetting && fnSetting.kind === "toggle") items.push("fn")
      if (backlightSetting && backlightSetting.kind === "toggle") items.push("backlight")
      else if (backlightOptions.length > 1 && backlightOptions.length <= 4) items.push("backlight")
    } else {
      if (dpiOptions.length > 0) items.push("dpi")
      if (smartSetting) items.push("smart")
    }
    return items
  }

  // One-word helper state for the header, like the settings sidebar.
  readonly property string liveText: {
    if (!mx) return strings.t("nav.reading")
    if (!mx.installed) return strings.t("nav.solaarMissing")
    if (mx.connecting && !canWrite) return strings.t("nav.connecting")
    if (!devices.length) return strings.t("nav.noDevices")
    return canWrite ? "● " + strings.t("nav.live") : "○ " + strings.t("nav.reading")
  }

  property string focusSection: "header"
  property int cursorIndex: 0
  property bool cursorActive: false
  property bool dropdownOpen: false
  readonly property bool headerHasCursor: cursorActive && focusSection === "header"

  // Device-supplied names, for plain-text sinks only.
  function plainName(item, fallback) {
    if (item && item.name) return String(item.name)
    return fallback !== undefined && fallback !== null ? String(fallback) : ""
  }

  function open() {
    root.controller.show()
    if (mx) {
      mx.ensureDaemon()
      mx.refresh()
    }
  }

  function close() {
    dropdownOpen = false
    root.controller.hide()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function persistSelected(id) {
    if (!root.bar || !root.bar.shell || typeof root.bar.shell.updateEntryInline !== "function") return
    var entry = { id: root.moduleName }
    for (var key in settings) if (key !== "id") entry[key] = settings[key]
    entry.selectedDevice = String(id || "")
    root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function chooseDevice(id) {
    if (!mx) return
    mx.selectDevice(id)
    persistSelected(id)
    mx.refresh()
  }

  function openSettings(section) {
    var payload = {}
    if (device && device.id) payload.device = String(device.id)
    if (section) payload.section = section
    root.close()
    Qt.callLater(function() {
      if (root.bar && root.bar.shell && typeof root.bar.shell.summon === "function")
        root.bar.shell.summon("local.mx-unison", JSON.stringify(payload))
    })
  }

  function writeSetting(setting, value, key) {
    if (!mx || !setting) return
    if (String(setting.name) === "change-host" && Model.choiceId(setting) === String(value)) return
    mx.setSetting(setting.name, value, key)
  }

  function writeToggle(setting) {
    if (!setting) return
    writeSetting(setting, Model.nextToggleValue(setting))
  }

  function switchDesk(target) {
    if (!mx || String(target) === deskHere) return
    mx.switchTogether(Number(target))
  }

  function stepChoice(options, current, dx) {
    if (!options.length) return ""
    var index = -1
    for (var i = 0; i < options.length; i++) if (options[i].value === current) index = i
    if (index < 0) {
      // Not on a preset: step to the nearest preset in that direction.
      var n = Number(current)
      for (var j = 0; j < options.length; j++) if (Number(options[j].value) > n) { index = dx > 0 ? j - 1 : j; break }
      if (index < 0) index = options.length - (dx > 0 ? 1 : 0)
    }
    var next = Math.max(0, Math.min(options.length - 1, index + dx))
    return options[next].value
  }

  function sectionList() {
    var sections = ["header"]
    if (mx && !mx.installed) sections.push("install")
    else if (mx && mx.installed && !mx.accessible) sections.push("access")
    if (devices.length > 1) sections.push("devices")
    if (showDesk) sections.push("desk")
    if (showHosts) sections.push("hosts")
    if (quickItems.length) sections.push("quick")
    if (canWrite) sections.push("settings")
    return sections
  }

  function sectionCount(section) {
    if (section === "devices") return devices.length
    if (section === "desk") return deskOptions.length
    if (section === "hosts") return hostOptions.length
    if (section === "quick") return quickItems.length
    return 1
  }

  function ensureCursor() {
    var sections = sectionList()
    if (sections.indexOf(focusSection) < 0) focusSection = sections.length ? sections[0] : "header"
    var count = sectionCount(focusSection)
    if (cursorIndex >= count) cursorIndex = Math.max(0, count - 1)
    if (cursorIndex < 0) cursorIndex = 0
  }

  function quickHasCursor(item) {
    return cursorActive && focusSection === "quick" && quickItems[cursorIndex] === item
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    ensureCursor()
    if (dx !== 0) {
      // Left/right moves within a row of choices, or steps a choice setting.
      if (focusSection === "quick" && quickItems[cursorIndex] === "dpi") {
        var dpi = stepChoice(dpiOptions, dpiValue, dx)
        if (dpi !== "" && dpi !== dpiValue) writeSetting(dpiSetting, Number(dpi))
        return
      }
      if (focusSection === "quick" && quickItems[cursorIndex] === "backlight" && backlightOptions.length) {
        var level = stepChoice(backlightOptions, Model.choiceId(backlightSetting), dx)
        if (level !== "" && level !== Model.choiceId(backlightSetting)) writeSetting(backlightSetting, level)
        return
      }
      if (focusSection === "devices" || focusSection === "desk" || focusSection === "hosts") {
        cursorIndex = Math.max(0, Math.min(sectionCount(focusSection) - 1, cursorIndex + dx))
        return
      }
    }
    if (dy === 0) return
    var horizontal = focusSection === "desk" || focusSection === "hosts"
    var sections = sectionList()
    var index = sections.indexOf(focusSection)
    var count = sectionCount(focusSection)
    if (!horizontal && dy > 0 && cursorIndex < count - 1) { cursorIndex += 1; return }
    if (!horizontal && dy < 0 && cursorIndex > 0) { cursorIndex -= 1; return }
    var nextSection = index + (dy > 0 ? 1 : -1)
    if (nextSection < 0 || nextSection >= sections.length) return
    focusSection = sections[nextSection]
    var nextHorizontal = focusSection === "desk" || focusSection === "hosts"
    cursorIndex = dy > 0 || nextHorizontal ? 0 : Math.max(0, sectionCount(focusSection) - 1)
  }

  function activateCursor() {
    ensureCursor()
    if (focusSection === "install" && mx) mx.installSolaar()
    else if (focusSection === "access" && mx) mx.triggerUdev()
    else if (focusSection === "devices" && devices[cursorIndex]) chooseDevice(devices[cursorIndex].id)
    else if (focusSection === "desk" && deskOptions[cursorIndex]) switchDesk(deskOptions[cursorIndex].value)
    else if (focusSection === "hosts" && hostSetting && hostOptions[cursorIndex]) writeSetting(hostSetting, hostOptions[cursorIndex].value)
    else if (focusSection === "quick") {
      var item = quickItems[cursorIndex]
      if (item === "smart") writeToggle(smartSetting)
      else if (item === "fn") writeToggle(fnSetting)
      else if (item === "backlight" && backlightSetting && backlightSetting.kind === "toggle") writeToggle(backlightSetting)
    }
    else if (focusSection === "settings") openSettings()
  }

  function setCursor(section, index) {
    cursorActive = true
    focusSection = section
    cursorIndex = index
  }

  onOpenedChanged: {
    if (!opened) {
      dropdownOpen = false
      return
    }
    cursorActive = false
    if (panelFlick) panelFlick.contentY = 0
    if (mx) {
      mx.ensureDaemon()
      mx.refresh()
    }
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(Math.max(column.implicitHeight, root.canWrite ? 0 : Style.space(200)), Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // blocked, not enabled:false — disabling this item also disables the
      // Flickable and every control inside it, so the popup never receives
      // clicks and dropdownOpen can stay stuck until the shell restarts.
      blocked: root.dropdownOpen
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") { if (mx) mx.refresh() }
      }

      // Normally fits without scrolling; kept for very small screens.
      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(18)

          // ── Header ──────────────────────────────────────────────────
          Column {
            width: parent.width
            spacing: Style.space(8)
            Item {
              x: Style.space(10)
              width: parent.width - Style.space(20)
              implicitHeight: brand.implicitHeight
              Text {
                id: brand
                text: "MX UNISON"
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                font.letterSpacing: 2
              }
              Text {
                anchors.right: parent.right
                anchors.verticalCenter: brand.verticalCenter
                text: root.liveText
                textFormat: Text.PlainText
                color: root.canWrite ? root.accent : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
            Rectangle { width: parent.width; height: 1; color: Qt.alpha(root.foreground, 0.12) }
            // Last action or error, one line.
            Text {
              visible: !!(mx && (mx.actionStatus !== "" || mx.lastError !== ""))
              x: Style.space(10)
              width: parent.width - Style.space(20)
              text: "› " + (mx && mx.actionStatus !== "" ? mx.actionStatus : (mx ? mx.lastError : ""))
              textFormat: Text.PlainText
              color: mx && mx.lastError !== "" && mx.actionStatus === "" ? root.urgent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          // ── Setup problems ──────────────────────────────────────────
          MxSection {
            visible: !!(mx && !mx.installed)
            title: "Setup"
            hint: "MX Unison uses Solaar to talk to Logitech devices. Install it, then reconnect your devices."
            MxInset {
            Button {
              text: "Install Solaar"
              bordered: true
              hasCursor: root.cursorActive && root.focusSection === "install"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: if (mx) mx.installSolaar()
              onHovered: function(on) { if (on) root.setCursor("install", 0) }
            }
            }
          }

          MxSection {
            visible: !!(mx && mx.installed && !mx.accessible && !mx.connecting)
            title: "Access"
            hint: "Solaar is installed, but your user cannot open the devices yet. Reconnect them, or reload the device rules."
            MxInset {
            Button {
              text: "Reload udev"
              bordered: true
              hasCursor: root.cursorActive && root.focusSection === "access"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: if (mx) mx.triggerUdev()
              onHovered: function(on) { if (on) root.setCursor("access", 0) }
            }
            }
          }

          // ── Devices: pick which one the quick settings apply to ─────
          MxSection {
            visible: root.devices.length > 0
            title: strings.t("nav.devices")
            Column {
              width: parent.width
              spacing: Style.space(2)
              Repeater {
                model: root.devices
                Item {
                  id: deviceRow
                  required property var modelData
                  required property int index
                  readonly property bool selected: !!(device && String(device.id) === String(modelData.id))
                  readonly property bool cursor: root.cursorActive && root.focusSection === "devices" && root.cursorIndex === index
                  readonly property int battery: Model.batteryPercent(modelData)
                  width: parent.width
                  implicitHeight: Style.space(38)
                  MxStateSurface {
                    id: rowSurface
                    anchors.fill: parent
                    selected: deviceRow.selected
                    hot: deviceRow.cursor || rowMouse.containsMouse
                    pressed: rowMouse.pressed
                    foreground: root.foreground
                    accent: root.accent
                  }
                  Row {
                    x: Style.space(10)
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - Style.space(20)
                    spacing: Style.space(10)
                    opacity: deviceRow.modelData.online === false ? 0.55 : 1
                    Text {
                      width: Style.space(18)
                      anchors.verticalCenter: parent.verticalCenter
                      text: Model.kindIcon(deviceRow.modelData)
                      textFormat: Text.PlainText
                      color: deviceRow.selected ? rowSurface.contentColor : root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                    }
                    Text {
                      width: parent.width - Style.space(18) - state.width - parent.spacing * 2
                      anchors.verticalCenter: parent.verticalCenter
                      text: root.plainName(deviceRow.modelData, "Device")
                      textFormat: Text.PlainText
                      color: rowSurface.contentColor
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: rowSurface.contentBold
                      elide: Text.ElideRight
                    }
                    Item {
                      id: state
                      width: Math.max(meter.implicitWidth, offline.implicitWidth)
                      height: parent.height
                      anchors.verticalCenter: parent.verticalCenter
                      MxMeter {
                        id: meter
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        visible: deviceRow.modelData.online !== false && value >= 0
                        value: deviceRow.battery / 100
                        cells: 5
                        suffix: deviceRow.battery + "%"
                        warn: Model.batteryLow(deviceRow.modelData)
                      }
                      Text {
                        id: offline
                        visible: deviceRow.modelData.online === false
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: "offline"
                        textFormat: Text.PlainText
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                    }
                  }
                  MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.chooseDevice(deviceRow.modelData.id)
                    onContainsMouseChanged: if (containsMouse) root.setCursor("devices", deviceRow.index)
                  }
                }
              }
            }
          }

          // ── Whole-desk switching, named after your computers ────────
          MxSection {
            visible: root.showDesk
            title: strings.t("popup.switchDesk")
            MxInset {
            MxChips {
              width: parent.width
              options: root.deskOptions
              value: root.deskHere
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              cursorIndex: root.cursorActive && root.focusSection === "desk" ? root.cursorIndex : -1
              onChanged: function(value) { root.switchDesk(value) }
              onHovered: function(index, on) { if (on) root.setCursor("desk", index) }
            }
            }
          }

          // ── No group yet: move just this device ─────────────────────
          MxSection {
            visible: root.showHosts
            title: strings.t("popup.switchDevice")
            MxInset {
            MxChips {
              width: parent.width
              options: root.hostOptions
              value: hostSetting ? Model.choiceId(hostSetting) : ""
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              cursorIndex: root.cursorActive && root.focusSection === "hosts" ? root.cursorIndex : -1
              onChanged: function(value) { if (hostSetting) root.writeSetting(hostSetting, value) }
              onHovered: function(index, on) { if (on) root.setCursor("hosts", index) }
            }
            }
          }

          // ── Everyday settings for the selected device ───────────────
          MxSection {
            visible: root.quickItems.length > 0
            title: root.plainName(device, "Device")

            MxField {
              visible: root.quickItems.indexOf("dpi") >= 0
              stacked: true
              label: strings.t("popup.sensitivity").toLowerCase() + (root.dpiValue !== "" ? "  ·  " + root.dpiValue + " dpi" : "")
              hasCursor: root.quickHasCursor("dpi")
              onHovered: function(on) { if (on) root.setCursor("quick", root.quickItems.indexOf("dpi")) }
              MxChips {
                width: parent.width
                options: root.dpiOptions
                value: root.dpiValue
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                cursorIndex: root.quickHasCursor("dpi") ? Math.max(0, root.dpiOptions.map(function(o) { return o.value }).indexOf(root.dpiValue)) : -1
                onChanged: function(value) { if (root.dpiSetting) root.writeSetting(root.dpiSetting, Number(value)) }
              }
            }

            MxField {
              visible: root.quickItems.indexOf("smart") >= 0
              switchable: true
              label: "SmartShift"
              help: strings.t("popup.smartshiftHelp")
              checked: root.smartState.on
              hasCursor: root.quickHasCursor("smart")
              onToggled: root.writeToggle(root.smartSetting)
              onHovered: function(on) { if (on) root.setCursor("quick", root.quickItems.indexOf("smart")) }
            }

            MxField {
              visible: root.quickItems.indexOf("fn") >= 0
              switchable: true
              label: root.fnSetting && root.fnSetting.label ? String(root.fnSetting.label) : "Swap Fx function"
              help: strings.t("popup.fnHelp")
              checked: root.fnSetting ? Model.boolValue(root.fnSetting) : false
              hasCursor: root.quickHasCursor("fn")
              onToggled: root.writeToggle(root.fnSetting)
              onHovered: function(on) { if (on) root.setCursor("quick", root.quickItems.indexOf("fn")) }
            }

            MxField {
              visible: root.quickItems.indexOf("backlight") >= 0 && !!root.backlightSetting && root.backlightSetting.kind === "toggle"
              switchable: true
              label: strings.t("popup.backlight")
              checked: root.backlightSetting ? Model.boolValue(root.backlightSetting) : false
              hasCursor: root.quickHasCursor("backlight")
              onToggled: root.writeToggle(root.backlightSetting)
              onHovered: function(on) { if (on) root.setCursor("quick", root.quickItems.indexOf("backlight")) }
            }

            MxField {
              visible: root.quickItems.indexOf("backlight") >= 0 && root.backlightOptions.length > 0
              stacked: true
              label: strings.t("popup.backlight").toLowerCase()
              hasCursor: root.quickHasCursor("backlight")
              onHovered: function(on) { if (on) root.setCursor("quick", root.quickItems.indexOf("backlight")) }
              MxChips {
                width: parent.width
                options: root.backlightOptions
                value: root.backlightSetting ? Model.choiceId(root.backlightSetting) : ""
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                cursorIndex: root.quickHasCursor("backlight") ? Math.max(0, root.backlightOptions.map(function(o) { return o.value }).indexOf(Model.choiceId(root.backlightSetting))) : -1
                onChanged: function(value) { if (root.backlightSetting) root.writeSetting(root.backlightSetting, value) }
              }
            }
          }

          // ── Still reading ───────────────────────────────────────────
          MxSection {
            visible: !!(mx && mx.installed && (mx.accessible || mx.connecting) && !root.canWrite)
            title: strings.t("page.status")
            MxInset {
            Text {
              width: parent.width
              text: {
                if (mx && mx.connecting)
                  return "Connecting to your devices…"
                if (!mx || !mx.daemonWanted)
                  return "Click the bar icon again if settings do not appear."
                if (mx.lastError)
                  return mx.lastError
                if (mx.hidppTicks > 12)
                  return "Still reading settings. Right-click the bar icon to retry."
                if (mx.progressLabel)
                  return "Reading " + mx.progressLabel + "…"
                return "Reading settings from the device…"
              }
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
            MxMeter {
              visible: !!(mx && mx.daemonWanted && !mx.lastError)
              value: (mx && mx.readPercent ? mx.readPercent : 0) / 100
              cells: 20
              suffix: (mx && mx.readPercent ? mx.readPercent : 0) + "%"
            }
            }
          }

          // ── Footer ──────────────────────────────────────────────────
          Column {
            width: parent.width
            spacing: Style.space(8)
            Rectangle { width: parent.width; height: 1; color: Qt.alpha(root.foreground, 0.12) }
            Button {
              visible: root.canWrite
              text: strings.t("popup.settings")
              iconText: "󰒓"
              leftAlign: true
              bordered: true
              width: parent.width
              hasCursor: root.cursorActive && root.focusSection === "settings"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.openSettings()
              onHovered: function(on) { if (on) root.setCursor("settings", 0) }
            }
            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: strings.t("popup.keys")
              textFormat: Text.PlainText
              color: Qt.alpha(root.foreground, 0.35)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }
      }
    }
  }
}
