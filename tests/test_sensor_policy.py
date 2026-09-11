import tempfile
import time
import unittest
from pathlib import Path
from support import Monitor, fixture, put


class SensorPolicyTests(unittest.TestCase):
    def test_current_voltage_battery_power_when_power_now_is_missing(self):
        with tempfile.TemporaryDirectory(prefix="scope-") as tmp:
            root = Path(tmp) / "fixture"
            fixture(root)
            (root / "sys/class/power_supply/BAT1/power_now").unlink()
            put(root, "sys/class/power_supply/BAT1/current_now", 2000000)
            put(root, "sys/class/power_supply/BAT1/voltage_now", 8000000)
            with Monitor(tmp, root) as monitor:
                data = monitor.request("get_status")["data"]
                self.assertEqual(data["latest"]["battery_rate_mw"], 16000)
                self.assertEqual(data["sources"]["battery_power"], "current_x_voltage")

    def test_nvme_temperature_is_explicitly_cached_not_reread_each_tick(self):
        with tempfile.TemporaryDirectory(prefix="scope-") as tmp:
            root = Path(tmp) / "fixture"
            fixture(root)
            put(root, "sys/class/hwmon/hwmon50/name", "nvme")
            put(root, "sys/class/hwmon/hwmon50/temp1_input", 31500)
            with Monitor(tmp, root) as monitor:
                before = monitor.request("get_status")["data"]
                put(root, "sys/class/hwmon/hwmon50/temp1_input", 80000)
                time.sleep(1.1)
                after = monitor.request("get_status")["data"]
                self.assertGreater(after["samples"], before["samples"])
                self.assertEqual(after["latest"]["nvme_temp_mc"], 31500)
                self.assertEqual(after["sensor_cache"]["nvme_period_ms"], 30000)
                self.assertGreaterEqual(after["sensor_cache"]["nvme_age_ms"], 1000)


class DeviceIdentityTests(unittest.TestCase):
    def test_model_fields_are_read_once_without_serial_identifiers(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "fixture"
            fixture(root)
            put(root, "proc/cpuinfo", "processor : 0\nmodel name : AMD Custom APU\nserial : PRIVATE-SERIAL\n")
            put(root, "sys/class/dmi/id/sys_vendor", "Valve")
            put(root, "sys/class/dmi/id/product_name", "Galileo")
            run = Path(directory) / "run"
            run.mkdir()
            monitor = Monitor(run, root)
            try:
                info = monitor.request("get_device_info")["data"]
                self.assertEqual(info["cpu_model"], "AMD Custom APU")
                self.assertEqual(info["vendor"], "Valve")
                self.assertEqual(info["product"], "Galileo")
                self.assertNotIn("PRIVATE-SERIAL", str(info))
            finally:
                monitor.close()
