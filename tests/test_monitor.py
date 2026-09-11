import json
import struct
import tempfile
import time
import unittest
from pathlib import Path
from support import Monitor, fixture, put, update_cpu


class MonitorTests(unittest.TestCase):
    def test_profiles_and_dynamic_topology(self):
        for board, cpus, battery, gpu in [("Jupiter", 8, "BAT1", True), ("Galileo", 8, "BAT1", True), ("Other SteamOS Board", 16, "BAT0", False)]:
            with self.subTest(board=board), tempfile.TemporaryDirectory(prefix="scope-") as tmp:
                root = Path(tmp) / "fixture"
                fixture(root, board, cpus, battery, gpu)
                with Monitor(tmp, root) as monitor:
                    status = monitor.request("get_status")["data"]
                    self.assertEqual(status["cpu_online"], cpus)
                    self.assertEqual(status["latest"]["cpu_mhz"], 2400)
                    self.assertEqual(status["sources"]["battery"], battery)
                    self.assertEqual(status["latest"]["battery_rate_mw"], 14000)
                    self.assertNotIn("cpu_pct_x10", status["latest"])
                    if not gpu:
                        self.assertNotIn("gpu_pct", status["latest"])
                        self.assertNotIn("apu_power_mw", status["latest"])
                    self.assertTrue(monitor.request("get_device_info")["data"]["is_steamos"])

    def test_sampling_live_gate_history_and_recovery(self):
        with tempfile.TemporaryDirectory(prefix="scope-") as tmp:
            root = Path(tmp) / "fixture"
            fixture(root)
            with Monitor(tmp, root) as monitor:
                self.assertFalse(monitor.request("get_status")["data"]["live_push"])
                update_cpu(root, 8, 2)
                time.sleep(1.15)
                status = monitor.request("get_status")["data"]
                self.assertEqual(status["latest"]["cpu_pct_x10"], 200)
                self.assertEqual(monitor.events, [])
                self.assertTrue(monitor.request("set_config", {"live_push": True, "interval_ms": 500})["ok"])
                time.sleep(1.2)
                status = monitor.request("get_status")["data"]
                self.assertGreaterEqual(len(monitor.events), 1)
                self.assertLessEqual(len(monitor.events), 2)
                self.assertTrue(monitor.request("set_config", {"live_push": False})["ok"])
                self.assertFalse(monitor.request("flush")["data"]["persistence_failed"])
                result = monitor.request("query_history", {"metric": "mem_used_mb", "max_points": 1200})
                self.assertTrue(result["data"]["samples"])
            files = list((Path(tmp) / "history").glob("*.dscp"))
            self.assertEqual(len(files), 1)
            data = files[0].read_bytes()
            self.assertEqual(data[:4], b"DSCP")
            self.assertEqual((len(data) - 32) % 128, 0)
            files[0].write_bytes(data + b"broken-tail")
            with Monitor(tmp, root) as monitor:
                status = monitor.request("get_status")["data"]
                self.assertGreater(status["lo_len"], 0)
                self.assertGreater(status["invalid_history_files"], 0)
                time.sleep(1.1)
                monitor.request("flush")
            self.assertEqual((files[0].stat().st_size - 32) % 128, 0)

    def test_invalid_request_unknown_method_and_fragmentation(self):
        with tempfile.TemporaryDirectory(prefix="scope-") as tmp:
            root = Path(tmp) / "fixture"
            fixture(root, "generic", 24, None, False)
            with Monitor(tmp, root) as monitor:
                response = monitor.request("unimplemented")
                self.assertFalse(response["ok"])
                self.assertEqual(response["error"]["code"], "unsupported_method")
                monitor.conn.sendall(b'{"type":"request","id":77,"method":')
                monitor.conn.sendall(b'"get_status"}\n')
                self.assertEqual(monitor.read()["id"], 77)
                monitor.conn.sendall(b'{"type":"request","id":5,"method":"set_config","args":{"interval_ms":0}}\n')
                self.assertFalse(monitor.read()["ok"])
                self.assertTrue(monitor.request("get_status")["ok"])

    def test_charging_is_negative_and_absent_battery_is_unknown(self):
        with tempfile.TemporaryDirectory(prefix="scope-") as tmp:
            root = Path(tmp) / "fixture"
            fixture(root, "Other", 12, "CMB0", False)
            put(root, "sys/class/power_supply/CMB0/status", "Charging")
            with Monitor(tmp, root) as monitor:
                status = monitor.request("get_status")["data"]
                self.assertEqual(status["latest"]["battery_rate_mw"], -14000)
                self.assertEqual(status["sources"]["cpu_temperature"], "coretemp")

    def test_oversize_disconnect_is_bounded(self):
        with tempfile.TemporaryDirectory(prefix="scope-") as tmp:
            root = Path(tmp) / "fixture"
            fixture(root)
            with Monitor(tmp, root) as monitor:
                monitor.conn.sendall(b"x" * (256 * 1024 + 1))
                self.assertEqual(monitor.process.wait(timeout=3), 1)

    def test_gpu_metrics_are_bound_to_selected_card(self):
        with tempfile.TemporaryDirectory(prefix="scope-") as tmp:
            root = Path(tmp) / "fixture"
            fixture(root)
            put(root, "sys/class/hwmon/hwmon0/name", "amdgpu")
            put(root, "sys/class/hwmon/hwmon0/temp1_input", 99000)
            with Monitor(tmp, root) as monitor:
                value = monitor.request("get_status")["data"]["latest"]
                self.assertEqual(value["gpu_temp_mc"], 51000)
                self.assertEqual(value["apu_power_mw"], 8500)

    def test_recent_history_is_visible_before_first_minute(self):
        with tempfile.TemporaryDirectory(prefix="scope-") as tmp:
            root = Path(tmp) / "fixture"
            fixture(root)
            with Monitor(tmp, root) as monitor:
                time.sleep(1.05)
                now = int(time.time() * 1000)
                reply = monitor.request("query_history", {"from": now - 1800000, "to": now, "metric": "mem_used_mb"})
                self.assertGreater(len(reply["data"]["samples"]), 0)

    def test_live_host_network_is_read_only(self):
        with tempfile.TemporaryDirectory(prefix="scope-") as tmp:
            with Monitor(tmp) as monitor:
                time.sleep(0.25)
                info = monitor.request("get_connectivity")["data"]
                self.assertTrue(info["ready"])
                self.assertFalse(info["reachability_verified"])
                self.assertIn("ssh", info)


if __name__ == "__main__":
    unittest.main()
