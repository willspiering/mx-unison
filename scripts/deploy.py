#!/usr/bin/env python3
"""Copy reviewed runtime source into the current user's Omarchy plugin directory."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import shutil
import subprocess
import time

PLUGIN_ID = "local.mx-unison"
RUNTIME = (
    "manifest.json", "LICENSE", "README.md", "ActionEditor.qml", "BarWidget.qml",
    "DeviceChannels.qml", "MxField.qml", "MxIcon.qml", "MxMeter.qml", "MxSection.qml", "MxSettings.qml", "Panel.qml", "Service.qml", "SwitchGroup.qml", "WheelGuard.qml",
    "Model.js", "mxactions.py", "mxctl.py", "mxpointer.py", "mxscroll.py", "mxswitch.py",
)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true", help="Validate and list files without writing or enabling")
    parser.add_argument("--enable", action="store_true", help="Rescan and enable after copying")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    destination = Path.home() / ".config/omarchy/plugins" / PLUGIN_ID
    manifest = json.loads((root / "manifest.json").read_text())
    if manifest.get("id") != PLUGIN_ID:
        parser.error("Unexpected plugin identity")
    catalogs = sorted((root / "i18n").glob("*.json"))
    files = [root / name for name in RUNTIME] + catalogs
    if not catalogs:
        parser.error("No translation catalogs found")
    for source in files:
        if source.is_symlink() or not source.is_file():
            parser.error(f"Missing or symlinked runtime file: {source.name}")
        if source.suffix == ".json":
            json.loads(source.read_text())
    if root == destination.resolve():
        parser.error("Run from a separate source checkout, not the deployed plugin")
    if destination.is_symlink():
        parser.error("Refusing to overwrite a symlinked plugin directory")
    print(f"Source: {root}\nDestination: {destination}")
    for source in files:
        print(f"  {source.relative_to(root)}")
    if args.dry_run:
        print("Dry run: no files changed; shell commands were not run.")
        return
    if destination.exists():
        state = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state")
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
        backup = state / "mx-unison/backups" / stamp
        backup.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(destination, backup, symlinks=True)
        print(f"Backup: {backup}")
    destination.mkdir(parents=True, exist_ok=True)
    for source in files:
        target = destination / source.relative_to(root)
        if not target.resolve().is_relative_to(destination.resolve()):
            raise RuntimeError(f"Target escapes the plugin directory: {target}")
        target.parent.mkdir(parents=True, exist_ok=True)
        if target.is_symlink():
            raise RuntimeError(f"Refusing to replace a symlink: {target}")
        shutil.copy2(source, target)
    print("Runtime files copied; local device preferences were not changed.")
    if args.enable:
        subprocess.run(["omarchy-shell", "shell", "rescanPlugins"], check=True)
        # Registry discovery is asynchronous. Wait for this ID before enabling.
        for _ in range(20):
            result = subprocess.run(["omarchy", "plugin", "catalog"], check=True, capture_output=True, text=True)
            if any(row.get("id") == PLUGIN_ID for row in json.loads(result.stdout)):
                break
            time.sleep(0.25)
        else:
            raise RuntimeError("Installed files, but shell did not discover the plugin")
        subprocess.run(["omarchy", "plugin", "enable", PLUGIN_ID, "--section", "right"], check=True)
    print("If QML components remain cached, run: omarchy restart shell")


if __name__ == "__main__":
    main()
