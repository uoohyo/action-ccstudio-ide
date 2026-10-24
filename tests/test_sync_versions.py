import importlib.util
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / '.github/scripts/sync_versions.py'
spec = importlib.util.spec_from_file_location('sync_versions', SCRIPT)
sync = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sync)


class SelectionTests(unittest.TestCase):
    def test_available_rows_only_and_numeric_order(self):
        data = '| `1.9.0` | ![available](url) | 99.99.99 |\n| `1.10.0` | ![available](url) | |\n| `1.22.0` | missing | |'
        self.assertEqual(sync.available_versions(data, 3), ['1.9.0', '1.10.0'])

    def test_invalid_available_row_is_error(self):
        for data in ['', '| `1.2.3-action.1` | ![available](url) | |']:
            with self.assertRaises(ValueError):
                sync.available_versions(data, 3)

    def test_ccs_patch_alias_keeps_highest_build(self):
        aliases = sync.alias_targets(['20.5.1.00002', '20.5.1.00014', '21.0.0.00001'], 4)
        self.assertEqual(aliases['v20.5.1'], 'v20.5.1.00014')
        self.assertEqual(aliases['latest'], 'v21.0.0.00001')

    def test_revision_tag_is_not_a_toolchain_version(self):
        with self.assertRaises(ValueError):
            sync.alias_targets(['1.2.3-action.1'], 3)

    def test_release_api_error_propagates(self):
        with patch.object(sync, 'command', side_effect=RuntimeError('API unavailable')):
            with self.assertRaises(RuntimeError):
                sync.release_tags()

    def test_alias_lease_failure_is_a_failed_operation(self):
        with patch.object(sync, 'remote_tags', return_value=({'v1.2.3': 'tag-object'}, {'v1.2.3': 'target'})), \
             patch.object(sync, 'release_tags', return_value={'v1.2.3'}), \
             patch.object(sync, 'command', side_effect=lambda *args, **kw: (_ for _ in ()).throw(RuntimeError('stale lease')) if args[1] == 'push' else ''):
            run = sync.Reconciler('stm32')
            run.reconcile(['1.2.3'])
        aliases = [row for row in run.results if row['operation'] == 'alias']
        self.assertTrue(aliases)
        self.assertTrue(all(row['status'] == 'failed' for row in aliases))


class LocalGitIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.repo = self.root / 'repo'
        self.remote = self.root / 'origin.git'
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.release_file = self.root / 'releases.json'
        self.release_file.write_text('[]')
        gh = self.bin / 'gh'
        gh.write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
p = Path(os.environ['FAKE_RELEASES'])
releases = json.loads(p.read_text())
if sys.argv[1] == 'api':
    if os.environ.get('FAIL_API'): sys.exit(1)
    print(json.dumps([[{'tag_name': t, 'draft': False} for t in releases]]))
elif sys.argv[1:3] == ['release', 'create']:
    tag = sys.argv[3]
    if os.environ.get('FAIL_RELEASE') == tag: sys.exit(1)
    releases.append(tag)
    p.write_text(json.dumps(releases))
