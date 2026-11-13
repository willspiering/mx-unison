# MX Unison

**Logitech MX mouse and keyboard settings for [Omarchy](https://omarchy.org), plus one-press Easy-Switch for the whole desk.**

MX Unison is an Omarchy shell plugin that does two jobs:

1. **Configures Logitech devices on Linux.** DPI, SmartShift, scroll direction and speed, thumb wheel, button remaps, gestures, per-app shortcuts, keyboard function-key mode and backlight: the settings people usually need Logi Options+ for, which does not run on Linux.
2. **Moves your mouse and keyboard to another computer together.** Logitech's Easy-Switch buttons switch one device at a time. If you share a mouse and keyboard between a Linux desktop and a laptop, you normally press a channel button on each device. MX Unison switches the whole group with one button, one keyboard shortcut or, experimentally, by following the keyboard's own Easy-Switch button.

It runs inside Omarchy's existing Quickshell bar, talks to devices locally over HID++ through [Solaar](https://github.com/pwr-Solaar/Solaar)'s library, and has no cloud account, telemetry, AI features or network access.

> **Status: early development (0.1.0).** Device settings work on the hardware they have been tried on. In one real setup (MX Master 3S over Bluetooth plus MX Mechanical Mini over Bolt), switching the group with the shortcut and with the keyboard's own Easy-Switch key both worked, outbound. Neither has been tested widely, and physical following is still experimental. This is not full Logi Options+ parity. See [Limitations](#limitations).

## Contents

- [Who it is for](#who-it-is-for)
- [Features](#features)
- [How it works](#how-it-works)
- [Requirements](#requirements)
- [Install](#install)
- [Using it](#using-it)
- [Switching a group of devices](#switching-a-group-of-devices)
- [Files, configuration and privacy](#files-configuration-and-privacy)
- [Troubleshooting](#troubleshooting)
- [Limitations](#limitations)
- [Uninstall](#uninstall)
- [Roadmap](#roadmap)
- [Development](#development)
- [Credits and license](#credits-and-license)

## Who it is for

- You run **Omarchy 4** (Hyprland with the Quickshell-based `omarchy-shell`).
- You own a **Logitech MX-series mouse and/or keyboard** (MX Master, MX Anywhere, MX Vertical, MX Ergo, MX Keys and similar), connected over Bluetooth or a Logi Bolt / Unifying receiver.
- You want to change device settings from the desktop instead of booting Windows/macOS or editing Solaar rules by hand.
- You share one mouse and keyboard between several computers and want them to move together.

If you only want hardware settings and do not use Omarchy, use Solaar directly.

## Features

| Feature | What you get | Notes |
| --- | --- | --- |
| Device list and battery | Connection type, online state, battery level in the bar | Bluetooth and supported Logitech receivers |
| Pointer hardware | DPI, SmartShift, wheel direction and resolution, thumb wheel | Only controls the device reports |
| Per-mouse scroll speed | Scroll factor for that mouse only | Applied through Hyprland; touchpads are untouched |
| Pointer acceleration | Optional macOS-style acceleration curve per mouse | Applied at runtime through Hyprland |
| Button remaps | Hardware remaps between supported controls | Stored on the device |
| Software actions | Map a button or directional gesture to a shortcut, or a sequence of up to eight shortcuts, optionally per application | Matches Hyprland window classes exactly; needs the helper running |
| Keyboard | Function-key mode, platform layout, backlight | When exposed by firmware; arbitrary F-row remapping is not guaranteed |
| Profiles | Save and re-apply a snapshot of a device's settings | Local, manual; applied without rollback |
| Easy-Switch host names | View and rename the paired-host labels stored on a device | |
| **Coordinated switching** | Move a group of devices to another computer at once | Channels matched by stored host name, or mapped by hand; mice first, keyboard last |
| **Physical Easy-Switch following** | Pressing the keyboard's channel button moves the rest of the group | Experimental; needs Easy-Switch key reporting or CHANGE_HOST v2; outbound only |

MX-series devices are the primary scope. A supported receiver does not mean every peripheral attached to it is supported. Firmware, connection method, permissions and sleep state all affect which controls appear.

Out of scope today: firmware updates, receiver pairing management, Logitech Flow, cloud sync and the full Smart Actions workflow.

## How it works

```
 Omarchy shell (Quickshell, already running)
 ├── Bar widget + popup panel + settings window   (QML, this plugin)
 └── Service.qml ── starts on demand ──►  mxctl.py serve   (system Python helper)
                                          ├── Solaar's logitech_receiver library ──► HID++ ──► devices
                                          ├── Hyprland IPC socket  (scroll, acceleration, shortcuts)
                                          └── $XDG_RUNTIME_DIR/mx-unison/status.json  ──► UI
```

- **No extra shell or system service.** The UI loads in the Quickshell process Omarchy already runs. There is no systemd unit and nothing runs as root.
- **The helper is a single Python process** (`mxctl.py serve`). It owns all HID++ handles, applies writes one at a time on a single command thread, and publishes a JSON snapshot that the UI watches. The UI sends it commands through private files in the runtime directory.
- **Hardware settings live on the device.** DPI, SmartShift, remaps, function-key mode, backlight and host channels are written to the device and stay there, even with the helper stopped or the device moved to another computer.
- **Software features need the helper running.** Software actions and gestures, pointer acceleration, per-mouse scroll speed and physical Easy-Switch following are applied or listened for live. They work only while the helper runs.

### When the helper runs

| Situation | What runs |
| --- | --- |
| Shell starts, no software features configured | A lightweight sysfs scan (`mxctl.py discover`) every 15 seconds for the bar's device and battery display. The interval is configurable from 10 to 3600 s in the widget settings. No HID++ handles are opened. |
| You hover the bar icon, open the panel or settings, or change anything | The resident helper starts and does a full HID++ read |
| Saved software actions, acceleration, scroll speed or physical follow exist | The resident helper starts with the shell, because those features need it |
| Helper idle | Sleeps on inotify, device and compositor events. Also wakes every 30 s to read battery from sysfs, and every 60 s for a HID++ battery read and heartbeat |
| Shell exits or the plugin is disabled | The helper stops and restores compositor scroll and acceleration defaults |

The resident helper uses little CPU when idle. Memory is dominated by Python and Solaar's library, roughly 100 MB resident on a typical setup. Reducing this is the main goal of the [roadmap](#roadmap).

## Requirements

- **Omarchy 4** with its Quickshell shell and Lua-based Hyprland configuration.
- **System Python** at `/usr/bin/python3`. A virtualenv or version-manager Python usually cannot see the Arch Solaar package, so the plugin deliberately calls the system interpreter.
- **Solaar**, installed with `omarchy pkg add solaar`. Without it MX Unison shows devices and batteries only; every setting and switching feature needs Solaar's `logitech_receiver` library. Solaar's GUI does not need to be running.
- **hidraw access** for your user through Solaar's udev rules (installed with the package).
- Node.js only for development checks.

Do not run the plugin or helper as root. Avoid running other tools that configure or divert the same controls at the same time, for example Solaar rules acting on the same buttons, logiops, or another Options+ replacement.

## Install

Clone the repository into a directory you own, then deploy from its root:

```sh
git clone https://github.com/willspiering/mx-unison.git
cd mx-unison
omarchy pkg add solaar               # if not installed yet
python3 scripts/deploy.py --dry-run  # shows exactly what will be copied
python3 scripts/deploy.py --enable   # copies, rescans plugins, enables the bar widget
```

The deploy script copies an explicit allowlist of runtime files into `~/.config/omarchy/plugins/local.mx-unison/`. It backs up any existing installation first. It does **not** install packages, add keyboard shortcuts, change device settings or install a daemon.

Omarchy plugins run unsandboxed as your user. Review the source before enabling it.

If Omarchy keeps showing old UI after an update, run `omarchy restart shell`. This reloads the whole desktop shell, so do it at a convenient moment. Backups, rollback and the source-versus-install split are covered in [CONTRIBUTING.md](CONTRIBUTING.md).

## Using it

Click the mouse icon in the bar for the quick panel. It shows:

- each device with its battery; click one to choose which device the quick settings apply to;
- **Switch desk to**, one button per computer in your switch group, named after the computers stored on your devices, with the current one highlighted (or **Switch this device to** when no group is set up);
- everyday settings: DPI presets and SmartShift for a mouse, Fn keys and backlight for a keyboard;
- **Settings…** for everything else.

The popup has no sliders and normally needs no scrolling. Arrow keys move between rows, left/right step DPI and backlight presets, and Enter activates. You can also open the full settings window from a terminal or keybinding:

```sh
omarchy-shell shell summon local.mx-unison '{}'
```

The window opens on **Desk**: your devices, and switching the whole group between computers. Pick a device in the sidebar (or on Desk) to open its page. It shows only the sections that device reports: pointer, scroll, thumb wheel, keys, buttons, its own Easy-Switch channels, profiles, and a collapsed **More** for rarely used settings. The sidebar links under the selected device jump to each section. Opening settings from the popup goes straight to that device. Until a device's settings have been read, which can take a few seconds over Bluetooth, its page shows a status line and progress instead.

- Hardware settings apply immediately. There is no global undo.
- Profiles and software actions have their own save and apply controls.
- Switch-group changes, including physical following, save as you make them.
- Scrolling over a slider scrolls the page; it never changes the setting.

If Solaar is missing or your user lacks hidraw permission, the panel offers two buttons. **Install Solaar** opens a terminal running `omarchy pkg add solaar`. **Reload udev** opens a terminal that runs `udevadm control --reload-rules && udevadm trigger` through `sudo`, so you see and approve the command. Neither runs without you clicking it.

## Switching a group of devices

### Set up

1. Pair each device with each computer using its normal Easy-Switch pairing process.
2. In settings, open **Desk** and turn on each device that should move together under **Devices in the group**.
3. Your computers appear under **Switch together**, named after the host names stored on the devices. When a device joins, its channels are matched to those computers by name, so devices that store channels in a different order still line up.
4. If names are missing or differ (for example a receiver keyboard that only knows channel numbers), open **Customize channels** and pick, for each device, the channel it uses for each computer. Each computer must use a different channel on a given device; picking a channel that is already in use swaps the two.
5. Changes save immediately. Use **Switch** next to a computer, or the popup's **Switch desk to** buttons.

Channel numbers may differ between devices. If your laptop is channel 1 on the keyboard but channel 3 on the mouse, the laptop row should list keyboard channel 1 and mouse channel 3. If the stored names suggest a different mapping than the saved one, the page says so and offers **Match channels by name**. Names are only a hint; equal names on two devices do not prove they point at the same computer.

To move a single device, or to rename the channels stored on it, use the **Easy-Switch** section of that device's page.

### What happens when you switch

1. **Preflight.** Every group member must answer a live ping and support `change-host`. Devices already on the target channel are skipped. The target channel must exist and must not be marked unpaired in the latest device snapshot. If any check fails, nothing is switched.
2. **Send.** Mice and other devices switch first. The keyboard switches last, so you keep a keyboard until the end.
3. **Confirm departure.** Switch commands are fire-and-forget, so after each one the helper checks that the device stopped answering. If it is still connected, the command is resent once. If it still stays, switching stops and the keyboard is kept here.
4. **Partial failure.** If a write fails, the remaining writes stop and the error says how many devices were already sent. There is no rollback once a device has left. MX Unison can confirm that a device left, but not that it arrived at the destination.

The active channel is never saved as a reconnect preference. Snapshot pairing data can be stale.

**Switching back** requires MX Unison (or equivalent software) on the computer the devices moved to, or the devices' own channel buttons. Installing this plugin on one computer does not control devices that have moved away.

### Optional keyboard shortcuts

The plugin exposes an IPC command. Check for conflicts first with `omarchy menu keybindings --print`, then add bindings like these to `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + CTRL + ALT + 1", "MX Unison: target 1", "omarchy-shell local.mx-unison switchTogether 1")
o.bind("SUPER + CTRL + ALT + 2", "MX Unison: target 2", "omarchy-shell local.mx-unison switchTogether 2")
o.bind("SUPER + CTRL + ALT + 3", "MX Unison: target 3", "omarchy-shell local.mx-unison switchTogether 3")
```

Back up the file before editing, then validate with `hyprctl reload` and `hyprctl configerrors`. The installer never adds or removes bindings.

### Physical Easy-Switch following (experimental)

With this on, pressing the keyboard's own Easy-Switch button moves the rest of the group to the matching target.

1. Include a keyboard in the group.
2. Turn on **Follow this keyboard's Easy-Switch keys**, shown under that keyboard in **Devices in the group**. It takes effect immediately.

The helper picks one of two ways to notice the key press:

| Mode | Used when | How |
| --- | --- | --- |
| Key reporting | The keyboard's Easy-Switch keys support HID++ *analytics key events* (common on recent MX keyboards with CHANGE_HOST v1) | The helper asks the keyboard to report presses of its three Easy-Switch keys, and only those keys. The keys are not diverted: the keyboard still switches itself, and also reports which key was pressed. |
| Host-change notification | The keyboard supports CHANGE_HOST version 2 | The helper reads the keyboard's host-change notification. |

`switchRuntime.mode` in the runtime snapshot shows the active mode, and `switchRuntime.lastKey` shows the last Easy-Switch key the helper saw.

Limits:

- **This works in one direction only, from this computer outward.** When you press an Easy-Switch key on another computer, this computer can't see the press, and the mouse is no longer connected here to command. To switch back with one key press, the other computer needs its own switching software. Otherwise, press the mouse's own channel button. See [Using several computers](#using-several-computers).
- The keyboard has already started its own switch; the group mapping decides where the other devices go. Pressing the key for the channel you are already on does nothing.
- Group members that are not connected here at that moment (for example a Bluetooth mouse still reconnecting after a trip back) are skipped rather than cancelling the switch. Popup and shortcut switches stay all-or-nothing, so the keyboard is kept here when the group cannot move.
- Key reporting is reset when the keyboard reconnects, so the helper turns it back on when the keyboard returns.
- Events can be missed during startup, reconnection, sleep or a slow HID++ request. On the tested keyboard the report arrived before it dropped its link, and the mouse switched within the same second; other models may differ.
- It is not Logitech's persistent cookie-based device linking.
- Hardware-tested outbound with an MX Mechanical Mini (CHANGE_HOST v1, Bolt, key-reporting mode) and an MX Master 3S (Bluetooth). The CHANGE_HOST v2 mode has synthetic test coverage only. Test every destination before relying on it. It is off by default.

### Using several computers

MX Unison controls devices only while they are connected to the computer it runs on.

- **Leaving this computer:** the switch buttons, shortcuts and physical following all work from here.
- **Coming back:** the other computer has to send the devices back. Today that means MX Unison on another Omarchy machine, or pressing each device's channel button. A small cross-platform companion for macOS and other Linux desktops is on the [roadmap](#roadmap).

## Files, configuration and privacy

| Location | Contents |
| --- | --- |
| Your clone of this repository | Source; make changes here |
| `~/.config/omarchy/plugins/local.mx-unison/` | Deployed copy that Omarchy loads |
| `~/.config/mx-unison/` | Your profiles, actions, pointer and scroll preferences, switch group |
| `$XDG_RUNTIME_DIR/mx-unison/` | Live `status.json` snapshot and command spool (falls back to `/run/user/$UID`) |
| `~/.config/omarchy/shell.json` | Omarchy's plugin and bar configuration |
| `~/.config/hypr/bindings.lua` | Optional shortcuts you add yourself |
| `~/.local/state/mx-unison/backups/` | Deployment backups (or under `$XDG_STATE_HOME`) |

Solaar's library may also record hardware settings in Solaar's own configuration. MX Unison does not replace Solaar's `rules.yaml`, disable other services or modify packaged Omarchy files.

Scroll and acceleration overrides return to the compositor's global defaults when the helper exits normally. If it is killed, run `hyprctl reload` to clear them. The global defaults may differ from per-device overrides you set elsewhere.

Preferences and snapshots can contain device serial numbers, Bluetooth addresses, paired-host names, application classes and shortcuts. Redact them before sharing diagnostics. See [SECURITY.md](SECURITY.md).

## Troubleshooting

| Symptom | What to check |
| --- | --- |
| Device missing | Wake it, check its channel and connection, then refresh. A visible receiver does not prove its peripherals are supported. |
| "Solaar unavailable" | `/usr/bin/python3 -c 'import logitech_receiver'` must succeed. |
| Controls are read-only | Solaar installed? hidraw permissions? Use **Reload udev** or reconnect the device. Never run the shell as root to fix this. |
| Old UI after deploying | `omarchy restart shell` clears QML caches. |
| Switch failed | Read the error before retrying; some devices may already have moved. Confirm every member is paired on the target channel. |
| Physical follow unavailable | Read the message under the follow checkbox. `switchRuntime` in `$XDG_RUNTIME_DIR/mx-unison/status.json` shows the mode and the last Easy-Switch key seen. |
| Scroll or acceleration stuck after a crash | `hyprctl reload`. |

## Limitations

- **Hardware validation is incomplete.** Discovery, feature loading, the settings window, an outbound shortcut switch and outbound physical following (key-reporting mode) have worked on one MX Master 3S + MX Mechanical Mini setup. The return direction, partial failures and CHANGE_HOST v2 following are untested on hardware. Synthetic tests do not prove compatibility with a given model, firmware or transport.
- **Switching is not atomic.** See [What happens when you switch](#what-happens-when-you-switch).
- **Profiles** have global names. Filtering by device kind does not prove cross-model compatibility, and settings are applied in sequence without rollback.
- **Discovery** mainly targets MX-related device names. Receiver support is broader than proven peripheral support.
- **Translation:** new strings use the `i18n/` catalog; much of the inherited interface is still English-only.

## Uninstall

```sh
omarchy plugin disable local.mx-unison
omarchy plugin remove local.mx-unison
```

Back up any edits you made to the installed copy first, and remove any shortcuts you added. Settings stored on the devices, Solaar's configuration, `~/.config/mx-unison/` and deployment backups remain. Uninstalling is not a factory reset.

## Roadmap

- Validate coordinated switching and physical following on real hardware, both directions, and publish a compatibility table.
- Run the helper only while it is needed: exit after configuration when no software feature requires a listener.
- Explore a native (Rust) helper to cut memory use and startup time. See [docs/rust-plan.md](docs/rust-plan.md).
- A small cross-platform companion so other computers (macOS, other Linux desktops) can send the group back with one key press.

Issues and pull requests are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md). Hardware reports are especially useful. Include model, firmware, connection type and steps, but no serial numbers or host names.

## Development

```sh
./scripts/check.sh   # Python unit tests, JavaScript model checks, whitespace
```

The suite covers configuration validation, switch ordering and channel mapping, unpaired destinations, partial failures, notification filtering, unsafe text, action lifecycle, pointer behavior and scroll factors, all with synthetic data and mocked device APIs.

- [CONTRIBUTING.md](CONTRIBUTING.md): Git workflow, checks, hardware test checklist, deployment and rollback.
- [docs/architecture.md](docs/architecture.md): module responsibilities, runtime and validation gaps.
- [CHANGELOG.md](CHANGELOG.md): changes from the inherited base.

## Credits and license

GPL-2.0-or-later; see [LICENSE](LICENSE).

MX Unison is a fork of [Zach Wilke's MX Control](https://github.com/zachwilke/omarchy-mxcontrol), starting at commit `0968d77124ed72b207035e5f4f7b70509822a3d6`. Original copyright notices and history are retained. [OmaOptions](https://github.com/andreinita21/omaoptions) was reviewed as a reference; its installer is not used.

Device access builds on [Solaar](https://github.com/pwr-Solaar/Solaar). The physical-follow listener was informed by [Solaar's Enhanced Easy-Switch proposal](https://github.com/pwr-Solaar/Solaar/pull/3339) and its [discussion](https://github.com/pwr-Solaar/Solaar/issues/3228); it does not include the complete proposed linking implementation.

MX Unison is an independent project and is not affiliated with or endorsed by Logitech. Logitech, MX, Logi Bolt, Unifying, Easy-Switch and Flow are trademarks of Logitech.
