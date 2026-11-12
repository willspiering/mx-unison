# MX Unison

A local Logitech device controller for the Omarchy shell, with coordinated host switching for compatible mice and keyboards. Configure supported device settings, choose a group, and move that group to another paired computer with a button or keyboard shortcut.

MX Unison runs inside Omarchy’s existing Quickshell process. It uses Solaar’s HID++ library for device access and Hyprland for local software actions. It has no AI features, cloud account, telemetry, or periodic Internet access.

**Status:** early development, version 0.1.0. Coordinated switching is implemented and unit-tested; end-to-end host switching still needs hardware validation. Physical Easy-Switch following is experimental and requires compatible firmware. This is not complete Logi Options+ feature parity.

## Features and compatibility

| Feature | Availability |
| --- | --- |
| Device discovery, connection and battery status | Bluetooth and supported Logitech receivers; device support depends on Solaar and discovery filters |
| DPI, SmartShift, wheel direction and resolution, thumb wheel | When reported by the device |
| Per-mouse scroll speed | Local Hyprland scroll factor; does not change touchpad settings |
| Pointer acceleration | Optional local macOS-style acceleration curve |
| Hardware remaps, software shortcuts and directional gestures | Supported controls only; temporary diversion required for software actions |
| App-specific actions and short shortcut sequences | Exact Hyprland class matching; up to eight shortcut steps |
| Keyboard function-key mode, platform layout and backlight | When exposed by firmware; arbitrary F-row remapping is not guaranteed |
| Local profiles | Manual snapshots; compatibility and partial-application caveats apply |
| Coordinated host switching | Explicit per-device mappings; mice before keyboards |
| Physical Easy-Switch following | Experimental CHANGE_HOST v2 notification listener; v1 is not supported by this listener |

MX-series mice and keyboards are the primary scope. A supported Bolt, Unifying, or other receiver does not imply support for every attached Logitech peripheral. Firmware, connection method, permissions and device sleep state affect available controls. Firmware updates, receiver pairing management, Flow, cloud synchronization and the full Smart Actions workflow are outside the current implementation.

## Requirements

- Omarchy 4 with its Quickshell shell and Lua-based Hyprland configuration.
- System Python at `/usr/bin/python3`.
- Solaar, installed with `omarchy pkg add solaar`.
- User access to the relevant `/dev/hidraw*` nodes through Solaar’s udev rules.
- Node.js for development checks, not normal plugin use.

System Python is intentional: a virtual environment or version-manager interpreter may not see the Arch Solaar package. Do not run the plugin or its helper as root. If permissions are missing after installation, reconnect the receiver/device or reload the udev rules using the normal system administration tools. Avoid competing tools that configure or divert the same controls.

## Install from a checkout

Clone this repository into a directory you own, then run from its root:

```sh
omarchy pkg add solaar
python3 scripts/deploy.py --dry-run
python3 scripts/deploy.py --enable
```

The deployment script copies an explicit set of runtime files into `~/.config/omarchy/plugins/local.mx-unison/`. It backs up an existing installation before replacing files. It does not install packages, add shortcuts, change device settings, or install an extra daemon. Review plugin source before enabling it: Omarchy plugins run unsandboxed as your user.

If Omarchy retains old QML components after an update, run `omarchy restart shell`. This reloads the entire desktop shell, so do it when convenient. See [development and deployment](CONTRIBUTING.md) for backups, rollback and source-versus-installation details.

## Open and configure

Click the plugin’s mouse icon in the bar, then **All settings**, or run:

```sh
omarchy-shell shell summon local.mx-unison '{}'
```

Select a device to see the settings it reports. Changes to supported hardware settings are generally applied immediately; the switch-group editor has an explicit **Save group** button. Profiles and software actions have their own save/apply controls. There is no global undo for device settings.

### Switch a group together

1. Pair each device with each destination using its normal pairing process.
2. Open **Easy Switch** and select the devices to move together.
3. Map each logical **Target 1/2/3** to the paired channel **1/2/3** on each device. Channel assignments may differ between devices.
4. Save the group and use **Switch to 1/2/3**.

For example, target 1 can refer to channel 1 on a keyboard and channel 3 on a mouse. Map the same destination computer, rather than assuming matching channel numbers always mean matching hosts.

Every group member must be available and expose `change-host`. The helper preflights members and their channel choices before sending commands, and rejects channels marked unpaired in its latest device snapshot. Snapshot state may be stale. Mice switch first and keyboards last. If a write fails, remaining writes stop and the error reports the number already sent. There is no rollback once a device leaves this computer, and command delivery does not verify arrival at the destination. Current channels are never saved as reconnect preferences.

Switching back requires equivalent software on the computer the devices are leaving, or their physical channel controls. Installing this plugin on one computer does not control devices after they have moved away.

### Optional keyboard shortcuts

Add these only after checking existing bindings for conflicts with `omarchy menu keybindings --print`:

