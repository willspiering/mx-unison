import os
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import mxctl


def fake_sysfs(root: Path, nodes):
    """nodes: {hidrawN: (instance, vendor)} with synthetic uevent files."""
    devices = root / "devices"
    classdir = root / "class"
    classdir.mkdir(parents=True, exist_ok=True)
    for name, (instance, vendor) in nodes.items():
        dev = devices / instance
        dev.mkdir(parents=True, exist_ok=True)
        (dev / "uevent").write_text(f"HID_ID=0005:0000{vendor}:0000B034\nHID_NAME=Synthetic Mouse\nHID_UNIQ=\n")
        node = classdir / name
        node.mkdir(exist_ok=True)
        link = node / "device"
        if link.is_symlink():
            link.unlink()
        link.symlink_to(dev)
    return classdir


class Reconnect(unittest.TestCase):
    def test_reconnect_with_same_node_name_changes_topology(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            before = mxctl.logitech_hidraw(fake_sysfs(root, {"hidraw3": ("0005:046D:B034.000B", "046D")}))
            after = mxctl.logitech_hidraw(fake_sysfs(root, {"hidraw3": ("0005:046D:B034.000C", "046D")}))
        self.assertEqual([n["path"] for n in before], ["/dev/hidraw3"])
        self.assertNotEqual(mxctl.hidraw_topology(before), mxctl.hidraw_topology(after))
        self.assertEqual(mxctl.hidraw_instances(after), {"/dev/hidraw3": "0005:046D:B034.000C"})

    def test_non_logitech_nodes_are_ignored(self):
        with tempfile.TemporaryDirectory() as tmp:
            nodes = mxctl.logitech_hidraw(fake_sysfs(Path(tmp), {"hidraw0": ("0003:1234:0001.0001", "1234")}))
        self.assertEqual(nodes, [])

    def test_prune_drops_replaced_handle_even_if_path_exists(self):
        closed = []
        with tempfile.NamedTemporaryFile(dir="/dev/shm" if os.path.isdir("/dev/shm") else None) as node:
            handle = SimpleNamespace(path=node.name, close=lambda: closed.append(True))
            if not node.name.startswith("/dev/"):
                self.skipTest("needs a /dev path for prune_dead")
            kept = mxctl.prune_dead([handle], {node.name: "A.0001"}, {node.name: "A.0001"})
            self.assertEqual(kept, [handle])
            kept = mxctl.prune_dead([handle], {node.name: "A.0001"}, {node.name: "A.0002"})
            self.assertEqual(kept, [])
            self.assertEqual(closed, [True])

    def test_reopen_backoff_is_bounded(self):
        delays = [mxctl.reopen_retry_delay(i) for i in range(8)]
        self.assertEqual(delays[:6], [1.0, 2.0, 4.0, 8.0, 15.0, 30.0])
        self.assertEqual(delays[6:], [None, None])

    def test_unopened_paths_lists_devices_that_failed_to_open(self):
        listed = [SimpleNamespace(path="/dev/hidraw2"), SimpleNamespace(path="/dev/hidraw3")]
        mods = {"base": SimpleNamespace(receivers_and_devices=lambda: listed)}
        self.assertEqual(mxctl.unopened_paths(mods, [SimpleNamespace(path="/dev/hidraw2")]), {"/dev/hidraw3"})
        self.assertEqual(mxctl.unopened_paths(mods, [SimpleNamespace(path=p.path) for p in listed]), set())


if __name__ == "__main__":
    unittest.main()
