# Working on MX Unison

Read README.md, CONTRIBUTING.md and docs/architecture.md before changing behavior.

- Work in this source checkout. The installed Omarchy plugin is a separate copy; use scripts/deploy.py to deploy reviewed changes only when requested.
- Never commit real device preferences, serials, Bluetooth addresses, host names, local absolute paths, runtime snapshots or desktop screenshots. Use synthetic fixtures.
- Preserve upstream copyright notices and GPL-2.0-or-later licensing. The upstream remote is for reference; publish only to the maintainer's own origin when authorized.
- Keep user preferences outside the checkout. Do not change packaged Omarchy source or automatically install system dependencies.
- Keep HID++ writes serialized on the helper's command thread. Group switching is non-atomic; preserve preflight checks, keyboard-last ordering and explicit partial-failure reporting.
- Do not trigger real host switches in automated checks. Hardware operations and software input injection require deliberate manual validation.
- Use plain-text QML sinks for dynamic text, sanitize shared tooltip inputs, use Omarchy motion/theme primitives, and catalog new UI strings under i18n/.
- Run ./scripts/check.sh after code changes. Socket-based tests need a normal local environment. Validate deployment changes with --dry-run and isolated temporary HOME tests.
- Document current limitations accurately. Synthetic tests do not prove hardware compatibility or physical Easy-Switch support. Historical upstream reviews are not current measurements.
