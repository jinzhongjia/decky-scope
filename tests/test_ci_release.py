import hashlib
import importlib.util
import json
import stat
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


def module(name):
    spec = importlib.util.spec_from_file_location('ci_' + name, ROOT / 'ci' / f'{name}.py')
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


release = module('release')
publisher = module('publish')
COMMIT = 'a' * 40


def fixture(root):
    for directory in ('monitor/src', 'ci', 'outputs', 'py_modules', 'dist', 'bin'):
        (root / directory).mkdir(parents=True, exist_ok=True)
    (root / 'package.json').write_text(json.dumps({'name': 'decky-scope', 'version': '0.1.0-rc.3', 'packageManager': 'pnpm@11.3.0'}))
    (root / 'plugin.json').write_text('{"name":"DeckScope"}')
    (root / 'monitor/src/model.zig').write_text('pub const version = "0.1.0-rc.3";')
    (root / 'ci/toolchains.json').write_bytes((ROOT / 'ci/toolchains.json').read_bytes())
    for name in ('main.py', 'dist/index.js', 'py_modules/deckscope_bridge.py'):
        (root / name).write_text('fixture')
    native = bytearray(64)
    native[:6] = b'\x7fELF\x02\x01'
    native[18:20] = b'\x3e\x00'
    (root / 'bin/deckscope-monitor').write_bytes(native)
    return root


def archive(root, extra=None, bad_mode=False):
    target = root / 'outputs/DeckScope-dev.zip'
    with zipfile.ZipFile(target, 'w') as z:
        for name in sorted(release.allowed_files(root)):
            entry = zipfile.ZipInfo('DeckScope/' + name)
            mode = 0o755 if name == 'bin/deckscope-monitor' and not bad_mode else 0o644
            entry.external_attr = (stat.S_IFREG | mode) << 16
            z.writestr(entry, (root / name).read_bytes())
        if extra:
            z.writestr(extra, 'unwanted')
    return target


class ReleasePipelineTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = fixture(Path(self.temp.name))

    def assets(self):
        archive(self.root)
        with patch.object(release.subprocess, 'check_output', return_value=COMMIT + '\n'):
            release.make_assets(self.root, 'v0.1.0-rc.3')
        return self.root / 'outputs/ci'

    def test_metadata_accepts_matching_tag_and_rejects_mismatch(self):
        self.assertTrue(release.identity(self.root, 'v0.1.0-rc.3')['prerelease'])
        for tag in ('v0.1.0', '0.1.0-rc.3', 'v0.1.0-rc.3\n', '$(bad)'):
            with self.assertRaises(ValueError):
                release.identity(self.root, tag)

    def test_metadata_rejects_native_or_toolchain_drift(self):
        (self.root / 'monitor/src/model.zig').write_text('pub const version = "0.1.0";')
        with self.assertRaises(ValueError):
            release.identity(self.root)
        fixture(self.root)
        tools = json.loads((self.root / 'ci/toolchains.json').read_text())
        tools['pnpm'] = '9.0.0'
        (self.root / 'ci/toolchains.json').write_text(json.dumps(tools))
        with self.assertRaises(ValueError):
            release.identity(self.root)

    def test_metadata_rejects_invalid_versions(self):
        for version in ('01.0.0', '0.1.0-01', '../../x', '0.1.0\n'):
            package = json.loads((self.root / 'package.json').read_text())
            package['version'] = version
            (self.root / 'package.json').write_text(json.dumps(package))
            with self.assertRaises(ValueError):
                release.identity(self.root)

    def test_tag_must_point_to_checkout(self):
        with patch.object(release.subprocess, 'check_output', side_effect=[COMMIT, 'b' * 40]):
            with self.assertRaises(ValueError):
                release.tracked_tag('v0.1.0-rc.3', self.root)

    def test_package_rejects_extra_files_modes_and_stale_content(self):
        release.validate_package(archive(self.root), self.root)
        for name in ('DeckScope/settings.json', '../escape', 'DeckScope/.env'):
            with self.assertRaises(ValueError):
                release.validate_package(archive(self.root, extra=name), self.root)
        with self.assertRaises(ValueError):
            release.validate_package(archive(self.root, bad_mode=True), self.root)
        archive(self.root)
        (self.root / 'main.py').write_text('stale')
        with self.assertRaises(ValueError):
            release.validate_package(self.root / 'outputs/DeckScope-dev.zip', self.root)

    def test_package_rejects_wrong_binary_architecture(self):
        (self.root / 'bin/deckscope-monitor').write_bytes(b'not an ELF')
        with self.assertRaises(ValueError):
            release.validate_package(archive(self.root), self.root)

    def test_assets_are_reproducible_and_verified(self):
        folder = self.assets()
        first = {p.name: p.read_bytes() for p in folder.iterdir()}
        second = self.root / 'outputs/again'
        with patch.object(release.subprocess, 'check_output', return_value=COMMIT + '\n'):
            release.make_assets(self.root, 'v0.1.0-rc.3', second)
        self.assertEqual(first, {p.name: p.read_bytes() for p in second.iterdir()})
        self.assertEqual(publisher.verify_assets(folder, 'v0.1.0-rc.3', COMMIT)['version'], '0.1.0-rc.3')
        with self.assertRaises(ValueError):
            publisher.verify_assets(folder, 'v0.1.0', COMMIT)
        (folder / 'SHA256SUMS').write_text('corrupt')
        with self.assertRaises(ValueError):
            publisher.verify_assets(folder, 'v0.1.0-rc.3', COMMIT)

    def test_existing_asset_comparison_never_clobbers(self):
        self.assertEqual(publisher.asset_decision(None, 'abc'), 'upload')
        self.assertEqual(publisher.asset_decision({'digest': 'sha256:abc'}, 'abc'), 'skip')
        self.assertEqual(publisher.asset_decision({'digest': None}, 'abc'), 'verify-download')
        with self.assertRaises(ValueError):
            publisher.asset_decision({'digest': 'sha256:different'}, 'abc')

    def run_publish(self, existing=None, remote_sha=COMMIT):
        folder = self.assets()
        calls = []

        def fake(*args):
            calls.append(args)
            if args[0] == 'api' and '/git/ref/tags/' in args[-1]:
                return json.dumps({'object': {'type': 'commit', 'sha': remote_sha}})
            if '--paginate' in args:
                return json.dumps([[existing] if existing else []])
            if args[0] == 'api' and '/releases/tags/' in args[-1]:
                return json.dumps({'draft': True, 'assets': []})
            return ''

        with patch.object(publisher, 'gh', side_effect=fake):
            publisher.publish(folder, 'owner/repo', 'v0.1.0-rc.3', COMMIT)
        return calls

    def test_new_release_uploads_before_publish_and_marks_prerelease(self):
        calls = self.run_publish()
        create = next(c for c in calls if c[:2] == ('release', 'create'))
        self.assertIn('--verify-tag', create)
        self.assertIn('--draft', create)
        self.assertIn('--prerelease', create)
        self.assertEqual(len([c for c in calls if c[:2] == ('release', 'upload')]), 3)
        self.assertEqual(calls[-1][:2], ('release', 'edit'))
        self.assertIn('--draft=false', calls[-1])

    def test_existing_user_draft_is_not_published(self):
        calls = self.run_publish({'tag_name': 'v0.1.0-rc.3', 'draft': True, 'assets': [], 'body': 'User draft'})
        self.assertFalse(any(c[:2] == ('release', 'edit') for c in calls))

    def test_interrupted_ci_draft_can_resume(self):
        calls = self.run_publish({'tag_name': 'v0.1.0-rc.3', 'draft': True, 'assets': [], 'body': f'<!-- deckscope-ci:{COMMIT} -->'})
        self.assertEqual(calls[-1][:2], ('release', 'edit'))

    def test_remote_tag_move_blocks_all_release_mutations(self):
        with self.assertRaisesRegex(ValueError, 'moved'):
            self.run_publish(remote_sha='b' * 40)

    def test_workflow_has_readonly_build_and_publish_gate(self):
        source = (ROOT / '.github/workflows/ci.yml').read_text()
        self.assertNotIn('pull_request_target', source)
        self.assertIn('contents: read', source)
        self.assertIn('needs: build', source)
        self.assertIn("format('pr-{0}', github.event.pull_request.number)", source)
        self.assertIn("github.event_name == 'release'", source)
        self.assertIn('pnpm install --frozen-lockfile', source)
        for line in source.splitlines():
            if 'uses:' in line:
                self.assertRegex(line, r'@[a-f0-9]{40} # v')
