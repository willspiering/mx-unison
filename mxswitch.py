# SPDX-License-Identifier: GPL-2.0-or-later
"""Explicit per-device host mappings; optional CHANGE_HOST v2 observation.

No network, no key logging, no keyboard diversion. Notification handles are
separate from Solaar's command handles and read only by the helper main thread.
"""
import json
import os
import stat
import time


def empty():
    return {"version": 1, "keyboard": "", "follow": False, "members": {}}


def validate(raw):
    if not isinstance(raw, dict) or raw.get("version") != 1:
        raise ValueError("Unsupported switch configuration")
    members = raw.get("members", {})
    keyboard = raw.get("keyboard", "")
    if not isinstance(keyboard, str) or len(keyboard) > 128 or any(c in keyboard for c in '<>\x00'):
        raise ValueError("Invalid keyboard identity")
    if not isinstance(raw.get("follow", False), bool) or not isinstance(members, dict) or len(members) > 16:
        raise ValueError("Invalid switch group")
    clean = empty()
    clean.update(keyboard=keyboard, follow=raw.get("follow", False))
    for did, channels in members.items():
        if not isinstance(did, str) or not did or len(did) > 128 or any(c in did for c in '<>\x00'):
            raise ValueError("Invalid device identity")
        if not isinstance(channels, list) or len(channels) != 3 or any(type(c) is not int or c not in (0, 1, 2) for c in channels):
            raise ValueError("Each device needs three channel mappings")
        if len(set(channels)) != 3:
            raise ValueError("Map each target to a different device channel")
        clean["members"][did] = channels[:]
    if clean["follow"] and keyboard not in clean["members"]:
        raise ValueError("Include the source keyboard in the group before enabling follow")
    return clean


def load(path):
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    except FileNotFoundError:
        return empty()
    try:
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            raise ValueError("Switch config must be a regular file")
        raw = os.read(fd, 16385)
        if len(raw) > 16384:
            raise ValueError("Switch config exceeds size limit")
        return validate(json.loads(raw))
    finally:
        os.close(fd)


def prepare(config, devices, identity, online, setting_for, target, source="", hosts_for=None):
    """Preflight every member before changing any device. Targets are 1..3."""
    config = validate(config)
    if type(target) is not int or target not in (1, 2, 3):
        raise ValueError("Choose target 1, 2, or 3")
    if not config["members"]:
        raise ValueError("Add devices to the switch group first")
    available = {identity(d): d for d in devices}
    work = []
    for did, channels in config["members"].items():
        if did == source:  # physical keyboard already initiated its own switch
            continue
        dev = available.get(did)
        if dev is None or not online(dev):
            raise ValueError("A grouped device is offline; nothing was switched")
        setting = setting_for(dev)
        if setting is None:
            raise ValueError("A grouped device does not support host switching")
        channel = channels[target - 1]
        hosts = hosts_for(dev) if hosts_for else []
        if any(h.get("index") == channel and h.get("paired") is False for h in hosts):
            raise ValueError("A grouped device is not paired on the target channel; nothing was switched")
        if channel not in [int(c) for c in setting.choices]:
            raise ValueError("A target channel is unavailable; nothing was switched")
        work.append((did, dev, setting, channel))
    # Keep keyboard available until all mouse/other commands have been sent.
    work.sort(key=lambda row: ("key" in str(getattr(row[1], "kind", "")).lower() or "key" in str(getattr(row[1], "name", "")).lower(), row[0]))
    return work


def execute(work):
    sent = []
    for did, dev, setting, channel in work:
        try:
            # Never use cached current-host state to suppress a switch, and
            # never persist an active channel that could switch on reconnect.
            result = setting.write(channel, save=False)
            if result is None or result is False:
                raise RuntimeError("Device rejected the switch command")
            sent.append(did)
        except Exception as exc:
            raise RuntimeError(f"Switch stopped after {len(sent)} command(s); check device channels. {exc}") from exc
    return {"sent": sent, "message": "Switch commands sent; destination connection cannot be verified here", "ts": int(time.time())}


class Follower:
    """Observe only the configured keyboard's CHANGE_HOST v2 event."""
    def __init__(self):
        self.fd = None
        self.key = None
        self.feature = None
        self.number = None
        self.error = ""
        self.last_event = None
        self.last_time = 0

    def close(self):
        if self.fd is not None:
            os.close(self.fd)
        self.fd = None
        self.key = None

    def sync(self, config, devices, identity):
        from logitech_receiver.hidpp20_constants import SupportedFeature
        key = config["keyboard"] if config["follow"] else ""
        dev = next((d for d in devices if identity(d) == key), None)
        path = (getattr(dev, "path", None) or getattr(getattr(dev, "receiver", None), "path", None)) if dev else None
        token = (key, path, id(dev)) if key and dev else None
        if self.fd is not None and self.key == token:
            return
        self.close()
        self.error = ""
        if not key:
            return
        if dev is None:
            self.error = "Source keyboard is offline"
            return
        try:
            feature = dev.features[SupportedFeature.CHANGE_HOST]
            if not feature or dev.features.get_feature_version(SupportedFeature.CHANGE_HOST) < 2:
                raise ValueError("Physical Easy-Switch following requires CHANGE_HOST version 2; use a shortcut on this keyboard")
            self.fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_CLOEXEC)
            self.key, self.feature, self.number = token, int(feature), int(dev.number)
        except Exception as exc:
            self.error = str(exc)[:300]

    def poll(self, config):
        if self.fd is None:
            return None
        try:
            for _ in range(128):  # bounded drain; discard unrelated reports
                try:
                    raw = os.read(self.fd, 64)
                except BlockingIOError:
                    return None
                if not raw:
                    raise OSError("Keyboard disconnected")
                if len(raw) < 6 or raw[0] not in (0x10, 0x11, 0x21):
                    continue
                if raw[1] != self.number or raw[2] != self.feature or raw[3] != 0:
                    continue
                old, new = raw[4:6]
                if old not in (0, 1, 2) or new not in (0, 1, 2) or old == new:
                    continue
                now = time.monotonic()
                if self.last_event == (old, new) and now - self.last_time < 1:
                    continue
                self.last_event, self.last_time = (old, new), now
                mapping = config["members"].get(config["keyboard"], [])
                if new in mapping:
                    return mapping.index(new) + 1
        except OSError as exc:
            self.close()
            self.error = str(exc)[:300]
        return None

    def status(self):
        return {"listening": self.fd is not None, "error": self.error}
