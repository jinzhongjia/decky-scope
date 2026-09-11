import importlib.util
import json
import tempfile
import unittest
import zipfile
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("release_preflight_tests", ROOT / "scripts/release-check.py")
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleasePreflightTests(unittest.TestCase):
    def fixture(self, root):
        files = {
            "package.json": json.dumps({"version": "0.1.0-rc.1", "packageManager": "pnpm@11.3.0"}),
            "plugin.json": json.dumps({"name": "DeckScope", "publish": {"image": ""}}),
            "monitor/src/model.zig": 'pub const version = "0.1.0-rc.1";',
            "main.py": "# test fixture\n",
            "dist/index.js": "test fixture",
            "bin/deckscope-monitor": "test fixture",
            "py_modules/deckscope_bridge.py": "# test fixture\n",
        }
        for name, value in files.items():
            path = root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(value)
        (root / "outputs").mkdir()
        with zipfile.ZipFile(root / "outputs/DeckScope-dev.zip", "w") as z:
            for name, value in files.items():
                z.writestr("DeckScope/" + name, value)

    def test_private_candidate_does_not_imply_public_release(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root)
            with patch.object(release, "ROOT", root), patch.object(release.subprocess, "run", return_value=SimpleNamespace(stdout="")):
                result = release.inspect()
            self.assertTrue(result["candidate_ok"])
            self.assertFalse(result["public_preflight_ok"])
            self.assertTrue(any("license" in issue for issue in result["public_blockers"]))
            self.assertTrue(result["manual_review_required"])

    def test_stale_frontend_and_version_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root)
            (root / "dist/index.js").write_text("changed since packaging")
            (root / "monitor/src/model.zig").write_text('pub const version = "0.0.0";')
            with patch.object(release, "ROOT", root), patch.object(release.subprocess, "run", return_value=SimpleNamespace(stdout="")):
                result = release.inspect()
            self.assertFalse(result["candidate_ok"])
            self.assertIn("Native/package versions differ", result["candidate_errors"])
            self.assertIn("Stale archive: dist/index.js", result["candidate_errors"])
