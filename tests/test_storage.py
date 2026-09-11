import fcntl
import subprocess
import tempfile
import time
import unittest
from pathlib import Path
from support import BINARY, Monitor, fixture, put


class StorageTests(unittest.TestCase):
    def test_disk_partitions_are_not_double_counted_and_psi_is_delta(self):
        with tempfile.TemporaryDirectory(prefix="scope-") as tmp:
            root = Path(tmp) / "fixture"
            fixture(root)
            (root / "sys/class/block/nvme5n1/device").mkdir(parents=True)
            (root / "sys/class/block/nvme5n1p1/device").mkdir(parents=True)
            put(root, "sys/class/block/nvme5n1p1/partition", 1)
            put(root, "proc/diskstats", "259 0 nvme5n1 1 0 100 0 1 0 200 0\n259 1 nvme5n1p1 1 0 100 0 1 0 200 0\n")
            with Monitor(tmp, root) as monitor:
                time.sleep(1.05)
                monitor.request("get_status")
                put(root, "proc/diskstats", "259 0 nvme5n1 2 0 200 0 2 0 400 0\n259 1 nvme5n1p1 2 0 10000 0 2 0 20000 0\n")
                put(root, "proc/pressure/cpu", "some avg10=0.00 total=100000\nfull total=0\n")
                time.sleep(1.0)
                latest = monitor.request("get_status")["data"]["latest"]
                self.assertGreater(latest["disk_read_kbps"], 25)
                self.assertLess(latest["disk_read_kbps"], 80)
                self.assertGreater(latest["psi_cpu_some_x100"], 500)
                self.assertLess(latest["psi_cpu_some_x100"], 1500)

    def test_history_lock_prevents_second_writer(self):
        with tempfile.TemporaryDirectory(prefix="scope-") as tmp:
            history = Path(tmp) / "history"
            history.mkdir()
            with (history / ".monitor.lock").open("wb") as lock:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                result = subprocess.run([str(BINARY), str(Path(tmp) / "unused.sock"), str(history)], capture_output=True, timeout=3)
                self.assertEqual(result.returncode, 1)
                self.assertIn(b"HistoryAlreadyInUse", result.stderr)

    def test_retention_keeps_only_own_current_day_window(self):
        with tempfile.TemporaryDirectory(prefix="scope-") as tmp:
            root = Path(tmp) / "fixture"
            fixture(root)
            history = Path(tmp) / "history"
            history.mkdir()
            today = int(time.time() // 86400)
            old = history / f"{today - 8}.dscp"
            future = history / f"{today + 1}.dscp"
            unrelated = history / "user-notes.txt"
            for path in (old, future, unrelated):
                path.write_text("fixture")
            with Monitor(tmp, root):
                self.assertFalse(old.exists())
                self.assertFalse(future.exists())
                self.assertTrue(unrelated.exists())
