"""Full-script races, lifecycle phases, and durable restoration records."""
from pathlib import Path
import os
import stat
import subprocess
import unittest
from test_installer_preferences import Sandbox, PREF


class InstallerLifecycle(unittest.TestCase):
    def setUp(self):
        self.s = Sandbox()
        self.addCleanup(self.s.close)

    def require_links(self, symlinks=False):
        if not self.s.hardlinks or (symlinks and not self.s.symlinks):
            self.skipTest('workspace filesystem does not support native links')

    def backup(self, name='AppDataFixture.plist', directory=None):
        target = (directory or self.s.dest) / name
        off = target.with_name(target.name + '.stheno-off')
        off.write_bytes(b'original-quarantined-settings')
        off.chmod(0o640)
        return target, off

    def ledger(self, *paths):
        # No trailing newline: read must still process the final record.
        self.s.ledger.write_text('\n'.join(map(str, paths)))
        return self.s.ledger.read_bytes()

    def hook(self, kind, target=None, sentinel=None):
        return dict(HOOK=kind, HOOK_TARGET=str(target or self.s.target),
                    HOOK_SENTINEL=str(sentinel or self.s.base / 'sentinel'))

    def test_install_publication_conflicts_file_and_directory(self):
        for kind in ('file', 'directory'):
            with self.subTest(kind=kind):
                if self.s.target.is_dir():
                    self.s.target.rmdir()
                elif self.s.target.exists():
                    self.s.target.unlink()
                (self.s.base / 'hook-done').unlink(missing_ok=True)
                self.s.run(**self.hook(kind))
                if kind == 'file':
                    self.assertEqual(self.s.target.read_bytes(), b'concurrent-user-data')
                else:
                    self.assertEqual(list(self.s.target.iterdir()), [])
                self.s.assert_clean()

    def test_install_symlink_race_never_follows_or_changes_metadata(self):
        self.require_links(symlinks=True)
        sentinel = self.s.base / 'sentinel'
        sentinel.mkdir()
        (sentinel / PREF).write_bytes(b'unrelated')
        sentinel.chmod(0o755)
        self.s.run(**self.hook('symlink', sentinel=sentinel))
        self.assertTrue(self.s.target.is_symlink())
        self.assertEqual((sentinel / PREF).read_bytes(), b'unrelated')
        self.assertEqual(stat.S_IMODE(sentinel.stat().st_mode), 0o755)
        self.s.assert_clean()

    def test_install_parent_rename_pins_destination(self):
        self.require_links(symlinks=True)
        sentinel = self.s.base / 'elsewhere'
        sentinel.mkdir()
        self.s.run(**self.hook('parent', sentinel=sentinel))
        self.assertEqual(list(sentinel.iterdir()), [])
        pinned = self.s.dest.with_name(self.s.dest.name + '-pinned') / PREF
        self.assertEqual(pinned.read_bytes(), self.s.template.read_bytes())
        self.s.assert_clean()

    def test_install_rejects_initial_symlinked_destination(self):
        self.require_links(symlinks=True)
        outside = self.s.base / 'outside'
        outside.mkdir()
        self.s.dest.rmdir()
        self.s.dest.symlink_to(outside, target_is_directory=True)
        self.s.run()
        self.assertEqual(list(outside.iterdir()), [])
        self.s.assert_clean()

    def test_primary_publication_race_preserves_concurrent_user_config(self):
        self.require_links()
        self.s.target.write_bytes(b'already-configured')
        primary = self.s.prefs / PREF
        self.s.run(**self.hook('file', primary))
        self.assertEqual(primary.read_bytes(), b'concurrent-user-data')
        self.assertEqual(self.s.target.read_bytes(), b'already-configured')
        self.s.assert_clean()

    def test_install_preparation_failures_and_exdev_clean_up(self):
        for command in ('cat', 'chown', 'chmod', 'mktemp'):
            with self.subTest(command=command):
                self.s.run(FAIL=command)
                self.assertFalse(self.s.target.exists())
                self.s.assert_clean()
        self.s.run(**self.hook('exdev'))
        self.assertFalse(self.s.target.exists())
        self.s.assert_clean()

    def test_install_rejects_untrusted_private_parent(self):
        self.s.home.chmod(0o777)
        self.s.run()
        self.assertFalse(self.s.target.exists())
        self.assertFalse(self.s.commands('mktemp'))
        self.s.home.chmod(0o700)
        self.s.assert_clean()

    def test_concurrent_installers_publish_one_complete_file(self):
        self.require_links()
        children = [subprocess.Popen(['/bin/sh', str(self.s.scripts['postinst']), 'configure'],
                                     env=self.s.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                    for _ in range(3)]
        try:
            for child in children:
                out, err = child.communicate(timeout=180)
                self.assertEqual((child.returncode, out, err), (0, b'', b''))
        finally:
            for child in children:
                if child.poll() is None:
                    child.kill()
                child.communicate()
        self.assertEqual(self.s.target.read_bytes(), self.s.template.read_bytes())
        self.assertEqual(stat.S_IMODE(self.s.target.stat().st_mode), 0o600)
        self.s.assert_clean()

    def test_optional_respring_and_defaults_contract(self):
        self.s.target.write_bytes(b'user-preferences')
        self.s.run()
        self.assertFalse(any('SpringBoard' in r[1] for r in self.s.commands('killall')))
        (self.s.docs / 'SthenoAutoRespring').touch()
        self.s.run()
        self.assertTrue(any('SpringBoard' in r[1] for r in self.s.commands('killall')))
        self.assertTrue(all(r[1][0] == 'read' for r in self.s.commands('defaults')))
        self.assertEqual(self.s.target.read_bytes(), b'user-preferences')

    def test_upgrade_abort_and_unknown_phases_are_noops(self):
        target, off = self.backup()
        original = self.ledger(target)
        for phase in ('upgrade', 'failed-upgrade', 'abort-install', 'abort-upgrade',
                      'abort-remove', 'disappear', 'configure', ''):
            with self.subTest(phase=phase):
                self.s.run('postrm', phase)
                self.assertFalse(target.exists())
                self.assertTrue(off.exists())
                self.assertEqual(self.s.ledger.read_bytes(), original)
        self.assertEqual(self.s.commands(), [])

    def test_remove_purge_restore_missing_and_preserve_records(self):
        self.require_links()
        for phase in ('remove', 'purge'):
            with self.subTest(phase=phase):
                target, off = self.backup('AppData-' + phase + '.plist')
                original = self.ledger(target)
                self.s.run('postrm', phase)
                self.assertEqual(target.read_bytes(), b'original-quarantined-settings')
                self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o640)
                self.assertTrue(off.exists())
                self.assertEqual(self.s.ledger.read_bytes(), original)
                self.s.assert_clean()

    def test_no_ledger_root_hide_fallback_only_appdata(self):
        self.require_links()
        target, off = self.backup()
        other, other_off = self.backup('Unrelated.plist')
        prefs, prefs_off = self.backup(PREF)
        self.s.run('postrm', 'remove')
        self.assertTrue(target.exists())
        self.assertTrue(off.exists())
        self.assertFalse(other.exists())
        self.assertFalse(prefs.exists())
        self.assertTrue(other_off.exists() and prefs_off.exists())

    def test_restore_conflicts_and_failures_keep_ledger_and_backups(self):
        target, off = self.backup()
        original = self.ledger(target, self.s.dest / 'AppDataMissing.plist')
        target.write_bytes(b'new-install-wins')
        self.s.run('postrm', 'remove')
        self.assertEqual(target.read_bytes(), b'new-install-wins')
        target.unlink()
        self.s.run('postrm', 'purge', FAIL='ln')
        self.assertFalse(target.exists())
        self.assertEqual(off.read_bytes(), b'original-quarantined-settings')
        self.assertEqual(self.s.ledger.read_bytes(), original)
        self.s.assert_clean()

    def test_restore_rejects_out_of_scope_and_traversal_records(self):
        directory = self.s.base / 'unrelated'
        directory.mkdir()
        arbitrary, arbitrary_off = self.backup(directory=directory)
        pref, pref_off = self.backup(PREF)
        traversal = self.s.dest / '..' / 'Preferences' / 'AppDataOther.plist'
        original = self.ledger(arbitrary, pref, traversal, Path('relative/AppData.plist'))
        self.s.run('postrm', 'remove')
        self.assertFalse(arbitrary.exists() or pref.exists())
        self.assertTrue(arbitrary_off.exists() and pref_off.exists())
        self.assertEqual(self.s.ledger.read_bytes(), original)

    def test_restore_publication_race_preserves_new_conflict(self):
        self.require_links()
        target, off = self.backup()
        original = self.ledger(target)
        self.s.run('postrm', 'remove', **self.hook('file', target))
        self.assertEqual(target.read_bytes(), b'concurrent-user-data')
        self.assertEqual(off.read_bytes(), b'original-quarantined-settings')
        self.assertEqual(self.s.ledger.read_bytes(), original)
        self.s.assert_clean()

    def test_restore_listed_dynamic_library_and_private_root_hide(self):
        self.require_links()
        libraries = self.s.path('/Library/MobileSubstrate/DynamicLibraries')
        libraries.mkdir(parents=True)
        lib, lib_off = self.backup('AppDataFixture.dylib', libraries)
        private = self.s.jb / 'private/var/mobile/Library/Preferences'
        private.mkdir(parents=True)
        pref, pref_off = self.backup('AppDataPrivate.plist', private)
        original = self.ledger(lib, pref)
        self.s.run('postrm', 'purge')
        self.assertEqual(lib.read_bytes(), lib_off.read_bytes())
        self.assertEqual(pref.read_bytes(), pref_off.read_bytes())
        self.assertEqual(self.s.ledger.read_bytes(), original)
        self.s.assert_clean()

    def test_restore_symlinks_and_source_swap_are_not_followed(self):
        self.require_links(symlinks=True)
        sentinel = self.s.base / 'sentinel'
        sentinel.write_bytes(b'unrelated')
        target, off = self.backup()
        original = self.ledger(target)
        target.symlink_to(self.s.base / 'missing')
        self.s.run('postrm', 'remove')
        self.assertTrue(target.is_symlink())
        target.unlink()
        off.unlink()
        off.symlink_to(sentinel)
        self.s.run('postrm', 'remove')
        self.assertFalse(target.exists())
        off.unlink()
        off.write_bytes(b'old-quarantine')
        self.s.run('postrm', 'remove', LN_SOURCE_DEFAULT='follow',
                   **self.hook('source-symlink', target, sentinel))
        self.assertTrue(off.is_symlink(), 'the source-swap hook must execute')
        self.assertFalse(target.exists() or target.is_symlink())
        self.assertEqual(sentinel.read_bytes(), b'unrelated')
        self.assertEqual(self.s.ledger.read_bytes(), original)
        self.s.assert_clean()

    def test_restore_rejects_symlinked_parent_and_ledger(self):
        self.require_links(symlinks=True)
        outside = self.s.base / 'outside'
        outside.mkdir()
        target, off = self.backup(directory=outside)
        original = self.ledger(self.s.dest / target.name)
        self.s.dest.rmdir()
        self.s.dest.symlink_to(outside, target_is_directory=True)
        self.s.run('postrm', 'remove')
        self.assertFalse(target.exists())
        self.assertTrue(off.exists())
        self.assertEqual(self.s.ledger.read_bytes(), original)
        self.s.ledger.unlink()
        self.s.ledger.symlink_to(self.s.base / 'absent-records')
        self.s.run('postrm', 'purge')
        self.assertTrue(self.s.ledger.is_symlink())
        self.s.assert_clean()

    def test_remove_purge_preserve_primary_preferences(self):
        for phase in ('remove', 'purge'):
            primary = self.s.prefs / PREF
            primary.write_bytes(b'Key=custom;Inject=false;Apps=user')
            primary.chmod(0o644)
            self.s.run('postrm', phase)
            self.assertEqual(primary.read_bytes(), b'Key=custom;Inject=false;Apps=user')
            self.assertEqual(stat.S_IMODE(primary.stat().st_mode), 0o644)
        self.assertFalse(self.s.commands('chown') or self.s.commands('chmod'))

    def test_explicit_ledger_keeps_legacy_non_appdata_names(self):
        self.require_links()
        target, off = self.backup('Legacy Injection.plist')
        original = self.ledger(target)
        self.s.run('postrm', 'remove')
        self.assertEqual(target.read_bytes(), off.read_bytes())
        self.assertEqual(self.s.ledger.read_bytes(), original)
        self.s.assert_clean()


if __name__ == '__main__':
    unittest.main(verbosity=2)
