import os
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import mxswitch


class Switching(unittest.TestCase):
    def setUp(self):
        self.config = {"version": 1, "keyboard": "keys", "follow": False,
                       "members": {"keys": [0, 1, 2], "mouse": [2, 0, 1]}}
        self.devices = [SimpleNamespace(id="keys", name="MX Keys", kind="keyboard"),
                        SimpleNamespace(id="mouse", name="MX Master", kind="mouse")]
        self.sent = []
        self.settings = {d.id: SimpleNamespace(choices=[0, 1, 2],
                         write=lambda channel, save, did=d.id: self.sent.append((did, channel, save)) or channel)
                         for d in self.devices}

    def plan(self, target=2, source="", devices=None):
        return mxswitch.prepare(self.config, self.devices if devices is None else devices,
                                lambda d: d.id, lambda d: True,
                                lambda d: self.settings.get(d.id), target, source)

    def test_mapping_and_keyboard_last_no_persistence(self):
        result = mxswitch.execute(self.plan())
        self.assertEqual(self.sent, [("mouse", 0, False), ("keys", 1, False)])
        self.assertEqual(result["sent"], ["mouse", "keys"])

    def test_missing_member_is_all_or_nothing_preflight(self):
        with self.assertRaises(ValueError): self.plan(devices=self.devices[:1])
        self.assertEqual(self.sent, [])

    def test_unsupported_member_is_all_or_nothing_preflight(self):
        del self.settings['mouse']
        with self.assertRaises(ValueError): self.plan()
        self.assertEqual(self.sent, [])

    def test_invalid_targets(self):
        for target in (0, 4, True, "2", None):
            with self.assertRaises(ValueError): self.plan(target)

    def test_keyboard_already_switching_is_not_commanded(self):
        self.config['follow'] = True
        mxswitch.execute(self.plan(source="keys", devices=self.devices[1:]))
        self.assertEqual(self.sent, [("mouse", 0, False)])

    def test_mouse_rejection_stops_before_keyboard(self):
        self.settings['mouse'].write = lambda *a, **kw: None
        with self.assertRaisesRegex(RuntimeError, "after 0"):
            mxswitch.execute(self.plan())
        self.assertEqual(self.sent, [])

    def test_validation_markup_and_bounds(self):
        for key in ('<img src="https://example.invalid/x">', 'x'*129):
            self.config['keyboard'] = key
            with self.assertRaises(ValueError): mxswitch.validate(self.config)
        self.config['keyboard'] = 'keys'
        self.config['members']['mouse'] = [0, 0, 2]
        with self.assertRaises(ValueError): mxswitch.validate(self.config)

    def test_store_symlinks_and_size(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)/'switch.json'
            self.assertEqual(mxswitch.load(path), mxswitch.empty())
            path.write_text(' '*16385)
            with self.assertRaises(ValueError): mxswitch.load(path)
            link = Path(tmp)/'link'; link.symlink_to(path)
            with self.assertRaises(OSError): mxswitch.load(link)

    def test_notification_filter_and_mapping(self):
        follower = mxswitch.Follower()
        follower.fd = 99; follower.number = 255; follower.feature = 10
        self.config['follow'] = True
        # Not our device, then keyboard switching from channel 1 to 3.
        packets = [bytes([0x11, 1, 10, 0, 0, 1]), bytes([0x11, 255, 10, 0, 0, 2])]
        with patch('mxswitch.os.read', side_effect=packets):
            self.assertEqual(follower.poll(self.config), 3)
        # Duplicate notification is suppressed.
        with patch('mxswitch.os.read', side_effect=[packets[1], BlockingIOError()]):
            self.assertIsNone(follower.poll(self.config))

    def test_unpaired_target_is_rejected_before_any_write(self):
        with self.assertRaisesRegex(ValueError, "not paired"):
            mxswitch.prepare(self.config, self.devices, lambda d: d.id,
                lambda d: True, lambda d: self.settings[d.id], 3,
                hosts_for=lambda d: [{"index": 2, "paired": False}] if d.id == "keys" else [])
        self.assertEqual(self.sent, [])

    def test_devices_already_on_target_are_skipped(self):
        # Mouse maps target 2 -> channel 0 and is already there (live read).
        work = mxswitch.prepare(self.config, self.devices, lambda d: d.id, lambda d: True,
                                lambda d: self.settings.get(d.id), 2,
                                current_for=lambda d: 0 if d.id == "mouse" else 2)
        self.assertEqual([row[0] for row in work], ["keys"])
        # Everything already there: nothing to send.
        none = mxswitch.prepare(self.config, self.devices, lambda d: d.id, lambda d: True,
                                lambda d: self.settings.get(d.id), 2,
                                current_for=lambda d: {"mouse": 0, "keys": 1}[d.id])
        self.assertEqual(none, [])

    def test_unknown_current_channel_still_switches(self):
        work = mxswitch.prepare(self.config, self.devices, lambda d: d.id, lambda d: True,
                                lambda d: self.settings.get(d.id), 2, current_for=lambda d: None)
        self.assertEqual(len(work), 2)

    def run_verified(self, answers):
        """answers: per-device list of ping results consumed in order."""
        pings = {did: list(seq) for did, seq in answers.items()}
        present = lambda dev: pings[dev.id].pop(0) if pings[dev.id] else False
        return mxswitch.execute(self.plan(), present=present, sleep=lambda _: None)

    def test_verified_switch_departs_first_time(self):
        result = self.run_verified({"mouse": [False], "keys": [False]})
        self.assertEqual([d for d, _, _ in self.sent], ["mouse", "keys"])
        self.assertEqual(result["retried"], [])

    def test_ignored_command_is_resent_once(self):
        result = self.run_verified({"mouse": [True, True, True, False], "keys": [False]})
        self.assertEqual([d for d, _, _ in self.sent], ["mouse", "mouse", "keys"])
        self.assertEqual(result["retried"], ["mouse"])

    def test_device_that_stays_keeps_keyboard_here(self):
        with self.assertRaisesRegex(mxswitch.SwitchError, "after 0 command.*mouse ignored.*still connected") as ctx:
            self.run_verified({"mouse": [True] * 9, "keys": [False]})
        self.assertEqual([d for d, _, _ in self.sent], ["mouse"] * mxswitch.SWITCH_ATTEMPTS)
        self.assertEqual(ctx.exception.steps, [{"kind": "mouse", "channel": 1, "attempts": 3, "outcome": "stayed"}])

    def test_steps_record_each_device(self):
        result = self.run_verified({"mouse": [True, True, True, False], "keys": [False]})
        self.assertEqual([(s["kind"], s["attempts"], s["outcome"]) for s in result["steps"]],
                         [("mouse", 2, "left"), ("keyboard", 1, "left")])

    def test_follow_requires_grouped_source(self):
        self.config.update(follow=True, keyboard='other')
        with self.assertRaises(ValueError): mxswitch.validate(self.config)


