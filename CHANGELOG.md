# Changelog

## Unreleased

- Rewrote the README around what the plugin does and who it is for, including when the helper runs and which features need it resident.
- Added a phased plan for a leaner, possibly Rust-based helper (`docs/rust-plan.md`).
- Physical Easy-Switch following now works on keyboards with CHANGE_HOST v1 whose Easy-Switch keys support HID++ analytics key reporting. Reporting is enabled for those three keys only, re-enabled when the keyboard reconnects and cleared when following stops. Hardware validation is pending.
- Group switching now confirms that each device actually left after its CHANGE_HOST command, resends once if it did not, and stops before the keyboard if a device stays. Solaar sends this command without a reply, so its success result alone proved nothing.
- Fixed devices that reconnect (wake from sleep, return from another host) being left unmanaged. Reconnects are detected by kernel HID instance even when the `hidrawN` name is reused, replaced handles are closed, and devices that fail to open right after a reconnect (before udev grants access) are retried with backoff.
- Group switch preflight pings every member instead of trusting a cached online flag.
- Redesigned the bar popup: devices with battery, "Switch desk to" buttons named after your computers, everyday settings only, no sliders.
- Sliders no longer change settings (and write the device) when the page is scrolled over them; stock combo boxes and sliders ignore the wheel.
- Switch-group edits save immediately; Save/Revert removed.
- Physical following re-arms after the keyboard returns: receiver connection notifications are enabled, receiver devices that Solaar marked offline are pinged again, and a heartbeat check repairs reporting.
- Switching skips devices already on the target; each attempt is logged (kinds and outcomes only) in the runtime directory.
- Physical following moves the members that are here and skips ones still reconnecting, instead of cancelling; manual switches remain all-or-nothing.
- Arriving devices show "Connecting…" instead of a permissions warning; reopen retries start at 0.5 s, are cheap, and continue while a device is listed.
- Replaced device-like identifiers in test fixtures with synthetic values.
- Rebuilt the settings window in a minimal terminal style. The sidebar lists **Desk** and each device (no device dropdown); a device page shows its sections in order, with inline help, jump links and a status/progress view while its settings are still being read. Rare settings sit under **More**.
- **Desk** shows one row per computer, named from the devices' stored host names, each with its own Switch button. Group membership uses whole-row toggles. A joining device's channels are matched by host name, with manual mapping behind **Customize channels**. A device's own channel buttons and channel renaming are on its page.
- Fixed settings dropdowns that stopped following the device after being used once.

## 0.1.0 — initial MX Unison baseline

Derived from MX Control commit `0968d77124ed72b207035e5f4f7b70509822a3d6`.

- Introduced the MX Unison identity and separate local preference/runtime paths.
- Added coordinated device groups with explicit per-device channel mappings, preflight checks, known-unpaired-channel rejection, mouse-before-keyboard ordering and partial-failure reporting.
- Added an opt-in experimental CHANGE_HOST v2 physical keyboard-follow listener. End-to-end hardware validation remains pending.
- Added per-mouse Hyprland scroll-factor controls and validation.
- Used system Python explicitly to access the distribution-installed Solaar library; disabled bytecode writes from helper invocations.
- Added translation catalogs for the new group/scroll interface and respected animation preferences in inherited panel motion.
- Added switching and scroll regression tests, public documentation, deployment tooling and a local Git workflow.

Inherited capabilities include device settings, profiles, software shortcut actions, gestures and pointer acceleration. Their availability depends on reported device features. This release does not claim complete Options+ parity or verified physical-button following.
