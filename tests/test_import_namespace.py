"""Reproduce module-name collisions in Decky's frozen Python environment."""
import subprocess
import sys
import tempfile
import textwrap
import unittest
from support import ROOT


class ImportNamespaceTests(unittest.TestCase):
    def test_preloaded_host_modules_cannot_shadow_plugin_code(self):
        code = textwrap.dedent('''
            import importlib.util
            import json
            import sys
            import types
            from pathlib import Path

            root, temporary = map(Path, sys.argv[1:])
            # Decky appends py_modules; modules already loaded by the host win
            # for generic names, even if a file of that name exists in the plugin.
            sys.path.append(str(root / "py_modules"))
            host_settings = types.ModuleType("settings")
            host_settings.load = json.load
            host_protocol = types.ModuleType("protocol")
            host_protocol.Channel = object
            host_bridge = types.ModuleType("bridge")
            host_bridge.Bridge = object
            sys.modules.update(settings=host_settings, protocol=host_protocol, bridge=host_bridge)

            decky = types.ModuleType("decky")
            decky.DECKY_PLUGIN_DIR = str(temporary / "plugin")
            decky.DECKY_PLUGIN_RUNTIME_DIR = str(temporary / "data")
            decky.DECKY_PLUGIN_SETTINGS_DIR = str(temporary / "settings")
            sys.modules["decky"] = decky
            spec = importlib.util.spec_from_file_location("scope_facade_fixture", root / "main.py")
            facade = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(facade)
            instance = facade.Bridge()
            assert instance.config["interval_ms"] == 1000
            assert instance.config["privacy_mask"] is True
            assert facade.Bridge.__module__ == "deckscope_bridge"
            import deckscope_bridge
            assert deckscope_bridge.Channel.__module__ == "deckscope_protocol"
            assert deckscope_bridge.settings.__name__ == "deckscope_settings"
            assert sys.modules["settings"] is host_settings
            assert sys.modules["protocol"] is host_protocol
            assert sys.modules["bridge"] is host_bridge
        ''')
        with tempfile.TemporaryDirectory(prefix="scope-import-") as temporary:
            result = subprocess.run(
                [sys.executable, "-I", "-c", code, str(ROOT), temporary],
                capture_output=True, text=True, timeout=5,
            )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_internal_module_filenames_are_namespace_scoped(self):
        names = {path.name for path in (ROOT / "py_modules").glob("*.py")}
        self.assertEqual(names, {
            "deckscope_bridge.py", "deckscope_protocol.py", "deckscope_settings.py",
        })