class _Feature:
    """Stand-in for logitech_receiver.hidpp20_constants.SupportedFeature."""
    CHANGE_HOST = "CHANGE_HOST"
    REPROG_CONTROLS_V4 = "REPROG_CONTROLS_V4"


class _Features(dict):
    def __init__(self, indexes, versions):
        super().__init__(indexes)
        self.versions = versions

    def get_feature_version(self, feature):
        return self.versions.get(feature)


class _Keyboard:
    """Synthetic CHANGE_HOST v1 keyboard with reportable Easy-Switch keys."""
    def __init__(self, change_host_version=1, analytics=True, echo=True):
        self.number = 2
        self.path = "/dev/hidraw-synthetic"
        self.features = _Features({_Feature.CHANGE_HOST: 9, _Feature.REPROG_CONTROLS_V4: 8},
                                  {_Feature.CHANGE_HOST: change_host_version, _Feature.REPROG_CONTROLS_V4: 5})
        flag = 0x400 if analytics else 0
        self.keys = [SimpleNamespace(key=cid, flags=flag) for cid in (0xD1, 0xD2, 0xD3)]
        self.keys.append(SimpleNamespace(key=0xE2, flags=0x420))  # unrelated key
        self.echo = echo
        self.requests = []

    def feature_request(self, feature, function, *params):
        self.requests.append((feature, function, params))
        if feature == _Feature.CHANGE_HOST:
            return bytes([3, 1])  # three hosts, currently on channel 2
        if function == 0x20:
            return bytes([params[0], params[1], 0, 0, 0, 0x01 if self.echo else 0])
        return bytes(6)


