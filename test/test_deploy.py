"""Deployment checks use an isolated HOME and never contact the desktop shell."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class DeploymentTests(unittest.TestCase):
    def run_deploy(self, home, *args):
        env = dict(os.environ, HOME=str(home), XDG_STATE_HOME=str(home / 'state'))
        return subprocess.run([sys.executable, '-B', str(ROOT / 'scripts/deploy.py'), *args],
                              env=env, capture_output=True, text=True)

    def test_dry_run_has_no_side_effects_even_with_enable(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            result = self.run_deploy(home, '--dry-run', '--enable')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(list(home.iterdir()), [])

    def test_runtime_allowlist_and_backup_preserve_existing_install(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            dest = home / '.config/omarchy/plugins/local.mx-unison'
            dest.mkdir(parents=True)
            (dest / 'README.md').write_text('previous installation')
            result = self.run_deploy(home)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue((dest / 'mxswitch.py').is_file())
            self.assertTrue((dest / 'i18n/en.json').is_file())
            for private in ('.git', 'test', 'preview.png', 'switch.json', 'scripts'):
                self.assertFalse((dest / private).exists(), private)
            backups = list((home / 'state/mx-unison/backups').iterdir())
            self.assertEqual(len(backups), 1)
            self.assertEqual((backups[0] / 'README.md').read_text(), 'previous installation')

    def test_symlinked_installation_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            dest = home / '.config/omarchy/plugins/local.mx-unison'
            dest.parent.mkdir(parents=True)
            outside = home / 'outside'; outside.mkdir()
            dest.symlink_to(outside, target_is_directory=True)
            result = self.run_deploy(home)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(list(outside.iterdir()), [])


if __name__ == '__main__':
    unittest.main()
