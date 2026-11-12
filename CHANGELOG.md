# Changelog

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