class KeyReportFollow(unittest.TestCase):
    def setUp(self):
        module = SimpleNamespace(SupportedFeature=_Feature)
        patcher = patch.dict(sys.modules, {"logitech_receiver": SimpleNamespace(hidpp20_constants=module),
                                           "logitech_receiver.hidpp20_constants": module})
        patcher.start()
        self.addCleanup(patcher.stop)
        self.config = {"version": 1, "keyboard": "keys", "follow": True,
                       "members": {"keys": [0, 1, 2], "mouse": [2, 1, 0]}}

    def sync(self, follower, keyboard):
        with patch("mxswitch.os.open", return_value=77), patch("mxswitch.os.close"):
            follower.sync(self.config, [keyboard], lambda d: "keys")

    def test_parse_key_events_reports_only_host_key_presses(self):
        payload = bytes([0x00, 0xD2, 0x01, 0x00, 0xE2, 0x01, 0x00, 0xD3, 0x00]) + bytes(7)
        self.assertEqual(mxswitch.parse_key_events(payload), [1])
        self.assertEqual(mxswitch.parse_key_events(bytes(16)), [])

    def test_only_reportable_host_keys_are_selected(self):
        self.assertEqual(mxswitch.host_key_reporting(_Keyboard().keys), [0xD1, 0xD2, 0xD3])
        self.assertEqual(mxswitch.host_key_reporting(_Keyboard(analytics=False).keys), [])

    def test_v1_keyboard_enables_reporting_on_host_keys_only(self):
        keyboard, follower = _Keyboard(), mxswitch.Follower()
        self.sync(follower, keyboard)
        self.assertEqual(follower.status()["mode"], "key-report")
        self.assertTrue(follower.status()["listening"], follower.error)
        sets = [r for r in keyboard.requests if r[1] == 0x30]
        self.assertEqual([(p[0] << 8 | p[1]) for _, _, p in sets], [0xD1, 0xD2, 0xD3])
        # Never touches divert flags or remapping, only the analytics byte.
        self.assertTrue(all(p[2:5] == (0, 0, 0) and p[5] == 0x03 for _, _, p in sets))
        self.assertEqual(follower.current_host, 1)

    def test_close_clears_reporting(self):
        keyboard, follower = _Keyboard(), mxswitch.Follower()
        self.sync(follower, keyboard)
        keyboard.requests.clear()
        with patch("mxswitch.os.close"):
            follower.close()
        self.assertEqual([p[5] for _, f, p in keyboard.requests if f == 0x30], [0x02] * 3)
        self.assertFalse(follower.status()["listening"])

    def test_unconfirmed_reporting_is_an_error_not_a_listener(self):
        keyboard, follower = _Keyboard(echo=False), mxswitch.Follower()
        self.sync(follower, keyboard)
        self.assertFalse(follower.status()["listening"])
        self.assertIn("did not enable", follower.error)

    def test_keyboard_without_reportable_keys_explains_fallback(self):
        follower = mxswitch.Follower()
        self.sync(follower, _Keyboard(analytics=False))
        self.assertIn("cannot report", follower.error)

    def test_v2_keyboard_keeps_change_host_listener(self):
        keyboard, follower = _Keyboard(change_host_version=2), mxswitch.Follower()
        self.sync(follower, keyboard)
        self.assertEqual(follower.status()["mode"], "change-host-v2")
        self.assertEqual(keyboard.requests, [])

    def test_key_press_maps_to_target_and_skips_current_host(self):
        follower = mxswitch.Follower()
        follower.fd, follower.number, follower.feature, follower.mode = 77, 2, 8, "key-report"
        follower.current_host = 1
        press = lambda ch, dev=2: bytes([0x11, dev, 8, 0x20, 0x00, 0xD1 + ch, 0x01]) + bytes(13)
        # Other device, current host, then channel 1 -> logical target 1.
        with patch("mxswitch.os.read", side_effect=[press(0, dev=1), press(1), press(0)]):
            self.assertEqual(follower.poll(self.config), 1)
        self.assertEqual(follower.status()["lastKey"]["channel"], 1)
        # Repeat within a second is debounced.
        with patch("mxswitch.os.read", side_effect=[press(0), BlockingIOError()]):
            self.assertIsNone(follower.poll(self.config))
        # Channel 3 is mapped to target 3 for this keyboard.
        with patch("mxswitch.os.read", side_effect=[press(2)]):
            self.assertEqual(follower.poll(self.config), 3)

    def test_arming_enables_receiver_connection_notifications(self):
        keyboard, follower = _Keyboard(), mxswitch.Follower()
        calls = []
        keyboard.receiver = SimpleNamespace(enable_connection_notifications=lambda: calls.append(True))
        self.sync(follower, keyboard)
        self.assertEqual(calls, [True])
        self.assertTrue(follower.status()["listening"])

    def test_link_down_marks_away_and_verify_skips(self):
        keyboard, follower = _Keyboard(), mxswitch.Follower()
        self.sync(follower, keyboard)
        with patch("mxswitch.os.read", side_effect=[bytes([0x10, 2, 0x41, 0x44, 0, 0, 0]), BlockingIOError()]):
            follower.poll(self.config)
        self.assertTrue(follower.status()["away"])
        keyboard.requests.clear()
        follower.verified_at = 0.0
        follower.verify()
        self.assertEqual(keyboard.requests, [])

    def test_verify_rearms_when_reporting_was_reset(self):
        keyboard, follower = _Keyboard(), mxswitch.Follower()
        self.sync(follower, keyboard)
        keyboard.echo = False  # device lost the analytics flag
        follower.verified_at = 0.0
        follower.verify()
        self.assertTrue(follower.status()["rearmPending"])
        keyboard.echo = True
        self.sync(follower, keyboard)
        self.assertFalse(follower.status()["rearmPending"])

    def test_departing_key_press_marks_away(self):
        follower = mxswitch.Follower()
        follower.fd, follower.number, follower.feature, follower.mode = 77, 2, 8, "key-report"
        follower.current_host = 1
        press = bytes([0x11, 2, 8, 0x20, 0x00, 0xD1, 0x01]) + bytes(13)
        with patch("mxswitch.os.read", side_effect=[press]):
            self.assertEqual(follower.poll(self.config), 1)
        self.assertTrue(follower.away)

    def test_reconnect_schedules_rearm(self):
        keyboard, follower = _Keyboard(), mxswitch.Follower()
        self.sync(follower, keyboard)
        link_up, link_down = bytes([0x10, 2, 0x41, 0x04, 0, 0, 0]), bytes([0x10, 2, 0x41, 0x44, 0, 0, 0])
        with patch("mxswitch.os.read", side_effect=[link_down, BlockingIOError()]):
            follower.poll(self.config)
        self.assertIsNone(follower.rearm_at)
        with patch("mxswitch.os.read", side_effect=[link_up, BlockingIOError()]):
            follower.poll(self.config)
        self.assertIsNotNone(follower.rearm_at)
        keyboard.requests.clear()
        self.sync(follower, keyboard)
        self.assertEqual(len([r for r in keyboard.requests if r[1] == 0x30]), 3)
        self.assertIsNone(follower.rearm_at)


if __name__ == '__main__': unittest.main()