else: sys.exit(2)
''')
        gh.chmod(0o755)
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ['PATH'], FAKE_RELEASES=str(self.release_file))
        self.run_git('init', '--bare', str(self.remote), cwd=self.root)
        self.run_git('clone', str(self.remote), str(self.repo), cwd=self.root)
        self.run_git('config', 'user.name', 'Test')
        self.run_git('config', 'user.email', 'test@example.invalid')
        (self.repo / 'Dockerfile').write_text('ARG CUBECLT_VERSION=latest\nFROM example:${CUBECLT_VERSION}\n')
        (self.repo / 'keep.txt').write_text('preserved\n')
        self.run_git('add', '.')
        self.run_git('commit', '-m', 'Initial fixture')
        self.run_git('push', 'origin', 'HEAD:main')
        self.versions = self.root / 'versions.md'
        self.versions.write_text('| `1.2.3` | ![available](url) | |\n')

    def tearDown(self):
        self.temp.cleanup()

    def run_git(self, *args, cwd=None):
        return subprocess.check_output(['git', *args], cwd=cwd or self.repo, env=self.env, text=True, stderr=subprocess.DEVNULL).strip()

    def reconcile(self, kind='stm32', **env):
        return subprocess.run(['python3', str(SCRIPT), '--kind', kind, '--versions-file', str(self.versions)], cwd=self.repo, env=dict(self.env, **env), capture_output=True, text=True)

    def test_create_pin_and_idempotent_repair_without_new_version(self):
        result = self.reconcile()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        full = self.run_git('rev-parse', 'v1.2.3^{commit}')
        self.assertIn('ARG CUBECLT_VERSION=1.2.3', self.run_git('show', 'v1.2.3:Dockerfile'))
        self.assertEqual(self.run_git('show', 'v1.2.3:keep.txt'), 'preserved')
        first_refs = self.run_git('ls-remote', '--tags', 'origin')
        self.assertEqual(self.reconcile().returncode, 0)
        self.assertEqual(first_refs, self.run_git('ls-remote', '--tags', 'origin'))
        self.run_git('push', 'origin', ':refs/tags/v1.2')
        self.release_file.write_text('[]')
        self.assertEqual(self.reconcile().returncode, 0)
        self.assertEqual(self.run_git('rev-parse', 'v1.2^{commit}'), full)
        self.assertEqual(json.loads(self.release_file.read_text()), ['v1.2.3'])

    def test_ccs_full_tags_and_patch_alias_use_highest_build(self):
        (self.repo / 'Dockerfile').write_text('ARG CCS_VERSION=latest\nFROM example:${CCS_VERSION}\n')
        self.run_git('add', 'Dockerfile')
        self.run_git('commit', '-m', 'CCS fixture')
        self.versions.write_text('| `20.5.1.00002` | ![available](url) | |\n| `20.5.1.00014` | ![available](url) | |\n')
        result = self.reconcile(kind='ccs')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.run_git('rev-parse', 'v20.5.1^{commit}'), self.run_git('rev-parse', 'v20.5.1.00014^{commit}'))
        self.assertIn('ARG CCS_VERSION=20.5.1.00014', self.run_git('show', 'v20.5.1:Dockerfile'))
        refs = self.run_git('ls-remote', '--tags', 'origin')
        self.assertEqual(self.reconcile(kind='ccs').returncode, 0)
        self.assertEqual(refs, self.run_git('ls-remote', '--tags', 'origin'))

    def test_release_failure_reports_failure_and_no_aliases_then_recovers(self):
        result = self.reconcile(FAIL_RELEASE='v1.2.3')
        self.assertEqual(result.returncode, 1)
        report = json.loads((self.repo / 'sync-results.json').read_text())
        self.assertTrue(any(r['status'] == 'failed' for r in report))
        self.assertNotIn('refs/tags/latest', self.run_git('ls-remote', '--tags', 'origin'))
        self.assertEqual(self.reconcile().returncode, 0)

    def test_api_failure_does_not_create_tags(self):
        self.assertEqual(self.reconcile(FAIL_API='1').returncode, 1)
        self.assertEqual(self.run_git('ls-remote', '--tags', 'origin'), '')

    def test_existing_full_tag_is_never_rewritten(self):
        self.assertEqual(self.reconcile().returncode, 0)
        full = self.run_git('rev-parse', 'v1.2.3')
        (self.repo / 'keep.txt').write_text('new action code\n')
        self.run_git('add', 'keep.txt')
        self.run_git('commit', '-m', 'Change action')
        self.assertEqual(self.reconcile().returncode, 0)
        self.assertEqual(self.run_git('rev-parse', 'v1.2.3'), full)
        self.assertEqual(self.run_git('show', 'v1.2.3:keep.txt'), 'preserved')

    def test_tag_push_failure_is_not_counted_as_success(self):
        hook = self.remote / 'hooks/pre-receive'
        hook.write_text('#!/bin/sh\nexit 1\n')
        hook.chmod(0o755)
        self.assertEqual(self.reconcile().returncode, 1)
        report = json.loads((self.repo / 'sync-results.json').read_text())
        self.assertFalse(any(r['operation'] == 'tag' and r['status'] == 'created' for r in report))
        self.assertEqual(json.loads(self.release_file.read_text()), [])


if __name__ == '__main__':
    unittest.main()
