#!/usr/bin/env python3
"""Reconcile immutable toolchain tags, releases, and moving aliases.

Only aliases may move. Every network mutation is recorded and failures fail the
run. This module is import-safe so selection and failure behavior can be tested
without GitHub credentials or vendor tools.
"""
import argparse
import json
import os
import re
import subprocess
from pathlib import Path


def command(*args, input=None):
    result = subprocess.run(args, input=input, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(f"{' '.join(args[:3])} failed: {result.stderr.strip()}")
    return result.stdout.strip()


def available_versions(markdown, parts):
    pattern = re.compile(r"\d+(?:\.\d+){%d}" % (parts - 1))
    versions = set()
    for row in markdown.splitlines():
        cells = row.split('|')
        if len(cells) > 3 and '![available]' in cells[2]:
            version = cells[1].strip().strip('`')
            if not pattern.fullmatch(version):
                raise ValueError(f"Invalid available version: {version!r}")
            versions.add(version)
    if not versions:
        raise ValueError('No available versions found')
    return sorted(versions, key=lambda value: tuple(map(int, value.split('.'))))


def alias_targets(versions, parts):
    targets = {}
    for version in sorted(versions, key=lambda value: tuple(map(int, value.split('.'))), reverse=True):
        pieces = version.split('.')
        if len(pieces) != parts or not all(p.isdigit() for p in pieces):
            raise ValueError(f'Invalid full version: {version}')
        for size in range(1, parts):
            targets.setdefault('v' + '.'.join(pieces[:size]), 'v' + version)
        targets.setdefault('latest', 'v' + version)
    return targets


def remote_tags():
    raw = {}
    peeled = {}
    for line in command('git', 'ls-remote', '--tags', 'origin').splitlines():
        sha, ref = line.split()
        name = ref.removeprefix('refs/tags/')
        if name.endswith('^{}'):
            peeled[name[:-3]] = sha
        else:
            raw[name] = sha
    return raw, {name: peeled.get(name, sha) for name, sha in raw.items()}


def release_tags():
    # API failure is not interpreted as a missing release.
    pages = json.loads(command('gh', 'api', '--paginate', '--slurp', 'repos/{owner}/{repo}/releases?per_page=100'))
    return {release['tag_name'] for page in pages for release in page if not release.get('draft')}


def version_commit(version, variable):
    original = command('git', 'show', 'HEAD:Dockerfile') + '\n'
    rewritten, count = re.subn(rf'^ARG {variable}=latest$', f'ARG {variable}={version}', original, flags=re.M)
    if count != 1:
        raise ValueError(f'Expected exactly one default {variable} declaration')
    blob = command('git', 'hash-object', '-w', '--stdin', input=rewritten)
    entries = command('git', 'ls-tree', 'HEAD').splitlines()
    found = False
    for index, entry in enumerate(entries):
        metadata, path = entry.split('\t', 1)
        if path == 'Dockerfile':
            mode, kind, _ = metadata.split()
            entries[index] = f'{mode} {kind} {blob}\tDockerfile'
            found = True
    if not found:
        raise ValueError('Dockerfile is not tracked')
    tree = command('git', 'mktree', input='\n'.join(entries) + '\n')
    return command('git', 'commit-tree', tree, '-p', 'HEAD', '-m', f'Pin toolchain version {version}')


class Reconciler:
    def __init__(self, kind):
        self.kind = kind
        self.parts = 4 if kind == 'ccs' else 3
        self.variable = 'CCS_VERSION' if kind == 'ccs' else 'CUBECLT_VERSION'
        self.product = 'CCS' if kind == 'ccs' else 'STM32CubeCLT'
        self.image = 'uoohyo/ccstudio-ide' if kind == 'ccs' else 'uoohyo/stm32-cmake'
        self.results = []

    def record(self, item, operation, status, detail=''):
        self.results.append(dict(item=item, operation=operation, status=status, detail=detail))
        print(f'{status}: {operation} {item} {detail}')

    def reconcile(self, versions):
        raw, commits = remote_tags()
        releases = release_tags()
        for version in versions:
            tag = 'v' + version
            operation = 'tag'
            try:
                if tag not in raw:
                    commit = version_commit(version, self.variable)
                    command('git', 'tag', '-a', tag, commit, '-m', f'{self.product} {version}')
                    command('git', 'push', 'origin', f'refs/tags/{tag}:refs/tags/{tag}')
                    # Confirm the remote ref rather than relying on a local tag.
                    new_raw, new_commits = remote_tags()
                    if new_commits.get(tag) != commit:
                        raise RuntimeError('Remote tag did not resolve to the expected commit')
                    raw[tag], commits[tag] = new_raw[tag], new_commits[tag]
                    self.record(tag, 'tag', 'created')
                else:
                    self.record(tag, 'tag', 'unchanged')
                operation = 'release'
                if tag not in releases:
                    command('gh', 'release', 'create', tag, '--verify-tag', '--title', f'{self.product} {version}',
                            '--notes', f'{self.product} {version} using Docker image {self.image}:{version}. See README for usage and installation details.')
                    releases.add(tag)
                    self.record(tag, 'release', 'created')
                else:
                    self.record(tag, 'release', 'unchanged')
            except (RuntimeError, ValueError) as error:
                self.record(tag, operation, 'failed', str(error))

        # Do not move latest backwards when any desired version is incomplete.
        if any(result['status'] == 'failed' for result in self.results):
            self.record('all', 'aliases', 'skipped', 'A full version failed reconciliation')
            return
        for alias, tag in alias_targets(versions, self.parts).items():
            target = commits[tag]
            if commits.get(alias) == target:
                self.record(alias, 'alias', 'unchanged')
                continue
            try:
                command('git', 'tag', '-f', '-a', alias, target, '-m', f'Latest {self.product}: {tag}')
                # Lease protects against another publisher changing the alias.
                lease = f'--force-with-lease=refs/tags/{alias}:{raw.get(alias, "")}'
                command('git', 'push', lease, 'origin', f'refs/tags/{alias}:refs/tags/{alias}')
                confirmed_raw, confirmed_commits = remote_tags()
                if confirmed_commits.get(alias) != target:
                    raise RuntimeError('Remote alias verification failed')
                raw[alias], commits[alias] = confirmed_raw[alias], target
                self.record(alias, 'alias', 'updated')
            except RuntimeError as error:
                self.record(alias, 'alias', 'failed', str(error))

    def write_report(self, path):
        Path(path).write_text(json.dumps(self.results, indent=2) + '\n')
        summary = os.environ.get('GITHUB_STEP_SUMMARY')
        if summary:
            with open(summary, 'a') as stream:
                created = sum(row['status'] == 'created' and row['operation'] == 'tag' for row in self.results)
                failures = sum(row['status'] == 'failed' for row in self.results)
                stream.write(f'## Version reconciliation\n\nFull tags created: {created}; failed operations: {failures}.\n\n')
                stream.write('| Item | Operation | Result |\n|---|---|---|\n')
                for row in self.results:
                    stream.write(f"| {row['item']} | {row['operation']} | {row['status']} |\n")
                stream.write('\nFull version tags are immutable. Results describe actual operations, not planned counts.\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--kind', choices=['ccs', 'stm32'], required=True)
    parser.add_argument('--versions-file', required=True)
    parser.add_argument('--report', default='sync-results.json')
    args = parser.parse_args()
    sync = Reconciler(args.kind)
    try:
        versions = available_versions(Path(args.versions_file).read_text(), sync.parts)
        sync.reconcile(versions)
    except (RuntimeError, ValueError, OSError, json.JSONDecodeError) as error:
        sync.record('sync', 'preflight', 'failed', str(error))
    finally:
        sync.write_report(args.report)
    return int(any(row['status'] == 'failed' for row in sync.results))


if __name__ == '__main__':
    raise SystemExit(main())
