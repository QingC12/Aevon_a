"""Execute the real maintainer script in a workspace-only, service-free fixture.

Only absolute device paths are rebased. No implementation block is extracted.
The shims model root/mobile ownership on ordinary CI runners; no sudo or iOS
services are needed. Lifecycle tests run separately through their own CI entry.
"""
from pathlib import Path
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest

R = Path(__file__).resolve().parent.parent
KEY = "REXIIUA5FF8288VP"
PREF = "com.nx.stheno.plist"
SHIM = r'''#!PYTHON
import json, os, pathlib, stat, subprocess, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
root = pathlib.Path(os.environ['FIXTURE'])
with open(root / 'commands.jsonl', 'a') as f:
    f.write(json.dumps([name, args, os.getcwd()]) + '\n')
fail = os.environ.get('FAIL', '')
if name == fail:
    sys.exit(1)
if name == 'stat':
    s = os.stat(args[-1])
    # Model device ownership on non-root CI. Ancestors outside the fixture
    # (including host /tmp) are trusted scaffolding, not device directories.
    inside = pathlib.Path(args[-1]).is_relative_to(root)
    print('0:%o' % (stat.S_IMODE(s.st_mode) if inside else 0o755))
    sys.exit(0)
if name in ('killall', 'sleep', 'sync', 'chown'):
    sys.exit(0)
if name == 'defaults':
    if args[0] == 'read':
        value = os.environ.get('DEFAULTS_KEY', 'REXIIUA5FF8288VP') if args[-1] == 'Key' else os.environ.get('DEFAULTS_INJECT', '0')
        if not value:
            sys.exit(1)
        print(value)
    elif args[0] == 'write':
        # A real defaults write mutates the domain, not merely a command log.
        pathlib.Path(args[1] + '.plist').write_bytes(b'defaults-overwrote-user-data')
    sys.exit(0)
if name == 'ln' and args[-1] == './':
    hook = os.environ.get('HOOK', '')
    # EXDEV is a persistent filesystem condition, not a one-shot race hook.
    # Repeated aliases to the same jbroot must all fail publication.
    if hook == 'exdev':
        sys.exit(1)
    if hook and not (root / 'hook-done').exists():
        (root / 'hook-done').touch()
        target = pathlib.Path(os.environ['HOOK_TARGET'])
        sentinel = pathlib.Path(os.environ['HOOK_SENTINEL'])
        if hook == 'file':
            target.write_bytes(b'concurrent-user-data')
        elif hook == 'symlink':
            target.symlink_to(sentinel)
        elif hook == 'directory':
            target.mkdir()
        elif hook == 'parent':
            old = target.parent
            old.rename(old.with_name(old.name + '-pinned'))
            old.symlink_to(sentinel, target_is_directory=True)
        elif hook == 'exdev':
            sys.exit(1)
if name == 'ln' and os.environ.get('HOOK') == 'source-symlink' and args[0].endswith('.stheno-off'):
    source = pathlib.Path(args[0])
    source.unlink()
    source.symlink_to(os.environ['HOOK_SENTINEL'])
real = json.loads(os.environ['REAL_TOOLS'])[name]
sys.exit(subprocess.call([real, *args]))
'''


class Sandbox:
    def __init__(self):
        # Native temporary storage supports real symlink/race tests on iSH;
        # the iOS-mounted repository does not. All device paths stay rebased.
        self.temp = tempfile.TemporaryDirectory(prefix='.installer-tests-')
        # macOS /var/folders resolves through /private/var; match the real
        # script's pwd -P without weakening any production ancestry checks.
        self.base = Path(self.temp.name).resolve()
        self.root = self.base / 'root'
        self.root.mkdir()
        probe = self.base / 'probe'
        probe.write_bytes(b'capability')
        self.hardlinks = self.symlinks = True
        try:
            os.link(probe, self.base / 'hardlink')
        except OSError:
            self.hardlinks = False
        try:
            (self.base / 'symlink').symlink_to(probe)
        except OSError:
            self.symlinks = False
        (self.root / 'private/var').mkdir(parents=True)
        if self.symlinks:
            (self.root / 'var').symlink_to('private/var', target_is_directory=True)
        else:
            (self.root / 'var').mkdir()
        self.home = self.path('/var/root')
        self.home.mkdir(mode=0o700)
        self.prefs = self.path('/var/mobile/Library/Preferences')
        self.prefs.mkdir(parents=True)
        self.docs = self.path('/var/mobile/Documents')
        self.docs.mkdir()
        self.jb = self.path('/var/containers/Bundle/Application/.jbroot-fixture')
        self.dest = self.jb / 'var/mobile/Library/Preferences'
        self.dest.mkdir(parents=True)
        self.target = self.dest / PREF
        self.template = self.path('/usr/local/share/stheno/' + PREF)
        self.template.parent.mkdir(parents=True)
        self.template.write_bytes(b'default-template-with-original-fields')
        self.ledger = self.docs / 'SthenoRestore.txt'
        self.bin = self.base / 'bin'
        self.bin.mkdir()
        tools = ['cat', 'ln', 'chmod', 'chown', 'rm', 'rmdir', 'mktemp',
                 'stat', 'killall', 'sleep', 'sync', 'defaults']
        real = {name: shutil.which(name) for name in tools}
        for name in tools:
            shim = self.bin / name
            shim.write_text(SHIM.replace('PYTHON', sys.executable, 1))
            shim.chmod(0o755)
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ['PATH'],
                        FIXTURE=str(self.base), REAL_TOOLS=json.dumps(real))
        self.scripts = {}
        for name in ('postinst', 'postrm'):
            text = (R / 'installer' / name).read_text()
            # One pass only: never recursively rewrite the workspace prefix.
            text = re.sub(r'(?<![\w./$}*-])/(?:private/var|var|Library|usr/local)(?=/|\b)',
                          lambda m: str(self.root) + m.group(), text)
            script = self.base / name
            script.write_text(text)
            self.scripts[name] = script

    def path(self, absolute):
        return self.root / absolute.lstrip('/')

    def run(self, name='postinst', phase='configure', **extra):
        p = subprocess.run(['/bin/sh', str(self.scripts[name]), phase],
                           env=dict(self.env, **extra), capture_output=True, timeout=120)
        assert p.returncode == 0, (p.returncode, p.stdout, p.stderr)
        assert p.stdout == b'' and p.stderr == b'', (p.stdout, p.stderr)
        return p

    def commands(self, name=None):
        log = self.base / 'commands.jsonl'
        rows = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
        return [r for r in rows if name is None or r[0] == name]

    def assert_clean(self):
        assert list(self.home.iterdir()) == [], list(self.home.iterdir())
        assert not list(self.dest.glob('*.tmp.*'))

    def close(self):
        self.temp.cleanup()


