# SPDX-License-Identifier: GPL-2.0-or-later
"""Per-mouse scroll factors, restored on orderly exit; no config file edits."""
import json
import math
from mxpointer import HYPR_NAME_RE, evdev_names_for_hidraw, match_hypr_names


def factor(value):
    if isinstance(value, bool):
        raise ValueError('Invalid scroll speed')
    n = float(value)
    if not math.isfinite(n) or not 0.25 <= n <= 4:
        raise ValueError('Scroll speed must be between 0.25 and 4')
    return n


def lua(name, value):
    if not HYPR_NAME_RE.fullmatch(name):
        raise ValueError('Invalid device name')
    scalar = str(factor(value)) if value is not None else 'hl.get_config("input.scroll_factor") or 1'
    return 'hl.device({ name = %s, scroll_factor = %s })' % (json.dumps(name), scalar)


class ScrollRuntime:
    def __init__(self, pointer):
        self.pointer = pointer
        self.applied = {}
        self.error = ''
        self.fingerprint = None

    def sync(self, devices, prefs, force=False):
        fingerprint = (tuple((d.get('id'), d.get('path')) for d in devices), tuple(sorted(prefs.items())))
        if not force and fingerprint == self.fingerprint:
            return False
        before = (dict(self.applied), self.error)
        self.fingerprint = fingerprint
        try:
            wanted = {}
            if prefs:
                names = self.pointer.hypr_mice()
                for dev in devices:
                    if dev.get('kind') != 'mouse' or dev.get('id') not in prefs:
                        continue
                    for name in match_hypr_names(names, evdev_names_for_hidraw(dev.get('path'))):
                        wanted[name] = factor(prefs[dev['id']])
            for name in list(self.applied):
                if name not in wanted:
                    self.pointer._send(lua(name, None))
                    del self.applied[name]
            for name, speed in wanted.items():
                if force or self.applied.get(name) != speed:
                    self.pointer._send(lua(name, speed))
                    self.applied[name] = speed
            self.error = '' if not prefs or wanted else 'Mouse input is not available for scroll speed yet'
            if self.applied:
                self.pointer.events.connect()
        except Exception as exc:
            self.error = str(exc)[:300]
            self.fingerprint = None
        return before != (dict(self.applied), self.error)

    def shutdown(self):
        for name in self.applied:
            try:
                self.pointer._send(lua(name, None))
            except Exception:
                pass
