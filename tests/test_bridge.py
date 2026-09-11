import asyncio
import importlib
import logging
import os
import re
import sys
import tempfile
import types
import unittest
from pathlib import Path
from support import ROOT, BINARY

sys.path.insert(0, str(ROOT / "py_modules"))
import settings


class SettingsTests(unittest.TestCase):
    def test_atomic_private_settings_and_corrupt_fallback(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "settings.json"
            settings.save(path, settings.DEFAULTS)
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            self.assertEqual(settings.load(path), settings.DEFAULTS)
            path.write_text("{broken")
            self.assertEqual(settings.load(path), settings.DEFAULTS)
            self.assertEqual(path.read_text(), "{broken")

    def test_api_contract(self):
        facade = (ROOT / "main.py").read_text()
        names = set(re.search(r'frozenset\("([^"]+)"', facade).group(1).split())
        api = (ROOT / "src/api.ts").read_text()
        declared = set(re.findall(r'\("([a-z_]+)"\)', api)) - {"metrics"}
        self.assertEqual(names, declared)
        bridge = (ROOT / "py_modules/bridge.py").read_text()
        for name in names:
            self.assertRegex(bridge, rf'async def {name}\(')


class BridgeTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="scope-bridge-")
        self.path = Path(self.tmp.name)
        (self.path / "plugin/bin").mkdir(parents=True)
        (self.path / "plugin/bin/deckscope-monitor").symlink_to(BINARY)
        self.events = []
        async def emit(name, data):
            self.events.append((name, data))
        fake = types.ModuleType("decky")
        fake.DECKY_PLUGIN_DIR = str(self.path / "plugin")
        fake.DECKY_PLUGIN_RUNTIME_DIR = str(self.path / "data")
        fake.DECKY_PLUGIN_SETTINGS_DIR = str(self.path / "settings")
        fake.DECKY_VERSION = "test"
        fake.emit = emit
        fake.logger = logging.getLogger("test-decky")
        sys.modules["decky"] = fake
        import bridge
        importlib.reload(bridge)
        self.bridge = bridge.Bridge()
        await self.bridge.start()
        await asyncio.wait_for(self.bridge.connected.wait(), 5)

    async def asyncTearDown(self):
        await self.bridge.unload()
        self.assertIsNone(self.bridge.process)
        self.tmp.cleanup()

    async def test_control_settings_privacy_and_unload(self):
        result = await self.bridge.get_status()
        self.assertTrue(result["ok"])
        self.assertEqual(self.bridge.socket_path.stat().st_mode & 0o777, 0o600)
        self.assertTrue((await self.bridge.set_config({"interval_ms": 2000, "privacy_mask": False}))["ok"])
        self.assertTrue((await self.bridge.set_config({"live_push": True}))["ok"])
        saved = settings.load(self.bridge.settings_path)
        self.assertNotIn("live_push", saved)
        self.assertEqual(saved["interval_ms"], 2000)
        self.assertFalse((await self.bridge.set_config({"interval_ms": True}))["ok"])
        text = (await self.bridge.export_summary())["data"]["text"]
        for forbidden in (str(self.path), "recommended_ip", "hostname", "board:"):
            self.assertNotIn(forbidden, text)

    async def test_invalid_history_returns_correlated_error(self):
        reply = await self.bridge.query_history({"metric": "not_a_metric"})
        self.assertFalse(reply["ok"])
        self.assertEqual(reply["error"]["code"], "invalid_request")
        self.assertTrue((await self.bridge.get_status())["ok"])

    async def test_parallel_requests(self):
        replies = await asyncio.gather(*(self.bridge.get_status() for _ in range(8)))
        self.assertTrue(all(reply["ok"] for reply in replies))

    async def test_supervisor_recovers_after_process_exit(self):
        process = self.bridge.process
        process.kill()
        await process.wait()
        # One bounded test delay; the runtime owns its deterministic restart policy.
        await asyncio.sleep(1.3)
        await asyncio.wait_for(self.bridge.connected.wait(), 5)
        self.assertNotEqual(self.bridge.process.pid, process.pid)
        self.assertTrue((await self.bridge.get_status())["ok"])
