# Plan: a leaner helper, possibly in Rust

Status: proposal. Nothing here is implemented.

## Goal

MX Unison should cost almost nothing when you are not configuring devices. Hardware settings already persist on the device. Only a few features need a live process:

| Needs a resident process | Does not |
| --- | --- |
| Software actions and gestures (diverted button events → shortcuts) | DPI, SmartShift, wheel and thumb-wheel settings |
| Physical Easy-Switch following (CHANGE_HOST v2 notifications) | Hardware button remaps |
| Pointer acceleration and per-mouse scroll speed (re-applied after `hyprctl reload`) | Keyboard Fn mode, layout, backlight |
| | Host renames, one-shot group switches, profiles |

## Where things stand today

- `mxctl.py serve` is one Python process. It stays resident from first use until the shell exits. A typical setup uses about 100 MB RSS and near-zero idle CPU.
- Before the helper starts, the bar runs `mxctl.py discover` (a sysfs scan) every 15 s. That is a fresh Python start each time.
- The UI talks to the helper only through `status.json` and the command spool in `$XDG_RUNTIME_DIR/mx-unison/`. This file contract is the seam that lets the helper be replaced without rewriting the QML.

## What ties the project to Python

Only one thing: **Solaar's `logitech_receiver` library.** It supplies:

- HID++ 1.0/2.0 transport, receiver and device enumeration, and feature discovery.
- Setting templates: DPI, SmartShift, wheels, Fn mode, backlight, CHANGE_HOST, REPROG_CONTROLS (remap and divert), gestures, host names.
- Years of per-device quirks and firmware workarounds.

Everything else the helper does uses the Python standard library: hidraw/sysfs scanning, inotify, Hyprland socket IPC, JSON, switch validation and ordering, scroll and acceleration curves. All of it ports easily.

Reimplementing the settings MX Unison exposes in Rust is feasible. Matching Solaar's breadth of device quirks is not a short project. Any logic ported from Solaar stays GPL-2.0-or-later, which this project already uses.

## Phases

Each phase ships on its own and is measured before the next starts.

### Phase 0: measure

Record a baseline on real hardware:

- Idle RSS.
- Time from opening the panel to the first full snapshot.
- Idle wakeups per minute.
- Discover-poll cost.

Add a `scripts/bench` helper that records these without sending device writes.

### Phase 1: run only when needed (Python, small change)

- Exit `serve` after a short idle period when no software action, acceleration, scroll override or follow listener is configured. The UI already restarts it on demand.
- Replace the 15-second `discover` subprocess with event-driven updates where possible: an inotify watch on `/sys/class/hidraw` and Quickshell's Bluetooth model. Otherwise, lengthen the default interval.
- Import Solaar lazily and only for the devices being opened.

Expected result: no resident process for users who only change hardware settings. This phase is likely the biggest win for the least risk.

### Phase 2: native resident listener (Rust)

A small Rust daemon (for example `mxunisond`) takes over only the parts that must stay resident:

- Minimal HID++ 2.0: root/feature-set lookup, REPROG_CONTROLS_V4 divert and notifications, gesture events, and CHANGE_HOST read/write/notify.
- Hyprland socket IPC for shortcut dispatch, scroll factor and acceleration, plus `configreloaded` handling.
- Group switching: preflight, mouse-first/keyboard-last ordering, partial-failure reporting. Port the existing tests one for one.
- The same `status.json` and command-spool contract, so the QML stays unchanged.

Python and Solaar remain a short-lived configuration tool, started when the settings window opens and exited when it closes. Target: low single-digit MB RSS for the resident part.

### Phase 3 (optional): full native helper

Port the remaining settings and drop the Solaar dependency, but only if Phase 2 holds up on real hardware and there is demand. Until then, keeping Solaar gives broader device support with less risk.

## Invariants for any rewrite

These come from `AGENTS.md` and apply to any implementation:

- HID++ writes stay serialized on one command owner.
- Group switching keeps preflight checks, keyboard-last ordering and explicit partial-failure reporting.
- Automated tests never trigger a real host switch.
- No network access, no root, and no automatic installation of system packages.
- Preferences stay in `~/.config/mx-unison/` with the same schema, or a documented migration.

## Companion for other computers

Physical following only works outward: once the devices leave, this computer can no longer reach them. Switching back with one key press needs software on every computer in the group. A Rust listener from Phase 2 is a good basis for a small cross-platform companion (macOS through IOKit/hidapi, generic Linux through hidraw). It would contain only key reporting, the group mapping and CHANGE_HOST writes, with no UI beyond a config file.

## Open questions

- Is there a maintained Rust HID++ crate worth building on, or should we write a minimal implementation?
- How should the QML find and launch a native binary: build at deploy time with `cargo`, or ship a prebuilt binary through an AUR/Arch package?
- Should a configuration-only Python session share the HID++ handles with the Rust listener, or hand them over? Two openers of the same hidraw node need care.
