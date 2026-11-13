# SPDX-License-Identifier: GPL-2.0-or-later
"""Explicit per-device host mappings; optional physical Easy-Switch following.

No network, no keyboard diversion, and no key logging: press reporting is
enabled only for the three Easy-Switch keys of the configured keyboard. Notification handles are
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


VERIFY_DELAY = 0.8     # let the device act on CHANGE_HOST before checking
VERIFY_CHECKS = 3      # consecutive successful pings needed to call it "stayed"
VERIFY_INTERVAL = 0.7


def _stayed(dev, present, sleep):
    """True when the device still answers after a switch command."""
    sleep(VERIFY_DELAY)
    for attempt in range(VERIFY_CHECKS):
        if not present(dev):
            return False
        if attempt < VERIFY_CHECKS - 1:
            sleep(VERIFY_INTERVAL)
    return True


SWITCH_ATTEMPTS = 3


class SwitchError(RuntimeError):
    """A group switch stopped part-way; ``steps`` records what happened."""
    def __init__(self, message, steps):
        super().__init__(message)
        self.steps = steps


def device_kind(dev):
    kind = str(getattr(dev, "kind", "") or "").lower()
    return kind if kind in ("mouse", "keyboard", "trackball", "touchpad") else "device"


def execute(work, present=None, sleep=time.sleep):
    """Send switch commands in order.

    CHANGE_HOST is sent without a reply, so a successful write does not prove
    the device acted on it. With ``present`` (a liveness check), each device
    must stop answering; otherwise the command is resent, and if the device
    still stays the remaining devices are not switched.
    """
    sent = []
    retried = []
    steps = []
    for did, dev, setting, channel in work:
        step = {"kind": device_kind(dev), "channel": channel + 1, "attempts": 0, "outcome": ""}
        steps.append(step)
        try:
            # Never use cached current-host state to suppress a switch, and
            # never persist an active channel that could switch on reconnect.
            for attempt in range(SWITCH_ATTEMPTS if present else 1):
                step["attempts"] = attempt + 1
                result = setting.write(channel, save=False)
                if result is None or result is False:
                    raise RuntimeError(f"The {step['kind']} rejected the switch command")
                if not present or not _stayed(dev, present, sleep):
                    break
                if attempt == 0:
                    retried.append(did)
            else:
                step["outcome"] = "stayed"
                raise RuntimeError(f"The {step['kind']} ignored the switch command and is still connected here; remaining devices were not switched")
            step["outcome"] = "left" if present else "sent"
            sent.append(did)
        except Exception as exc:
            step["outcome"] = step["outcome"] or "error"
            raise SwitchError(f"Switch stopped after {len(sent)} command(s). {exc}", steps) from exc
    message = "Switch commands sent; destination connection cannot be verified here"
    if present:
        message = "Devices left this computer; arrival at the destination cannot be verified here"
    return {"sent": sent, "retried": retried, "steps": steps, "message": message, "ts": int(time.time())}


# REPROG_CONTROLS_V4 control IDs for the Easy-Switch keys and the flags used to
# ask for press reports without diverting them.
HOST_SWITCH_CIDS = (0x00D1, 0x00D2, 0x00D3)
KEY_FLAG_ANALYTICS = 0x400
SET_CID_REPORTING = 0x30
GET_CID_REPORTING = 0x20
ANALYTICS_ON = 0x03   # flags byte 2: analyticsKeyEvt + valid bit
ANALYTICS_OFF = 0x02  # valid bit only: clear reporting
REARM_DELAY = 5.0
VERIFY_EVERY = 300.0  # seconds between heartbeat checks of key reporting


def _bits(flags):
    return int(getattr(flags, "value", flags) or 0)


def host_key_reporting(keys):
    """Return the host-switch CIDs whose press the keyboard can report."""
    found = {}
    for key in keys or ():
        try:
            cid = int(key.key)
        except (TypeError, ValueError, AttributeError):
            continue
        if cid in HOST_SWITCH_CIDS and _bits(key.flags) & KEY_FLAG_ANALYTICS:
            found[cid] = key
    return [cid for cid in HOST_SWITCH_CIDS if cid in found]


def parse_key_events(data):
    """Channels (0..2) of host-switch keys pressed in an analyticsKeyEvents payload.

    The payload holds up to five (CID u16, event u8) entries; bit 0 of the
    event byte marks a press.
    """
    channels = []
    for i in range(0, len(data) - 2, 3):
        cid = (data[i] << 8) | data[i + 1]
        if cid in HOST_SWITCH_CIDS and data[i + 2] & 0x01:
            channels.append(cid - HOST_SWITCH_CIDS[0])
    return channels


class Follower:
    """Observe the configured keyboard's Easy-Switch activity.

    Two modes, chosen per keyboard:
    - ``change-host-v2``: the CHANGE_HOST v2 host-change notification.
    - ``key-report``: REPROG_CONTROLS_V4 analytics reports for the Easy-Switch
      keys. The keys are not diverted; the keyboard still switches itself and
      only tells us which key was pressed. Used for CHANGE_HOST v1 keyboards.

    Reporting is enabled from the helper's command thread (``sync``) and
    cleared again on ``close``.
    """
    def __init__(self):
        self.fd = None
        self.key = None
        self.feature = None
        self.number = None
        self.mode = ""
        self.dev = None
        self.cids = []
        self.current_host = None
        self.rearm_at = None
        self.away = False
        self.verified_at = 0.0
        self.error = ""
        self.last_event = None
        self.last_time = 0
        self.last_key = None

    def _set_reporting(self, value):
        from logitech_receiver.hidpp20_constants import SupportedFeature
        for cid in self.cids:
            self.dev.feature_request(SupportedFeature.REPROG_CONTROLS_V4, SET_CID_REPORTING, cid >> 8, cid & 0xFF, 0, 0, 0, value)

    def _arm(self):
        """Enable key reporting and verify it stuck. Command thread only."""
        from logitech_receiver.hidpp20_constants import SupportedFeature
        self._set_reporting(ANALYTICS_ON)
        for cid in self.cids:
            reply = self.dev.feature_request(SupportedFeature.REPROG_CONTROLS_V4, GET_CID_REPORTING, cid >> 8, cid & 0xFF)
            if not reply or len(reply) < 6 or not reply[5] & 0x01:
                raise ValueError("Keyboard did not enable Easy-Switch key reporting")
        self.current_host = self._read_current_host()
        self.rearm_at = None

    def _read_current_host(self):
        from logitech_receiver.hidpp20_constants import SupportedFeature
        try:
            reply = self.dev.feature_request(SupportedFeature.CHANGE_HOST, 0x00)
            return reply[1] if reply and len(reply) > 1 else None
        except Exception:
            return None

    def close(self):
        if self.mode == "key-report" and self.dev is not None:
            try:
                self._set_reporting(ANALYTICS_OFF)
            except Exception:
                pass  # keyboard gone or asleep; reporting resets on reconnect
        if self.fd is not None:
            os.close(self.fd)
        self.fd = None
        self.key = None
        self.mode = ""
        self.dev = None
        self.cids = []
        self.rearm_at = None
        self.away = False

    def sync(self, config, devices, identity):
        from logitech_receiver.hidpp20_constants import SupportedFeature
        key = config["keyboard"] if config["follow"] else ""
        dev = next((d for d in devices if identity(d) == key), None)
        path = (getattr(dev, "path", None) or getattr(getattr(dev, "receiver", None), "path", None)) if dev else None
        token = (key, path, id(dev)) if key and dev else None
        if self.fd is not None and self.key == token:
            if self.rearm_at is not None and time.monotonic() >= self.rearm_at:
                try:
                    self._arm()
                    self.error = ""
                except Exception as exc:
                    self.rearm_at = time.monotonic() + REARM_DELAY
                    self.error = str(exc)[:300]
            return
        self.close()
        self.error = ""
        if not key:
            return
        if dev is None:
            self.error = "Source keyboard is offline"
            return
        try:
            number = int(dev.number)
            change_host = dev.features[SupportedFeature.CHANGE_HOST]
            if change_host and (dev.features.get_feature_version(SupportedFeature.CHANGE_HOST) or 0) >= 2:
                self.fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_CLOEXEC)
                self.key, self.feature, self.number, self.mode = token, int(change_host), number, "change-host-v2"
                return
            reprog = dev.features[SupportedFeature.REPROG_CONTROLS_V4]
            if not reprog or (dev.features.get_feature_version(SupportedFeature.REPROG_CONTROLS_V4) or 0) < 4:
                raise ValueError("This keyboard cannot report its Easy-Switch keys; use the Switch buttons or a shortcut")
            cids = host_key_reporting(dev.keys)
            if not cids:
                raise ValueError("This keyboard cannot report its Easy-Switch keys; use the Switch buttons or a shortcut")
            self.dev, self.cids = dev, cids
            self.mode = "key-report"
            # Receivers only report a device leaving or returning when
            # connection notifications are on. Solaar's GUI listener enables
            # them; without it they are off and re-arming never happens.
            receiver = getattr(dev, "receiver", None)
            if receiver is not None and hasattr(receiver, "enable_connection_notifications"):
                try:
                    receiver.enable_connection_notifications()
                except Exception:
                    pass  # verify() on the heartbeat still recovers reporting
            self._arm()
            self.fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_CLOEXEC)
            self.key, self.feature, self.number = token, int(reprog), number
        except Exception as exc:
            self.close()
            self.error = str(exc)[:300]

    def _target(self, config, channel):
        mapping = config["members"].get(config["keyboard"], [])
        return mapping.index(channel) + 1 if channel in mapping else None

    def _debounced(self, event):
        now = time.monotonic()
        if self.last_event == event and now - self.last_time < 1:
            return True
        self.last_event, self.last_time = event, now
        return False

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
                if len(raw) < 6 or raw[0] not in (0x10, 0x11, 0x21) or raw[1] != self.number:
                    continue
                # Receiver link notification: the keyboard came back to this
                # host. Key reporting is volatile, so re-enable it.
                if self.mode == "key-report" and raw[0] == 0x10 and raw[2] == 0x41:
                    if raw[3] & 0x40:
                        self.away = True
                    else:
                        self.away = False
                        self.rearm_at = time.monotonic()
                    continue
                if raw[2] != self.feature:
                    continue
                if self.mode == "key-report":
                    if raw[3] & 0xF0 != 0x20:  # analyticsKeyEvents
                        continue
                    for channel in parse_key_events(raw[4:]):
                        self.last_key = {"channel": channel + 1, "ts": int(time.time())}
                        if channel == self.current_host or self._debounced(("key", channel)):
                            continue
                        target = self._target(config, channel)
                        if target is not None:
                            self.away = True  # the keyboard is leaving now
                            return target
                    continue
                if raw[3] != 0:
                    continue
                old, new = raw[4:6]
                if old not in (0, 1, 2) or new not in (0, 1, 2) or old == new:
                    continue
                if self._debounced((old, new)):
                    continue
                target = self._target(config, new)
                if target is not None:
                    return target
        except OSError as exc:
            self.close()
            self.error = str(exc)[:300]
        return None

    def verify(self):
        """Heartbeat safety net: re-arm if key reporting was reset.

        Skipped while the keyboard is known to be away or a re-arm is already
        pending. Command thread only.
        """
        if self.mode != "key-report" or self.fd is None or self.away or self.rearm_at is not None or not self.cids:
            return
        now = time.monotonic()
        if now - self.verified_at < VERIFY_EVERY:
            return
        self.verified_at = now
        from logitech_receiver.hidpp20_constants import SupportedFeature
        cid = self.cids[0]
        try:
            reply = self.dev.feature_request(SupportedFeature.REPROG_CONTROLS_V4, GET_CID_REPORTING, cid >> 8, cid & 0xFF)
        except Exception:
            return
        if reply is None:
            return  # no answer: likely asleep or away; the link event re-arms
        if len(reply) < 6 or not reply[5] & 0x01:
            self.rearm_at = time.monotonic()

    def status(self):
        return {"listening": self.fd is not None, "mode": self.mode, "error": self.error,
                "lastKey": self.last_key, "away": self.away, "rearmPending": self.rearm_at is not None}