class InstallerPreferences(unittest.TestCase):
    def setUp(self):
        self.s = Sandbox()
        self.addCleanup(self.s.close)

    def require_links(self, symlinks=False):
        if not self.s.hardlinks or (symlinks and not self.s.symlinks):
            self.skipTest('workspace filesystem does not support native links')

    def test_existing_bytes_and_metadata_preserved(self):
        (self.s.prefs / PREF).write_bytes(b'primary-existing')
        for data in (b'short-without-key', b'Key=custom;Inject=false;Apps=user', b''):
            with self.subTest(data=data):
                self.s.target.write_bytes(data)
                self.s.target.chmod(0o640)
                self.s.run()
                self.assertEqual(self.s.target.read_bytes(), data)
                self.assertEqual(stat.S_IMODE(self.s.target.stat().st_mode), 0o640)
        self.assertFalse(self.s.commands('chown'))
        self.s.assert_clean()

    def test_missing_seed_is_complete_and_private_before_publish(self):
        self.require_links()
        self.s.run()
        self.assertEqual(self.s.target.read_bytes(), self.s.template.read_bytes())
        self.assertEqual(stat.S_IMODE(self.s.target.stat().st_mode), 0o600)
        calls = self.s.commands()
        owner = next(i for i, r in enumerate(calls) if r[0] == 'chown')
        mode = next(i for i, r in enumerate(calls) if r[0] == 'chmod')
        link = next(i for i, r in enumerate(calls) if r[0] == 'ln')
        self.assertLess(owner, mode)
        self.assertLess(mode, link)
        self.assertTrue(calls[owner][1][-1].startswith(str(self.s.home.resolve()) + '/.stheno-install.'))
        self.assertEqual(calls[link][1][-1], './')
        self.s.assert_clean()

    def test_primary_existing_source_wins_without_metadata_changes(self):
        self.require_links()
        source = self.s.prefs / PREF
        source.write_bytes(b'user-source-Key=custom-Apps=kept')
        source.chmod(0o644)
        self.s.run()
        self.assertEqual(self.s.target.read_bytes(), source.read_bytes())
        self.assertEqual(stat.S_IMODE(source.stat().st_mode), 0o644)
        self.assertTrue(all(r[1][-1] != str(source) for r in self.s.commands('chown')))

    def test_primary_custom_or_empty_domain_never_defaults_written(self):
        source = self.s.prefs / PREF
        fields = ('st_ino', 'st_mode', 'st_uid', 'st_gid', 'st_mtime_ns', 'st_ctime_ns')
        for data in (b'Key=custom;Apps=user', b''):
            with self.subTest(data=data):
                source.write_bytes(data)
                source.chmod(0o640)
                before = tuple(getattr(source.stat(), f) for f in fields)
                self.s.run(DEFAULTS_KEY='custom', DEFAULTS_INJECT='')
                self.assertEqual(source.read_bytes(), data)
                self.assertEqual(tuple(getattr(source.stat(), f) for f in fields), before)
        self.assertFalse(any(r[1][0] == 'write' for r in self.s.commands('defaults')))
        self.s.assert_clean()

    def test_missing_primary_seed_is_atomic_and_private(self):
        self.require_links()
        primary = self.s.prefs / PREF
        self.s.run(DEFAULTS_KEY='', DEFAULTS_INJECT='')
        self.assertEqual(primary.read_bytes(), self.s.template.read_bytes())
        self.assertEqual(stat.S_IMODE(primary.stat().st_mode), 0o600)
        self.assertFalse(any(r[1][0] == 'write' for r in self.s.commands('defaults')))
        self.s.assert_clean()

    def test_symlinks_and_directories_are_occupied(self):
        self.require_links(symlinks=True)
        (self.s.prefs / PREF).write_bytes(b'primary-existing')
        sentinel = self.s.base / 'sentinel'
        sentinel.write_bytes(b'do-not-touch')
        sentinel.chmod(0o644)
        self.s.target.symlink_to(sentinel)
        self.s.run()
        self.assertTrue(self.s.target.is_symlink())
        self.assertEqual(sentinel.read_bytes(), b'do-not-touch')
        self.assertEqual(stat.S_IMODE(sentinel.stat().st_mode), 0o644)
        self.s.target.unlink()
        self.s.target.symlink_to(self.s.base / 'missing')
        self.s.run()
        self.assertTrue(self.s.target.is_symlink())
        self.s.target.unlink()
        self.s.target.mkdir()
        self.s.run()
        self.assertEqual(list(self.s.target.iterdir()), [])
        self.assertFalse(self.s.commands('chown'))


if __name__ == '__main__':
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(InstallerPreferences)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    if not result.wasSuccessful():
        sys.exit(1)