```lua
o.bind("SUPER + CTRL + ALT + 1", "MX Unison: target 1", "omarchy-shell local.mx-unison switchTogether 1")
o.bind("SUPER + CTRL + ALT + 2", "MX Unison: target 2", "omarchy-shell local.mx-unison switchTogether 2")
o.bind("SUPER + CTRL + ALT + 3", "MX Unison: target 3", "omarchy-shell local.mx-unison switchTogether 3")
```

These belong in `~/.config/hypr/bindings.lua`. Back it up before editing, then validate with `hyprctl reload` and `hyprctl configerrors`. The installer does not add or remove bindings.

### Physical Easy-Switch following

Select a keyboard included in the group, enable **Follow this keyboard’s physical Easy-Switch buttons**, and save. The listener requires the keyboard to expose CHANGE_HOST feature version 2. Version 1 devices can still use coordinated switching through plugin buttons and shortcuts, but their physical channel buttons are not followed by this implementation.

The helper observes that keyboard’s host-change notifications through a separate read handle. It does not intercept ordinary typing or divert the Easy-Switch buttons. The keyboard has already initiated its own switch; the group mapping determines where the other devices should go.

This is notification-based following, not Logitech’s persistent cookie-based device linking. Events can be missed during startup, reconnection, sleep, or a slow HID++ request. The listener has synthetic regression coverage but no end-to-end hardware validation. Test every destination before relying on it. Following starts disabled on a fresh installation.

## Configuration and privacy

| Location | Purpose |
| --- | --- |
| Your repository checkout | Version-controlled source; work here |
| `~/.config/omarchy/plugins/local.mx-unison/` | Deployed copy loaded by Omarchy |
| `~/.config/mx-unison/` | Local profiles, actions, pointer/scroll preferences and switch mappings |
| `$XDG_RUNTIME_DIR/mx-unison/status.json` | Live device snapshot; fallback runtime root is `/run/user/$UID` |
| `~/.config/omarchy/shell.json` | Omarchy plugin and bar configuration |
| `~/.config/hypr/bindings.lua` | Optional user-managed shortcuts |
| `~/.local/state/mx-unison/backups/` | Deployment backups, or the corresponding `$XDG_STATE_HOME` location |

Solaar’s library may also save hardware preferences in its existing configuration. The plugin does not replace Solaar’s `rules.yaml`, disable other services, or modify packaged Omarchy files. Local scroll and acceleration overrides are restored to global compositor defaults on orderly helper exit; forced termination can require a compositor reload. These defaults may differ from prior per-device custom overrides.

Preferences and snapshots can contain serial numbers, device addresses, paired-host names, application classes and shortcut assignments. Keep them outside this repository and redact diagnostic output before sharing. See [security and privacy](SECURITY.md).

## Troubleshooting and removal

- **Device missing:** wake it, check its channel/connection, and refresh. A receiver being visible does not prove its peripherals are supported.
- **Solaar unavailable:** confirm `/usr/bin/python3 -c 'import logitech_receiver'` succeeds.
- **Read-only controls:** check Solaar installation and hidraw permissions. Do not solve this by running the shell as root.
- **Old UI after deployment:** restart the Omarchy shell to clear QML component caches.
- **Switch failed:** inspect the error before retrying; some devices may already have moved. Confirm every group member’s channel pairing.
- **Physical follow unavailable:** check `changeHostVersion` in the local runtime snapshot. This listener requires version 2.

Disable with `omarchy plugin disable local.mx-unison`. Remove with `omarchy plugin remove local.mx-unison` after backing up any installation-only edits. Remove optional bindings separately. Device onboard settings, Solaar configuration, local preferences and deployment backups remain; removal is not a factory reset.

## Development and Git workflow

See [CONTRIBUTING.md](CONTRIBUTING.md) for the local Git workflow, checks, deployment and rollback. See [architecture](docs/architecture.md) for module responsibilities, runtime behavior and validation gaps. The [changelog](CHANGELOG.md) records changes from the inherited base.

```sh
./scripts/check.sh
```

The automated suite covers configuration validation, switch order and channel mapping, known unpaired destinations, partial failures, notification filtering, unsafe text, action lifecycle, pointer behavior and scroll factors. Tests do not establish hardware compatibility. Group/scroll strings use an English translation catalog with Omarchy fallback; much of the inherited interface remains English.

## Credits and license

GPL-2.0-or-later; see [LICENSE](LICENSE). MX Unison is derived from [Zach Wilke’s MX Control](https://github.com/zachwilke/omarchy-mxcontrol), starting at commit `0968d77124ed72b207035e5f4f7b70509822a3d6`. Original copyright notices and inherited history are retained. [OmaOptions](https://github.com/andreinita21/omaoptions) was reviewed as a reference; its installer is not used.

Device access builds on [Solaar](https://github.com/pwr-Solaar/Solaar). The experimental physical-follow listener was informed by [Solaar’s Enhanced Easy-Switch proposal](https://github.com/pwr-Solaar/Solaar/pull/3339) and [discussion](https://github.com/pwr-Solaar/Solaar/issues/3228); it does not incorporate the complete proposed linking implementation. MX Unison is an independent project and is not affiliated with Logitech.
