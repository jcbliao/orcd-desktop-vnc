"""Offline checks: never contact SSH or submit a real Slurm job."""
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'desktop-vnc' / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class WorkflowTests(unittest.TestCase):
    def test_lookup_follows_allocation_and_rejects_stale_node(self):
        lookup = load('find-session')
        with tempfile.TemporaryDirectory() as directory:
            connection = Path(directory) / 'connection.txt'
            queue = subprocess.CompletedProcess([], 0, '42|engaging-desktop-vnc|RUNNING|node9999|' + directory + '\n')
            with patch.object(lookup.subprocess, 'run', return_value=queue), patch.object(
                    lookup.subprocess, 'check_output', return_value='node9999\n'):
                connection.write_text('Desktop job: 42\nCompute node: node9999.inband\nVNC display: :2 (TCP port 5902)\n')
                self.assertEqual(lookup.resolve('42')[0:3], ('42', 'node9999.inband', '5902'))
                connection.write_text('Desktop job: 42\nCompute node: node0001.inband\nVNC display: :2 (TCP port 5902)\n')
                with self.assertRaisesRegex(ValueError, 'does not match'):
                    lookup.resolve('42')

    def test_launcher_uses_default_or_configured_account(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            shutil.copy(ROOT / 'desktop-vnc/launch.sh', root / 'launch.sh')
            (root / 'sbatch').write_text('#!/bin/bash\nprintf "%s\\n" "$@" > "$CAPTURE"\necho 42\n')
            (root / 'sbatch').chmod(0o755)
            env = dict(os.environ, PATH=str(root) + os.pathsep + os.environ['PATH'], CAPTURE=str(root / 'args'))
            for key in list(env):
                if key.startswith('DESKTOP_'):
                    del env[key]
            subprocess.run(['bash', str(root / 'launch.sh'), '--detach'], env=env, check=True, capture_output=True)
            args = (root / 'args').read_text()
            self.assertNotIn('--account=', args)
            self.assertNotIn('--qos=', args)
            self.assertNotIn('--nodelist', args)
            (root / 'config.sh').write_text('DESKTOP_ACCOUNT=test_account\nDESKTOP_QOS=test_qos\n')
            subprocess.run(['bash', str(root / 'launch.sh'), '--detach', '--mem=2G'], env=env, check=True, capture_output=True)
            args = (root / 'args').read_text()
            self.assertIn('--account=test_account', args)
            self.assertIn('--qos=test_qos', args)
            self.assertLess(args.index('--mem=64G'), args.index('--mem=2G'))
            for session in (root / 'sessions').iterdir():
                self.assertEqual(session.stat().st_mode & 0o777, 0o700)
                self.assertEqual((session / 'password').stat().st_mode & 0o777, 0o600)

    def test_local_helper_uses_ssh_user_and_dynamic_node(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'ssh').write_text('''#!/bin/bash
if [[ $1 == -G ]]; then
    echo 'user cluster_user'
elif [[ $1 == -T ]]; then
    printf '42\\tnode9999.inband\\t5902\\t/session/password\\ttestpass\\n'
else
    printf '%s\\n' "$@" > "$CAPTURE"
fi
''')
            (root / 'ssh').chmod(0o755)
            env = dict(os.environ, PATH=str(root) + os.pathsep + os.environ['PATH'], CAPTURE=str(root / 'args'))
            result = subprocess.run(['bash', str(ROOT / 'desktop-vnc/connect.sh')], env=env, check=True, capture_output=True, text=True)
            args = (root / 'args').read_text()
            self.assertIn('cluster_user@node9999.inband', args)
            self.assertIn('127.0.0.1:15901:127.0.0.1:5902', args)
            self.assertIn('testpass', result.stdout)
            env['VNC_LOCAL_PORT'] = '70000'
            result = subprocess.run(['bash', str(ROOT / 'desktop-vnc/connect.sh')], env=env, capture_output=True)
            self.assertNotEqual(result.returncode, 0)


if __name__ == '__main__':
    unittest.main()
