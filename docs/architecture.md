# Architecture and validation status

## Modules

| File | Responsibility |
| --- | --- |
| `manifest.json` | Omarchy plugin identity, entry points and dependency metadata |
| `BarWidget.qml`, `Panel.qml` | Bar entry and compact popup |
| `MxSettings.qml`, `ActionEditor.qml`, `SwitchGroup.qml` | Settings window, software actions and group configuration |
| `Service.qml` | Shared shell service, helper lifecycle, command queue and snapshot delivery |
| `Model.js` | UI data transformations and escaped display text |
| `mxctl.py` | Discovery, Solaar integration, command spool, settings and persistent preferences |
| `mxswitch.py` | Validated group mappings, switch ordering and optional keyboard host-change observation |
| `mxscroll.py` | Local per-mouse Hyprland scroll-factor overrides |
| `mxactions.py` | Device action listeners and application-targeted shortcut execution |
| `mxpointer.py` | Runtime pointer acceleration, compositor IPC and reload observation |
| `i18n/` | Translation catalogs for new UI strings |

## Runtime

The plugin loads inside the existing Omarchy shell; it does not start another production Quickshell instance. A shared service starts a system-Python helper on demand. The helper serializes configuration operations, holds device command handles, publishes a local JSON snapshot and drains private runtime command files. Independent notification handles keep event reads separate from HID++ command replies.

Discovery can show basic device information before full HID++ settings are available. Full reads can be slow, especially over Bluetooth. Status progress and a heartbeat distinguish a live helper from cached data. The absence of periodic network requests does not mean the helper is idle: local discovery, heartbeats and device/event processing continue as needed.

A group configuration maps three logical targets to device channels. Preflight consults opened devices, their supported choices and the latest snapshot’s pairing flags. Commands are sent sequentially without saving channels as reconnect preferences. Validation cannot make a multi-device switch atomic: once an earlier device leaves, subsequent failures cannot roll it back. A sent command is not proof of destination connectivity.

Physical following uses one of two signals. With CHANGE_HOST v2 it reads the host-change notification. Otherwise, if the Easy-Switch keys support REPROG_CONTROLS_V4 analytics reporting, it enables reporting for those three keys only. Solaar's own `setCidReporting` omits the needed flag byte, so the helper sends that request itself and clears it again when following stops. The listener applies the logical target to other group members; it does not issue a second switch to the already departing keyboard. This differs from persistent device linking through host cookies and does not implement Flow. Support must be demonstrated on actual firmware/transport combinations.

## Current validation limits

Automated checks cover synthetic protocol events, validation and failure paths. A development smoke test confirmed discovery, device feature loading and rendering of the settings window with real mouse/keyboard hardware. A maintainer confirmed one outbound coordinated switch through the keyboard shortcut, with an MX Master 3S (Bluetooth) and an MX Mechanical Mini (Bolt). Outbound physical following in key-reporting mode also worked with that pair: the keyboard's report arrived before it left and the mouse switched on the first command. The return direction, partial failures and CHANGE_HOST v2 following have not been tested on hardware. Do not infer universal compatibility from these checks.

Local profiles retain inherited limitations: names are global, kind-based UI filtering does not prove cross-model compatibility, and settings are applied sequentially without rollback. Some inherited interface text remains English. Discovery filters primarily target MX-related device names; supported receiver enumeration is broader than proven peripheral support.

## Historical references

[Options parity review](options-parity-review.md) and [performance/stability review](performance-stability-review.md) are inherited engineering notes from MX Control. They explain prior decisions and limitations; they are not fresh measurements or validation of MX Unison. Consult the README and changelog for current switching and scroll features.

[Rust/lean-helper plan](rust-plan.md) is a forward-looking proposal for reducing the resident footprint.

External reference links are documented in the README for maintainers. They are not contacted by the plugin during normal operation.
